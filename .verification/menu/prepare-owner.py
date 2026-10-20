from pathlib import Path
source=Path('scripts/test-macos-native.mts').read_text()
old='''        process.exitCode = await run("swift", [
          "test",
          ...args,
          "--event-stream-output-path",
          eventStreamPath,
          "--event-stream-version",
          "6.3",
        ]);'''
new='''        // Verification-only overlay: same resource/process owner, real product app driver.
        // This is NOT a Swift test invocation and has no Swift Testing event stream.
        process.exitCode = await run("python3", [".verification/menu/run.py"], 480_000);'''
assert source.count(old)==1
source=source.replace(old,new)
start=source.index('      if (process.exitCode === 0) {\n        try {\n          validateSwiftTestingCompletion(eventStreamPath);')
end=source.index('\n    } finally {',start)
source=source[:start]+'''      // The Python product-host driver validates its independent result.plist and
      // exits nonzero on timeout, setup failure, missing receipt, or failed assertion.
'''+source[end:]
Path('scripts/test-macos-menu-owned.mts').write_text(source)
