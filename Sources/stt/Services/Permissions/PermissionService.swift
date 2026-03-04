import AVFoundation
import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum PermissionState: String {
    case notDetermined = "not_determined"
    case denied = "denied"
    case restricted = "restricted"
    case authorized = "authorized"
}

@MainActor
final class PermissionService {
    func requestMicrophonePermission() async -> PermissionState {
        let current = microphoneState()
        switch current {
        case .authorized, .denied, .restricted:
            return current
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            return granted ? .authorized : .denied
        }
    }

    func requestAccessibilityPermission() -> PermissionState {
        accessibilityState(prompt: true)
    }

    func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    func accessibilityState(prompt: Bool = false) -> PermissionState {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options)
        return trusted ? .authorized : .denied
    }

    func openMicrophoneSettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
