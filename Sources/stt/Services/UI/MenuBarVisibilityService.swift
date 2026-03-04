import AppKit
import Foundation

@MainActor
final class MenuBarVisibilityService {
    private var originalMenuBarVisible: Bool?
    private var originalActivationPolicy: NSApplication.ActivationPolicy?
    private var pinRequestCount = 0
    private var restoreWorkItem: DispatchWorkItem?
    private var keepVisibleTimer: Timer?

    func panelDidOpen() {
        pinRequestCount += 1
        restoreWorkItem?.cancel()
        restoreWorkItem = nil

        if pinRequestCount == 1 {
            if originalMenuBarVisible == nil {
                originalMenuBarVisible = NSMenu.menuBarVisible()
            }
            if originalActivationPolicy == nil {
                originalActivationPolicy = NSApp.activationPolicy()
            }
        }

        applyPinnedState()
        startKeepVisibleTimerIfNeeded()
    }

    func panelDidClose() {
        pinRequestCount = max(0, pinRequestCount - 1)
        guard pinRequestCount == 0 else { return }
        scheduleRestore()
    }

    private func applyPinnedState() {
        NSMenu.setMenuBarVisible(true)
        _ = NSApp.setActivationPolicy(.regular)
    }

    private func startKeepVisibleTimerIfNeeded() {
        guard keepVisibleTimer == nil else { return }

        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.pinRequestCount > 0 else { return }
                self.applyPinnedState()
            }
        }
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        keepVisibleTimer = timer
    }

    private func stopKeepVisibleTimer() {
        keepVisibleTimer?.invalidate()
        keepVisibleTimer = nil
    }

    private func scheduleRestore() {
        restoreWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pinRequestCount == 0 else { return }
            self.restoreOriginalState()
        }

        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func restoreOriginalState() {
        stopKeepVisibleTimer()

        if let originalMenuBarVisible {
            NSMenu.setMenuBarVisible(originalMenuBarVisible)
            self.originalMenuBarVisible = nil
        }

        if let originalActivationPolicy {
            _ = NSApp.setActivationPolicy(originalActivationPolicy)
            self.originalActivationPolicy = nil
        }

        restoreWorkItem = nil
    }
}
