import AppKit
import Foundation
@testable import OpenClaw
import Testing
import WebKit

/// Fork-only baseline reproduction, expected to observe the pre-fix extra window.
@Suite(.testWaitLimit)
@MainActor
struct GatewayPickerBaselineProofTests {
    @Test func `pre fix menu opens an extra window`() async throws {
        try await withIsolatedWebChatManager { _ in
            let manager = WebChatManager.shared
            defer { manager.close() }
            let oldExperience = AppStateStore.shared.nativeExperienceEnabled
            let oldRenderer = AppDefaults.standard.bool(forKey: nativeConversationForcedKey)
            AppStateStore.shared.nativeExperienceEnabled = true
            AppDefaults.standard.set(false, forKey: nativeConversationForcedKey)
            defer {
                AppStateStore.shared.nativeExperienceEnabled = oldExperience
                AppDefaults.standard.set(oldRenderer, forKey: nativeConversationForcedKey)
            }
            let store = MacGatewayProfileStore.shared
            var profiles: [MacGatewayProfile] = []
            for (name, port) in [("Proof A", 19876), ("Proof B", 19877)] {
                let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
                let attempt = try await store.beginBrowserSignIn(url: url)
                try await profiles.append(store.saveConnection(name: name, token: nil, password: nil, attempt: attempt))
            }
            await manager.openGatewayWindow(for: .profile(profiles[0].id), newWindow: true).value
            let sourceWindow = try #require(NSApp.windows.first { $0.isVisible && $0.delegate is WebChatSwiftUIWindowController })
            let source = try #require(sourceWindow.delegate as? WebChatSwiftUIWindowController)
            let webA = try await Self.readyWeb(in: sourceWindow)
            try await Self.setDraft("Baseline A draft", in: webA)
            let before = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
            try await Self.capture(sourceWindow, web: webA, name: "picker-a")
            try await Self.selectGateway("Proof B", in: sourceWindow)
            try await TestWait.state("baseline extra window after picker") {
                NSApp.windows.contains { $0.isVisible && !before.contains(ObjectIdentifier($0)) }
            }
            let extra = try #require(NSApp.windows.first { $0.isVisible && !before.contains(ObjectIdentifier($0)) })
            let webB = try await Self.readyWeb(in: extra)
            #expect(sourceWindow.delegate === source)
            #expect(manager.openWindowCount(for: .profile(profiles[0].id)) == 1)
            #expect(manager.openWindowCount(for: .profile(profiles[1].id)) == 1)
            #expect(try await Self.draft(in: webA) == "Baseline A draft")
            try await Self.capture(extra, web: webB, name: "picker-b")
            print("BASELINE_REPRODUCED: native picker left A unchanged and opened an extra B window.")
            for profile in profiles {
                try await store.remove(profileID: profile.id)
            }
        }
    }

    private static func selectGateway(_ name: String, in window: NSWindow) async throws {
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

    private static func readyWeb(in window: NSWindow) async throws -> WKWebView {
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

    private static func draft(in web: WKWebView) async throws -> String {
        try #require(try await web.evaluateJavaScript("document.querySelector('textarea')?.value") as? String)
    }

    private static func setDraft(_ text: String, in web: WKWebView) async throws {
        let literal = try String(decoding: JSONEncoder().encode(text), as: UTF8.self)
        _ = try await web.evaluateJavaScript("{ const input=document.querySelector('textarea'); input.value=\(literal); input.dispatchEvent(new Event('input',{bubbles:true})); }")
        #expect(try await draft(in: web) == text)
    }

    private static func capture(_ window: NSWindow, web: WKWebView, name: String) async throws {
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
