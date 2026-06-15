import Foundation

/// Routes MIDI to USB when the OP-1 is connected via USB-C, BLE otherwise.
/// Owns both transports and aggregates their incoming callbacks.
/// BLE callbacks are silenced while USB is active to prevent double clock ticks.
final class MidiRouter {
    let ble = BLEMidi()
    let usb = USBMidi()

    var onClock: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop:  (() -> Void)?
    var onCC:    ((Int, Int, Int) -> Void)?

    init() {
        // USB always forwards — it is the authoritative source when connected
        usb.onClock = { [weak self] in self?.onClock?() }
        usb.onStart = { [weak self] in self?.onStart?() }
        usb.onStop  = { [weak self] in self?.onStop?()  }
        usb.onCC    = { [weak self] ch, cc, v in self?.onCC?(ch, cc, v) }

        // BLE forwards only when USB is not connected (avoids double clock ticks)
        ble.onClock = { [weak self] in
            guard let self, !self.usb.state.isConnected else { return }
            self.onClock?()
        }
        ble.onStart = { [weak self] in
            guard let self, !self.usb.state.isConnected else { return }
            self.onStart?()
        }
        ble.onStop = { [weak self] in
            guard let self, !self.usb.state.isConnected else { return }
            self.onStop?()
        }
        ble.onCC = { [weak self] ch, cc, v in
            guard let self, !self.usb.state.isConnected else { return }
            self.onCC?(ch, cc, v)
        }
    }

    func send(_ bytes: [UInt8]) {
        if usb.state.isConnected {
            usb.send(bytes)
        } else {
            ble.send(bytes)
        }
    }
}
