import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class RecordingOverlayWindowService {
    private let showDuration: Duration = .milliseconds(220)
    private let hideDuration: Duration = .milliseconds(160)
    private let levelStore = RecordingOverlayLevelStore()

    private weak var panel: RecordingOverlayPanel?
    private var screenParametersObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?
    private var phaseTask: Task<Void, Never>?

    func show() {
        hideTask?.cancel()
        hideTask = nil
        phaseTask?.cancel()
        phaseTask = nil
        let showDuration = self.showDuration

        let panel = ensurePanel()
        reposition(panel)
        registerObserversIfNeeded()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        levelStore.presentationPhase = .appearing

        withAnimation(.easeOut(duration: 0.22)) {
            levelStore.presentationProgress = 1
        }

        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: showDuration)
            guard let self, !Task.isCancelled else { return }
            self.levelStore.presentationPhase = .visible
        }
    }

    func hide() {
        updateLevel(0)
        phaseTask?.cancel()
        phaseTask = nil
        hideTask?.cancel()
        let hideDuration = self.hideDuration

        guard panel != nil else {
            levelStore.presentationPhase = .hidden
            levelStore.presentationProgress = 0
            return
        }

        levelStore.presentationPhase = .disappearing
        withAnimation(.easeIn(duration: 0.16)) {
            levelStore.presentationProgress = 0
        }

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: hideDuration)
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.unregisterObservers()
            self.levelStore.presentationPhase = .hidden
            self.levelStore.presentationProgress = 0
            self.hideTask = nil
        }
    }

    func updateLevel(_ level: Double) {
        levelStore.level = min(max(level, 0), 1)
    }

    private func ensurePanel() -> RecordingOverlayPanel {
        if let panel {
            return panel
        }

        let hostingController = NSHostingController(rootView: RecordingOverlayView(levelStore: levelStore))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        let panel = RecordingOverlayPanel(contentViewController: hostingController)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.alphaValue = 1
        panel.setFrame(
            NSRect(origin: .zero, size: fallbackPanelSize),
            display: false
        )
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        self.panel = panel
        return panel
    }

    private func reposition(_ panel: NSPanel) {
        guard let screen = mainDisplayScreen() else {
            AppLogger.app.error("Recording overlay could not resolve a target screen")
            panel.orderOut(nil)
            return
        }

        let metrics = overlayMetrics(for: screen)
        levelStore.notchWidth = metrics.notchWidth
        levelStore.notchHeight = metrics.notchHeight
        let frame = panelFrame(for: screen, panelSize: metrics.panelSize)
        panel.setFrame(frame, display: true)
    }

    private func registerObserversIfNeeded() {
        guard screenParametersObserver == nil, activeSpaceObserver == nil else {
            return
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionIfVisible()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionIfVisible()
            }
        }
    }

    private func unregisterObservers() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }

        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
    }

    private func repositionIfVisible() {
        guard let panel, panel.isVisible else { return }
        reposition(panel)
    }

    private var fallbackPanelSize: NSSize {
        NSSize(
            width: ceil(
                RecordingOverlayMetrics.finalWidth(
                    notchWidth: RecordingOverlayMetrics.fallbackNotchWidth
                )
            ),
            height: ceil(
                RecordingOverlayMetrics.finalHeight(
                    notchHeight: RecordingOverlayMetrics.fallbackNotchHeight
                )
            )
        )
    }

    private func overlayMetrics(for screen: NSScreen) -> (notchWidth: CGFloat, notchHeight: CGFloat, panelSize: NSSize) {
        let notchWidth: CGFloat
        if let leftInset = screen.auxiliaryTopLeftArea?.width,
           let rightInset = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - leftInset - rightInset + 4
        } else {
            notchWidth = RecordingOverlayMetrics.fallbackNotchWidth
        }

        let measuredHeight = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : screen.frame.maxY - screen.visibleFrame.maxY
        let notchHeight = measuredHeight > 0
            ? measuredHeight
            : RecordingOverlayMetrics.fallbackNotchHeight

        let panelSize = NSSize(
            width: ceil(RecordingOverlayMetrics.finalWidth(notchWidth: notchWidth)),
            height: ceil(RecordingOverlayMetrics.finalHeight(notchHeight: notchHeight))
        )

        return (notchWidth, notchHeight, panelSize)
    }

    private func panelFrame(for screen: NSScreen, panelSize: NSSize) -> NSRect {
        let x = screen.frame.midX - panelSize.width / 2
        let topEdgeOverlap = 1 / max(screen.backingScaleFactor, 1)
        let y = screen.frame.maxY - panelSize.height + topEdgeOverlap

        return NSRect(
            x: x.rounded(),
            y: y,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func mainDisplayScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            screen.displayID == mainDisplayID
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        guard let displayID = screen.displayID else {
            return false
        }
        return CGDisplayIsBuiltin(displayID) != 0
    }
}

private final class RecordingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
