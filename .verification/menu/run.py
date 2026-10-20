import os,pathlib,json,subprocess,time,urllib.request,plistlib,signal
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
    gateway=subprocess.Popen(['node','openclaw.mjs','gateway','run','--port',str(port),'--bind','loopback','--auth','none'],env=env,stdout=log,stderr=subprocess.STDOUT)
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
    binary=repo/'apps/macos/.build/debug/OpenClaw';assert binary.exists()
    for scenario,native,flag in [('dashboard','false','--dashboard'),('native-transcript','true','--chat')]:
      scenario_out=out/scenario;scenario_out.mkdir(exist_ok=True)
      domain=f'ai.openclaw.mac.profile.{profile}'
      subprocess.run(['defaults','write',domain,'openclaw.nativeExperienceEnabled','-bool',native],env=env,check=True)
      subprocess.run(['defaults','write',domain,'openclaw.contentZoom','-float','1'],env=env,check=True)
      appenv=env.copy();appenv['DYLD_INSERT_LIBRARIES']=str(repo/'.artifacts/menu/driver.dylib');appenv['OPENCLAW_MENU_RESULT_ROOT']=str(scenario_out)
      with (scenario_out/'app.log').open('w') as applog:
        app=subprocess.Popen([str(binary),'--attach-only',flag],env=appenv,stdout=applog,stderr=subprocess.STDOUT)
        result=app.wait(timeout=240)
      receipt=plistlib.loads((scenario_out/'result.plist').read_bytes());print(scenario,json.dumps(receipt,indent=2));assert result==0 and receipt['ok']

finally:
  for child in [app,gateway]:
    if child is not None and child.poll() is None:
      child.terminate()
      try:child.wait(timeout=20)
      except subprocess.TimeoutExpired:child.kill();child.wait(timeout=10)
