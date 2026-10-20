import os,pathlib,json,subprocess,time,urllib.request,plistlib,signal,shutil
repo=pathlib.Path.cwd();out=repo/'.artifacts/menu';out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();profile=env['OPENCLAW_PROFILE'];state=pathlib.Path(env['OPENCLAW_STATE_DIR']);state.mkdir(exist_ok=True,parents=True)
port=28765
config={'gateway':{'mode':'local','port':port,'bind':'loopback','auth':{'mode':'none'},'controlUi':{'enabled':True}},'agents':{'defaults':{'workspace':str(state/'workspace')}}}
pathlib.Path(env['OPENCLAW_CONFIG_PATH']).write_text(json.dumps(config))
env['OPENCLAW_GATEWAY_PORT']=str(port)
subprocess.run(['defaults','write',f'ai.openclaw.mac.profile.{profile}','openclaw.onboardingSeen','-bool','true'],env=env,check=True)
subprocess.run(['defaults','write',f'ai.openclaw.mac.profile.{profile}','openclaw.onboardingVersion','-int','8'],env=env,check=True)
subprocess.run(['defaults','write',f'ai.openclaw.mac.profile.{profile}','openclaw.nativeExperienceEnabled','-bool','false'],env=env,check=True)
gateway=None;app=None
try:
  with (out/'gateway.log').open('w') as log:
    gateway=subprocess.Popen(['pnpm','openclaw','gateway','run','--port',str(port),'--bind','loopback','--auth','none'],env=env,stdout=log,stderr=subprocess.STDOUT)
    deadline=time.monotonic()+180
    while True:
      if gateway.poll() is not None:raise RuntimeError(f'Gateway exited before ready: {gateway.returncode}')
      try:
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/',timeout=3) as response:
          document=response.read().decode();assert '<' in document
        break
      except Exception:
        if time.monotonic()>deadline:raise RuntimeError('Gateway readiness timeout')
        time.sleep(1)
    products=repo/'apps/macos/.build/debug'
    built_binary=products/'OpenClaw';assert built_binary.exists()
    bundle=pathlib.Path(env['TMPDIR'])/'OpenClawMenu.app'
    contents=bundle/'Contents';(contents/'MacOS').mkdir(parents=True);(contents/'Resources').mkdir();(contents/'Frameworks').mkdir()
    binary=contents/'MacOS/OpenClaw';shutil.copy2(built_binary,binary)
    info=plistlib.loads((repo/'apps/macos/Sources/OpenClaw/Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='ai.openclaw.mac.debug',SUFeedURL='',SUEnableAutomaticChecks=False,OpenClawGitCommit='9d3ce54df1f00a41e30dae6931ddd57a4c3e1485')
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    for resource in products.glob('*.bundle'):
      shutil.copytree(resource,contents/'Resources'/resource.name,symlinks=True)
    for name in ['GRDB_GRDB.bundle','KeyboardShortcuts_KeyboardShortcuts.bundle','OpenClaw_OpenClaw.bundle','OpenClawKit_OpenClawKit.bundle','OpenClawKit_OpenClawChatUI.bundle','SwiftMath_SwiftMath.bundle']:
      assert (contents/'Resources'/name).is_dir(),f'Missing required normal product resource {name}'
    framework=products/'Sparkle.framework';assert framework.is_dir()
    shutil.copytree(framework,contents/'Frameworks/Sparkle.framework',symlinks=True)
    span=pathlib.Path(env['DEVELOPER_DIR'])/'Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libswiftCompatibilitySpan.dylib'
    if span.exists():shutil.copy2(span,contents/'Frameworks'/span.name)
    subprocess.run(['codesign','--force','--sign','-',str(bundle)],check=True)
    (out/'app-bundle-provenance.json').write_text(json.dumps({'bundleIdentifier':info['CFBundleIdentifier'],'productSource':info['OpenClawGitCommit'],'staging':'verification-only minimal dev .app; ordinary product resources; external separately-owned Gateway; not full distribution package'},indent=2))
    for scenario,native,flag in [('dashboard','false','--dashboard'),('native-transcript','true','--chat')]:
      started=time.monotonic()
      scenario_out=out/scenario;scenario_out.mkdir(exist_ok=True)
      domain=f'ai.openclaw.mac.profile.{profile}'
      subprocess.run(['defaults','write',domain,'openclaw.nativeExperienceEnabled','-bool',native],env=env,check=True)
      subprocess.run(['defaults','write',domain,'openclaw.contentZoom','-float','1'],env=env,check=True)
      appenv=env.copy();appenv['DYLD_INSERT_LIBRARIES']=str(repo/'.artifacts/menu/driver.dylib');appenv['OPENCLAW_MENU_RESULT_ROOT']=str(scenario_out)
      with (scenario_out/'app.log').open('w') as applog:
        app=subprocess.Popen([str(binary),'--attach-only',flag],env=appenv,stdout=applog,stderr=subprocess.STDOUT)
        result=app.wait(timeout=240)
      receipt=plistlib.loads((scenario_out/'result.plist').read_bytes());receipt['duration_seconds']=round(time.monotonic()-started,3);(scenario_out/'result.json').write_text(json.dumps(receipt,indent=2));print(scenario,json.dumps(receipt,indent=2));assert result==0 and receipt['ok']

finally:
  for child in [app,gateway]:
    if child is not None and child.poll() is None:
      child.terminate()
      try:child.wait(timeout=20)
      except subprocess.TimeoutExpired:child.kill();child.wait(timeout=10)
