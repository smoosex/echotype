import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowService {
    private let windowContentWidth: CGFloat = 620
    private let fallbackContentHeight: CGFloat = 560
    private weak var window: NSWindow?

    func present<Content: View>(title: String, content: Content) {
        let window = ensureWindow(title: title, content: AnyView(content))
        resizeWindowToFitContent(window)
        activateAndShow(window: window)
    }

    func update<Content: View>(title: String? = nil, content: Content) {
        guard let window else { return }
        if let title {
            window.title = title
        }
        guard let hostingController = window.contentViewController as? NSHostingController<AnyView> else {
            return
        }

        hostingController.rootView = AnyView(content)
        resizeWindowToFitContent(window)
    }

    func close() {
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        self.window = nil
    }

    private func ensureWindow(title: String, content: AnyView) -> NSWindow {
        if let window {
            window.title = title
            if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = content
            } else {
                window.contentViewController = NSHostingController(rootView: content)
            }
            return window
        }

        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: windowContentWidth, height: fallbackContentHeight))
        window.center()
        self.window = window
        return window
    }

    private func resizeWindowToFitContent(_ window: NSWindow) {
        guard let hostingController = window.contentViewController as? NSHostingController<AnyView> else {
            window.setContentSize(NSSize(width: windowContentWidth, height: fallbackContentHeight))
            return
        }

        let fitting = hostingController.sizeThatFits(in: NSSize(
            width: windowContentWidth,
            height: .greatestFiniteMagnitude
        ))
        let measuredHeight = fitting.height
        let targetHeight = measuredHeight.isFinite && measuredHeight > 0
            ? ceil(measuredHeight)
            : fallbackContentHeight
        let targetContentRect = NSRect(
            origin: .zero,
            size: NSSize(width: windowContentWidth, height: targetHeight)
        )
        let currentFrame = window.frame
        let targetFrame = window.frameRect(forContentRect: targetContentRect)
        let anchoredOrigin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.maxY - targetFrame.height
        )
        window.setFrame(NSRect(origin: anchoredOrigin, size: targetFrame.size), display: true)
    }

    private func activateAndShow(window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
