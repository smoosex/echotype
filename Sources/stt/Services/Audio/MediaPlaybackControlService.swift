import AppKit
import Foundation
import IOKit.hidsystem

final class MediaPlaybackControlService {
    func pauseActivePlayback() {
        guard let keyDownEvent = mediaKeyEvent(keyDown: true),
              let keyUpEvent = mediaKeyEvent(keyDown: false) else {
            AppLogger.playback.error("Failed to create media pause events")
            return
        }

        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
        AppLogger.playback.info("Dispatched system media play/pause key event")
    }

    private func mediaKeyEvent(keyDown: Bool) -> CGEvent? {
        let keyCode = Int32(NX_KEYTYPE_PLAY)
        let keyState = Int32(keyDown ? 0xA : 0xB)
        let data1 = Int((keyCode << 16) | (keyState << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: data1,
            data2: -1
        )
        return event?.cgEvent
    }
}
