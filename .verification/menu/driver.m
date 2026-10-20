#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>
#include <unistd.h>
#include <math.h>
static NSString *root;
static NSMutableArray *checks;
static WKWebView *web;
static NSWindow *window;
static int attempts;
static void fail(NSString *why) {
  NSLog(@"MENU_HARNESS_FAILED %@", why);
  [@{@"ok":@NO,@"failure":why,@"checks":checks ?: @[]} writeToURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"result.plist"]] atomically:YES];
  _exit(1);
}
static void checkCondition(BOOL value, NSString *name) {
  if (!value) fail(name);
  [checks addObject:name]; NSLog(@"MENU_HARNESS_CHECK %@",name);
}
static WKWebView *findWeb(NSView *view) {
  if (view.isHidden) return nil;
  if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
  for (NSView *child in view.subviews) { WKWebView *found=findWeb(child); if(found)return found; }
  return nil;
}
static NSMenu *viewMenu(void) {
  for(NSMenuItem *item in NSApp.mainMenu.itemArray) if([item.title isEqual:@"View"])return item.submenu;
  return nil;
}
static void menu(NSString *name) {
  NSMenu *owner=viewMenu(); checkCondition(owner!=nil,@"actual SwiftUI View menu exists");
  NSInteger i=[owner indexOfItemWithTitle:name]; checkCondition(i>=0,[NSString stringWithFormat:@"actual View/%@ is registered",name]);
  [owner update]; checkCondition([owner itemAtIndex:i].enabled,[name stringByAppendingString:@" is enabled"]);
  [owner performActionForItemAtIndex:i];
}
static void capture(NSString *name, dispatch_block_t next) {
  WKSnapshotConfiguration *config=[WKSnapshotConfiguration new]; config.afterScreenUpdates=YES;
  [web takeSnapshotWithConfiguration:config completionHandler:^(NSImage *image,NSError *error){
    if(error||!image)fail([NSString stringWithFormat:@"product web snapshot %@: %@",name,error]);
    NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    checkCondition([png writeToFile:[root stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES],@"actual product web snapshot saved");
    NSTask *shot=[NSTask new];shot.executableURL=[NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
    shot.arguments=@[@"-x",@"-l",[NSString stringWithFormat:@"%ld",(long)window.windowNumber],[root stringByAppendingPathComponent:[name stringByAppendingString:@"-native-window.png"]]];
    NSError *shotError=nil;
    BOOL launched=[shot launchAndReturnError:&shotError];if(launched)[shot waitUntilExit];
    [@{@"launched":@(launched),@"exit":@(launched?shot.terminationStatus:-1),@"error":shotError.description?:@""} writeToFile:[root stringByAppendingPathComponent:[name stringByAppendingString:@"-native-window-status.plist"]] atomically:YES];
    next();
  }];
}
static void key(NSString *characters,NSEventModifierFlags modifiers, dispatch_block_t next) {
  unsigned short code=[characters isEqual:@"-"]?27:[characters isEqual:@"0"]?29:24;
  NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
  checkCondition(event!=nil,@"application-level key event constructed");
  [NSApp postEvent:event atStart:NO];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),next);
}
static void runKeys(void) {
  menu(@"Actual Size");checkCondition(fabs(web.pageZoom-1)<0.001,@"View Actual Size resets real product to 100%");
  key(@"=",NSEventModifierFlagCommand,^{
    checkCondition(fabs(web.pageZoom-1.1)<0.001,@"NSApplication queue Cmd+= changes real product to 110%");
    key(@"+",NSEventModifierFlagCommand|NSEventModifierFlagShift,^{
      checkCondition(fabs(web.pageZoom-1.2)<0.001,@"NSApplication queue Cmd++ changes real product to 120%");
      key(@"-",NSEventModifierFlagCommand,^{
        checkCondition(fabs(web.pageZoom-1.1)<0.001,@"NSApplication queue Cmd- changes real product to 110%");
        key(@"0",NSEventModifierFlagCommand,^{
          checkCondition(fabs(web.pageZoom-1)<0.001,@"NSApplication queue Cmd0 changes real product to 100%");
          menu(@"Zoom In"); checkCondition(fabs(web.pageZoom-1.1)<0.001,@"View Zoom In changes actual product");
          menu(@"Zoom Out"); checkCondition(fabs(web.pageZoom-1)<0.001,@"View Zoom Out changes actual product");
          for(int i=0;i<20;i++)menu(@"Zoom Out");checkCondition(fabs(web.pageZoom-.5)<0.001,@"actual View actions clamp to 50%");
          for(int i=0;i<20;i++)menu(@"Zoom In");checkCondition(fabs(web.pageZoom-2)<0.001,@"actual View actions clamp to 200%");
          NSString *profile=NSProcessInfo.processInfo.environment[@"OPENCLAW_PROFILE"];
          NSUserDefaults *defaults=[[NSUserDefaults alloc]initWithSuiteName:[@"ai.openclaw.mac.profile." stringByAppendingString:profile]];
          checkCondition(fabs([defaults doubleForKey:@"openclaw.contentZoom"]-2)<.001,@"profile-local preference records 200%");
          capture(@"product-after-200",^{
            [@{@"ok":@YES,@"checks":checks,@"view":@"actual product Control UI WKWebView; scenario recorded by parent artifact directory",@"inputBoundary":@"actual registered SwiftUI menu actions; NSApplication posted event queue; not physical hardware"} writeToURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"result.plist"]] atomically:YES];
            [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
          });
        });
      });
    });
  });
}
static void poll(void) {
  if(++attempts>180)fail(@"actual app did not expose a visible loaded Dashboard WKWebView and View menu within 180 seconds");
  for(NSWindow *candidate in NSApp.windows) {
    WKWebView *found=findWeb(candidate.contentView);
    if(found&&!found.loading&&found.URL) {
      window=candidate;web=found;
      [window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
      if(NSApp.keyWindow!=window)continue;
      [web evaluateJavaScript:@"({title:document.title,body:document.body.innerText.slice(0,500),href:location.href,product:!!document.querySelector('openclaw-app-shell,openclaw-chat-pane,textarea,[contenteditable=\"true\"]')})" completionHandler:^(id result,NSError *error){
        if(error||![result isKindOfClass:NSDictionary.class]||![result[@"product"] boolValue]) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{poll();});return; }
        [result writeToFile:[root stringByAppendingPathComponent:@"product-document.plist"] atomically:YES];
        checkCondition(viewMenu()!=nil,@"actual application SwiftUI View menu is installed");
        checkCondition([result[@"title"] length]>0,@"actual product document has title");
        checkCondition([result[@"body"] length]>20,@"actual product document rendered text");
        capture(@"product-before-100",^{runKeys();});
      }];return;
    }
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{poll();});
}
__attribute__((constructor)) static void initialize(void) {
  root=NSProcessInfo.processInfo.environment[@"OPENCLAW_MENU_RESULT_ROOT"];
  if(!root||![NSProcessInfo.processInfo.processName isEqual:@"OpenClaw"])return;
  checks=[NSMutableArray new];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{poll();});
}
