import AppKit
import Foundation
@testable import OpenClaw
import Testing
import WebKit

/// Only the remaining navigation boundaries; executes in a disposable macOS CI worker.
@Suite(.testWaitLimit)
@MainActor
struct GatewayPickerTargetedGapTests {
    @Test func `attachments isolation retirement and navigation`() async throws {
        let config = try #require(ProcessInfo.processInfo.environment["OPENCLAW_CONFIG_PATH"])
        let configuration: [String: Any] = ["gateway": ["mode": "remote", "remote": [
            "transport": "direct", "url": "ws://127.0.0.1:19876",
        ]]]
        try JSONSerialization.data(withJSONObject: configuration).write(to: URL(fileURLWithPath: config))
        try await withIsolatedWebChatManager { _ in
            let manager = WebChatManager.shared
            defer { manager.close() }
            let state = AppStateStore.shared
            let previousExperience = state.nativeExperienceEnabled
            let previousRenderer = AppDefaults.standard.bool(forKey: nativeConversationForcedKey)
            state.nativeExperienceEnabled = true
            AppDefaults.standard.set(false, forKey: nativeConversationForcedKey)
            defer {
                state.nativeExperienceEnabled = previousExperience
                AppDefaults.standard.set(previousRenderer, forKey: nativeConversationForcedKey)
            }
            let store = MacGatewayProfileStore.shared
            var profiles: [MacGatewayProfile] = []
            for (name, port) in [("Proof A", 19878), ("Proof B", 19879)] {
                let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
                let attempt = try await store.beginBrowserSignIn(url: url)
                try await profiles.append(store.saveConnection(name: name, token: nil, password: nil, attempt: attempt))
            }
            let targetA = DashboardGatewayTarget.profile(profiles[0].id)
            let targetB = DashboardGatewayTarget.profile(profiles[1].id)
            let prior = Set(NSApp.windows.map(ObjectIdentifier.init))
            await manager.openGatewayWindow(for: targetB, newWindow: true,
                                            route: .init(sessionKey: "agent:main:proof-independent-b", agentID: "main")).value
            let independentWindow = try Self.newChatWindow(excluding: prior)
            let independent = try #require(independentWindow.delegate as? WebChatSwiftUIWindowController)
            let independentWeb = try await Self.readyWeb(in: independentWindow)
            try await Self.populate("agent:main:proof-independent-b", marker: "INDEPENDENT B HISTORY", web: independentWeb)
            try await GatewayPickerForkProofTests.setDraft("Independent B draft", in: independentWeb)
            try await Self.attach("independent-b.txt", in: independentWeb)
            let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
            await manager.openGatewayWindow(for: targetA, newWindow: true,
                                            route: .init(sessionKey: "agent:main:proof-a", agentID: "main")).value
            let window = try Self.newChatWindow(excluding: existing)
            let sourceA = try #require(window.delegate as? WebChatSwiftUIWindowController)
            let frame = window.frame
            let visible = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
            let webA = try await Self.readyWeb(in: window)
            try await Self.populate("agent:main:proof-a", marker: "A ONLY HISTORY", web: webA)
            try await GatewayPickerForkProofTests.setDraft("A retained draft", in: webA)
            try await Self.attach("a-only.txt", in: webA)
            let primary = state.primaryGatewaySnapshot()
            try await GatewayPickerForkProofTests.capture(window, web: webA, name: "picker-gap-a")
            try await GatewayPickerForkProofTests.selectGateway("Proof B", in: window)
            try await TestWait.state("A to B controller replacement") { window.delegate !== sourceA }
            let sourceB = try #require(window.delegate as? WebChatSwiftUIWindowController)
            let webB = try await Self.readyWeb(in: window)
            let keyB = sourceB.currentRoute.sessionKey
            #expect(keyB != "agent:main:proof-a")
            #expect(keyB != "agent:main:proof-independent-b")
            try await Self.populate(keyB, marker: "B ONLY HISTORY", web: webB)
            try await GatewayPickerForkProofTests.setDraft("B retained draft", in: webB)
            try await Self.attach("b-only.txt", in: webB)
            #expect(window.frame == frame)
            #expect(Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init)) == visible)
            try await Self.assertIndependent(independent, window: independentWindow, web: independentWeb)
            try await GatewayPickerForkProofTests.capture(window, web: webB, name: "picker-gap-b")
            try await GatewayPickerForkProofTests.selectGateway("Proof A", in: window)
            try await TestWait.state("B to A retained controller") { window.delegate === sourceA }
            #expect(sourceA.currentRoute.sessionKey == "agent:main:proof-a")
            #expect(try await GatewayPickerForkProofTests.draft(in: webA) == "A retained draft")
            #expect(try await Self.attachmentNames(webA) == ["a-only.txt"])
            try await Self.assertHistory("agent:main:proof-a", contains: "A ONLY HISTORY", excludes: "B ONLY HISTORY", web: webA)
            try await GatewayPickerForkProofTests.capture(window, web: webA, name: "picker-gap-a-return")
            try await Self.checkEmbeddedShortcuts(manager: manager, targetA: targetA, targetB: targetB,
                                                  window: window, sourceA: sourceA, sourceB: sourceB, webA: webA, webB: webB)
            try await Self.retireAWhileBIsDisplayed(
                profiles[0], manager: manager, sourceA: sourceA, sourceB: sourceB,
                window: window, webA: webA, webB: webB, targetA: targetA
            )
            #expect(window.delegate === sourceB)
            #expect(sourceB.currentRoute.sessionKey == keyB)
            #expect(try await GatewayPickerForkProofTests.draft(in: webB) == "B retained draft")
            #expect(try await Self.attachmentNames(webB) == ["b-only.txt"])
            try await Self.assertHistory(keyB, contains: "B ONLY HISTORY", excludes: "A ONLY HISTORY", web: webB)
            try await Self.assertIndependent(independent, window: independentWindow, web: independentWeb)
            try await GatewayPickerForkProofTests.capture(window, web: webB, name: "picker-gap-retired")
            try await Self.checkNavigation(manager: manager, targetB: targetB, window: window, webB: webB)
            #expect(state.isCurrentPrimaryGateway(primary))
            try await store.remove(profileID: profiles[1].id)
            print("TARGETED_GAPS_PASSED: embedded A-B-A histories/drafts/attachments; independent B; real-owner A retirement while B displayed; held pre-dispatch web action rejected with no A request; B mutation succeeds; new window and ordinary open/focus; primary unchanged. No model generation.")
        }
    }

    private static func checkEmbeddedShortcuts(
        manager: WebChatManager, targetA: DashboardGatewayTarget, targetB: DashboardGatewayTarget,
        window: NSWindow, sourceA: WebChatSwiftUIWindowController, sourceB: WebChatSwiftUIWindowController,
        webA: WKWebView, webB: WKWebView
    ) async throws {
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Gateways"), action: nil, keyEquivalent: "")
        NSApp.mainMenu = menu
        let entries = [
            DashboardGatewayEntry(id: targetA.bridgeID, name: "Proof A", kind: "remote", isPrimary: true, canPromote: false, health: .unknown),
            DashboardGatewayEntry(id: targetB.bridgeID, name: "Proof B", kind: "remote", isPrimary: false, canPromote: false, health: .unknown),
        ]
        let owner = GatewaysMainMenu(gatewayEntries: { entries }, currentWindow: { window })
        owner.install()
        let frame = window.frame
        for (key, code, web, expected) in [("2", UInt16(19), webA, sourceB), ("1", UInt16(18), webB, sourceA)] {
            try await pressInComposer(key, code: code, modifiers: [.command], window: window, web: web)
            try await TestWait.state("embedded composer command shortcut switches same window") { window.delegate === expected }
            #expect(window.frame == frame)
        }
        #expect(try await GatewayPickerForkProofTests.draft(in: webA) == "A retained draft")
        #expect(try await attachmentNames(webA) == ["a-only.txt"])
        #expect(try await GatewayPickerForkProofTests.draft(in: webB) == "B retained draft")
        #expect(try await attachmentNames(webB) == ["b-only.txt"])
        let prior = Set(NSApp.windows.map(ObjectIdentifier.init))
        let count = manager.openWindowCount(for: targetB)
        try await pressInComposer("2", code: 19, modifiers: [.command, .option], window: window, web: webA)
        try await TestWait.state("embedded composer option-command shortcut opens independent window") { manager.openWindowCount(for: targetB) == count + 1 }
        #expect(window.delegate === sourceA)
        let extra = try newChatWindow(excluding: prior)
        #expect(extra !== window)
        extra.close()
        print("EMBEDDED_SHORTCUTS_PASSED: focused real textarea; NSApp key dispatch Cmd-2/Cmd-1 and Option-Cmd-2.")
    }

    private static func pressInComposer(_ key: String, code: UInt16, modifiers: NSEvent.ModifierFlags, window: NSWindow, web: WKWebView) async throws {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(web)
        #expect(try await web.evaluateJavaScript("document.querySelector('textarea').focus(); document.activeElement === document.querySelector('textarea')") as? Bool == true)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                                  characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
        NSApp.sendEvent(event)
    }

    private static func newChatWindow(excluding old: Set<ObjectIdentifier>) throws -> NSWindow {
        try #require(NSApp.windows.first { !old.contains(ObjectIdentifier($0)) && $0.isVisible && $0.delegate is WebChatSwiftUIWindowController })
    }

    private static func readyWeb(in window: NSWindow) async throws -> WKWebView {
        let web = try await GatewayPickerForkProofTests.readyWeb(in: window)
        // Instrument the existing WK configuration, then reload unchanged production UI.
        // Capture its real WebSocket; do not inject a substitute Gateway client.
        web.configuration.userContentController.addUserScript(WKUserScript(source: """
        window.__proofSockets = [];
        window.WebSocket = new Proxy(window.WebSocket, {construct(Target,args) {
          const socket = new Target(...args); window.__proofSockets.push(socket); return socket;
        }});
        window.__proofRequest = (socket,method,params) => new Promise((resolve,reject) => {
          const id = crypto.randomUUID();
          const receive = event => { const frame=JSON.parse(event.data); if(frame.id !== id) return;
            socket.removeEventListener('message',receive);
            frame.ok ? resolve(frame.payload) : reject(new Error(JSON.stringify(frame.error))); };
          socket.addEventListener('message',receive);
          socket.addEventListener('close',()=>reject(new Error('Retired real socket')), {once:true});
          try { socket.send(JSON.stringify({type:'req',id,method,params})); }
          catch(error) { reject(error); }
        });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web.reload()
        try await TestWait.state("real connected web Gateway client") {
            await (try? web.evaluateJavaScript("window.openclawControlUi?.diagnostics().gateway.phase === 'connected' && window.__proofSockets?.some(s=>s.readyState===1)")) as? Bool == true
        }
        return web
    }

    @discardableResult
    private static func rpc(_ method: String, _ params: [String: Any], web: WKWebView) async throws -> Any? {
        try await web.callAsyncJavaScript(
            "return await window.__proofRequest(window.__proofSockets.find(s=>s.readyState===1),method,params);",
            arguments: ["method": method, "params": params], in: nil, contentWorld: .page
        )
    }

    private static func populate(_ key: String, marker: String, web: WKWebView) async throws {
        _ = try await rpc("sessions.create", ["agentId": "main", "key": key], web: web)
        _ = try await rpc("chat.inject", ["sessionKey": key, "message": marker], web: web)
        try await assertHistory(key, contains: marker, excludes: "NOT A FIXTURE MESSAGE", web: web)
    }

    private static func assertHistory(_ key: String, contains marker: String, excludes other: String, web: WKWebView) async throws {
        let result = try await rpc("chat.history", ["sessionKey": key], web: web)
        let text = String(describing: result)
        #expect(text.contains(marker))
        #expect(!text.contains(other))
        try await TestWait.state("rendered conversation history \(marker)") {
            try await web.callAsyncJavaScript(
                "return document.body.textContent.includes(marker) && !document.body.textContent.includes(other);",
                arguments: ["marker": marker, "other": other], in: nil, contentWorld: .page
            ) as? Bool == true
        }
    }

    private static func attach(_ name: String, in web: WKWebView) async throws {
        _ = try await web.callAsyncJavaScript("""
        const data = new DataTransfer();
        data.items.add(new File(['navigation proof attachment'], name, {type:'text/plain'}));
        const chat = document.querySelector('section.chat');
        if (!chat) throw new Error('Missing real chat drop target');
        chat.dispatchEvent(new DragEvent('drop', {bubbles:true, cancelable:true, dataTransfer:data}));
        """, arguments: ["name": name], in: nil, contentWorld: .page)
        try await TestWait.state("attachment \(name) owned by real composer") {
            try await attachmentNames(web).contains(name)
        }
    }

    private static func attachmentNames(_ web: WKWebView) async throws -> [String] {
        try #require(try await web.evaluateJavaScript(
            "Array.from(document.querySelectorAll('.chat-attachment-file__name')).map(e=>e.textContent.trim())"
        ) as? [String])
    }

    private static func assertIndependent(_ controller: WebChatSwiftUIWindowController, window: NSWindow, web: WKWebView) async throws {
        #expect(controller._testWindow === window)
        #expect(controller.currentRoute.sessionKey == "agent:main:proof-independent-b")
        #expect(try await GatewayPickerForkProofTests.draft(in: web) == "Independent B draft")
        #expect(try await attachmentNames(web) == ["independent-b.txt"])
        try await assertHistory("agent:main:proof-independent-b", contains: "INDEPENDENT B HISTORY", excludes: "A ONLY HISTORY", web: web)
    }

    private static func patchCount(_ gateway: String) async throws -> Int {
        let url = try #require(URL(string: "http://127.0.0.1:19880/receipts"))
        let (data, _) = try await URLSession.shared.data(from: url)
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(payload["requests"] as? [[String: String]])
        return rows.filter { $0["gateway"] == gateway && $0["method"] == "sessions.patch" }.count
    }

    private static func liveSockets(_ gateway: String) async throws -> Int {
        let url = try #require(URL(string: "http://127.0.0.1:19880/receipts"))
        let (data, _) = try await URLSession.shared.data(from: url)
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let connections = try #require(payload["connections"] as? [String: [String: Int]])
        return try #require(connections[gateway]?["live"])
    }

    private static func rename(_ label: String, key: String, web: WKWebView) async throws {
        _ = try await rpc("sessions.patch", ["key": key, "label": label], web: web)
    }

    private static func retireAWhileBIsDisplayed(
        _ profile: MacGatewayProfile, manager: WebChatManager,
        sourceA: WebChatSwiftUIWindowController, sourceB: WebChatSwiftUIWindowController,
        window: NSWindow, webA: WKWebView, webB: WKWebView, targetA: DashboardGatewayTarget
    ) async throws {
        let beforeA = try await patchCount("A")
        let beforeB = try await patchCount("B")
        try await rename("A live action", key: "agent:main:proof-a", web: webA)
        #expect(try await patchCount("A") == beforeA + 1)
        #expect(try await patchCount("B") == beforeB)
        let gate = PickerPreDispatchGate()
        webA.configuration.userContentController.addScriptMessageHandler(gate, contentWorld: .page, name: "proofBeforeDispatch")
        let heldSelect = sourceA.gatewaySelection.select
        // The actual A document captures its actual Gateway client before awaiting our barrier.
        // No RPC request is sent until Swift releases the reply, after profile-owner retirement.
        let held = Task { @MainActor in
            do {
                _ = try await webA.callAsyncJavaScript("""
                const socket = window.__proofSockets.find(s=>s.readyState===1);
                const request = window.__proofRequest.bind(null,socket);
                await window.webkit.messageHandlers.proofBeforeDispatch.postMessage({stage:'held-before-dispatch'});
                return await request('sessions.patch', {key:'agent:main:proof-a',label:'STALE A MUST NOT COMMIT'});
                """, in: nil, contentWorld: .page)
                return false
            } catch {
                print("HELD_A_ACTION_REJECTED: \((error as NSError).domain) code=\((error as NSError).code)")
                return true
            }
        }
        await gate.entered.wait()
        var failure: (any Error)?
        do {
            #expect(try await patchCount("A") == beforeA + 1)
            try await GatewayPickerForkProofTests.selectGateway("Proof B", in: window)
            try await TestWait.state("B displayed for A retirement") { window.delegate === sourceB }
            try await MacGatewayProfileStore.shared.remove(profileID: profile.id)
            #expect(sourceA._testWindow == nil)
            #expect(sourceA.gatewaySelection.select == nil)
            #expect(heldSelect?(targetA) == nil)
            #expect(manager.openWindowCount(for: targetA) == 0)
            try await TestWait.state("retired A document cannot execute") { webA.url?.absoluteString == "about:blank" }
            try await TestWait.state("actual A transport retired") { try await liveSockets("A") == 0 }
            try await rename("B remains usable after A retirement", key: sourceB.currentRoute.sessionKey, web: webB)
        } catch { failure = error }
        gate.release()
        #expect(await held.value)
        webA.configuration.userContentController.removeScriptMessageHandler(forName: "proofBeforeDispatch", contentWorld: .page)
        if let failure {
            throw failure
        }
        try await rename("B usable after held A release", key: sourceB.currentRoute.sessionKey, web: webB)
        #expect(try await patchCount("A") == beforeA + 1)
        #expect(try await patchCount("B") == beforeB + 2)
        print("NETWORK_RECEIPTS: A sessions.patch stayed at \(beforeA + 1) after held release; B advanced to \(beforeB + 2).")
    }

    private static func views<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { views(type, in: $0) }
    }

    private static func checkNavigation(manager: WebChatManager, targetB: DashboardGatewayTarget, window: NSWindow, webB: WKWebView) async throws {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let count = manager.openWindowCount(for: targetB)
        // This is the real explicit New Gateway Window chooser, not a direct manager shortcut.
        AppNavigationActions.newGatewayWindow()
        var alertWindow: NSWindow?
        try await TestWait.state("New Gateway Window chooser") {
            alertWindow = NSApp.windows.first { candidate in
                guard let content = candidate.contentView else { return false }
                return views(NSTextField.self, in: content).contains { $0.stringValue == "New Gateway Window" }
            }
            return alertWindow != nil
        }
        let content = try #require(alertWindow?.contentView)
        let popup = try #require(views(NSPopUpButton.self, in: content).first)
        popup.selectItem(withTitle: "Proof B")
        try #require(views(NSButton.self, in: content).first { $0.title == "Open Window" }).performClick(nil)
        try await TestWait.state("explicit new B window") { manager.openWindowCount(for: targetB) == count + 1 }
        let extra = try Self.newChatWindow(excluding: before)
        let extraWeb = try await Self.readyWeb(in: extra)
        #expect(extra !== window)
        #expect(try await GatewayPickerForkProofTests.draft(in: webB) == "B retained draft")
        try await GatewayPickerForkProofTests.capture(extra, web: extraWeb, name: "picker-gap-new-window")
        extra.close()
        manager.hideWindows()
        #expect(!manager.hasVisibleWindows)
        // AppDelegate's ordinary reopen and Dock Open Dashboard both use this production action.
        AppNavigationActions.openDashboard(userGesture: true)
        try await TestWait.state("ordinary reopen focuses existing B") { manager.hasVisibleWindows }
        #expect(manager.frontmostGatewayTarget == targetB)
        #expect(manager.openWindowCount(for: targetB) == count)
        #expect(try await GatewayPickerForkProofTests.draft(in: webB) == "B retained draft")
    }
}

@MainActor
private final class PickerPreDispatchGate: NSObject, WKScriptMessageHandlerWithReply {
    let entered = AsyncTestGate()
    private var heldReply: (@MainActor (Any?, String?) -> Void)?

    func userContentController(_: WKUserContentController, didReceive _: WKScriptMessage,
                               replyHandler: @escaping @MainActor (Any?, String?) -> Void)
    {
        heldReply = replyHandler
        entered.open()
    }

    func release() {
        let reply = heldReply
        heldReply = nil
        reply?(["released": true], nil)
    }
}
