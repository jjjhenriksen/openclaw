import AppKit
import Foundation
@testable import OpenClaw
import Testing
import WebKit

/// Fork-only proof: production macOS windows and real loopback Gateway Control UI.
@Suite(.testWaitLimit)
@MainActor
struct GatewayPickerForkProofTests {
    @Test func `embedded conversation switch and retirement`() async throws {
        try await withIsolatedWebChatManager { manager in
            let previous = AppDefaults.standard.bool(forKey: nativeConversationForcedKey)
            AppDefaults.standard.set(false, forKey: nativeConversationForcedKey)
            defer { AppDefaults.standard.set(previous, forKey: nativeConversationForcedKey) }
            let store = MacGatewayProfileStore.shared
            var profiles: [MacGatewayProfile] = []
            for (name, port) in [("Proof A", 19876), ("Proof B", 19877)] {
                let attempt = try await store.beginBrowserSignIn(url: URL(string: "ws://127.0.0.1:\(port)")!)
                try await profiles.append(store.saveConnection(name: name, token: nil, password: nil, attempt: attempt))
            }
            let targetA = DashboardGatewayTarget.profile(profiles[0].id)
            let targetB = DashboardGatewayTarget.profile(profiles[1].id)
            await manager.openGatewayWindow(for: targetB, newWindow: true).value
            let independentWindow = try #require(NSApp.windows.first { $0.isVisible && $0.delegate is WebChatSwiftUIWindowController })
            let independent = try #require(independentWindow.delegate as? WebChatSwiftUIWindowController)
            let independentWeb = try await Self.readyWeb(in: independentWindow)
            try await Self.setDraft("Independent B draft", in: independentWeb)
            let priorWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
            await manager.openGatewayWindow(for: targetA, newWindow: true).value
            let window = try #require(NSApp.windows.first { !priorWindows.contains(ObjectIdentifier($0)) && $0.isVisible })
            let source = try #require(window.delegate as? WebChatSwiftUIWindowController)
            let frame = window.frame
            let visible = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
            let webA = try await Self.readyWeb(in: window)
            try await Self.setDraft("Retained A draft", in: webA)
            try await Self.capture(window, web: webA, name: "picker-a")
            try await Self.selectGateway("Proof B", in: window)
            try await TestWait.state("picker window replacement") { window.delegate !== source }
            let destination = try #require(window.delegate as? WebChatSwiftUIWindowController)
            let webB = try await Self.readyWeb(in: window)
            #expect(destination !== source)
            #expect(destination._testWindow === window)
            #expect(window.frame == frame)
            #expect(Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init)) == visible)
            #expect(try await Self.draft(in: webB) != "Independent B draft")
            try await Self.setDraft("Retained switched B draft", in: webB)
            try await Self.capture(window, web: webB, name: "picker-b")
            try await Self.selectGateway("Proof A", in: window)
            try await TestWait.state("return to retained A") { window.delegate === source }
            #expect(window.delegate === source)
            #expect(try await Self.draft(in: webA) == "Retained A draft")
            #expect(try await Self.draft(in: independentWeb) == "Independent B draft")
            #expect(independent._testWindow === independentWindow)
            try await Self.capture(window, web: webA, name: "picker-a-return")
            // Real profile-store removal must retire B even while retained behind A.
            try await store.remove(profileID: profiles[1].id)
            #expect(destination.gatewaySelection.select == nil)
            #expect(!independent.isWindowOpen)
            #expect(window.delegate === source)
            try await TestWait.state("retired embedded B document") {
                await (try? webB.evaluateJavaScript("document.querySelector('textarea') === null")) as? Bool == true
            }
            #expect(manager.openWindowCount(for: targetB) == 0)
            try await Self.capture(window, web: webA, name: "picker-retired")
            try await store.remove(profileID: profiles[0].id)
            print("FORK_PROOF: real embedded A-B-A through native menu, same window/frame, independent B draft, real profile removal passed. No held-network-action proof.")
        }
    }

    static func selectGateway(_ name: String, in window: NSWindow) async throws {
        try await AppKitTestSupport.startApplication()
        let button = try await AppKitTestSupport.waitForAccessibilityElement(
            in: window, description: "Gateway identity menu",
        ) { elements in
            elements.first { $0.accessibilityIdentifier?() == "chat-sidebar-identity" }
        }
        try await AppKitTestSupport.openMenu(button, in: window) { menu in
            let index = try #require(menu.items.firstIndex { $0.title == name })
            try AppKitTestSupport.record(menu: menu, content: window.contentView, name: name == "Proof A" ? "picker-menu-a" : "picker-menu-b")
            menu.performActionForItem(at: index)
            menu.cancelTracking()
        }
    }

    private static func webViews(in view: NSView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap { webViews(in: $0) }
    }

    static func readyWeb(in window: NSWindow) async throws -> WKWebView {
        print("FORK_PROOF: waiting for embedded composer in window \(window.windowNumber)")
        try await TestWait.state("real embedded web composer") {
            guard let content = window.contentView else { return false }
            for web in webViews(in: content) {
                if await (try? web.evaluateJavaScript("!!document.querySelector('textarea')")) as? Bool == true {
                    return true
                }
            }
            return false
        }
        let content = try #require(window.contentView)
        for web in webViews(in: content) {
            if await (try? web.evaluateJavaScript("!!document.querySelector('textarea')")) as? Bool == true {
                return web
            }
        }
        throw CocoaError(.fileReadUnknown)
    }

    static func draft(in web: WKWebView) async throws -> String {
        try #require(try await web.evaluateJavaScript("document.querySelector('textarea')?.value") as? String)
    }

    static func setDraft(_ text: String, in web: WKWebView) async throws {
        let literal = try String(decoding: JSONEncoder().encode(text), as: UTF8.self)
        _ = try await web.evaluateJavaScript("{ const input=document.querySelector('textarea'); input.value=\(literal); input.dispatchEvent(new Event('input',{bubbles:true})); }")
        #expect(try await draft(in: web) == text)
    }

    static func capture(_ window: NSWindow, web: WKWebView, name: String) async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["OPENCLAW_TEST_MENU_CAPTURE_DIR"])
        let output = URL(fileURLWithPath: directory)
        window.contentView?.layoutSubtreeIfNeeded()
        let view = try #require(window.contentView?.superview)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("\(name)-window.png"))
        let image = try await web.takeSnapshot(configuration: nil)
        let webBitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(webBitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("\(name)-menu-0.png"))
    }
}
