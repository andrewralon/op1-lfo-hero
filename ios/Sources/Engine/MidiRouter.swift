import Combine
import Foundation

/// Somewhere MIDI can be sent to and received from. Named to match CoreMIDI's own vocabulary,
/// where the endpoint you send to is a "destination".
///
/// `MidiRouter` is the real implementation; tests substitute `RecordingDestination` so the
/// outgoing wire format can be asserted without any hardware or transport.
protocol MidiDestination: AnyObject {
    func send(_ bytes: [UInt8])
    var onClock: (() -> Void)? { get set }
    var onStart: (() -> Void)? { get set }
    var onStop:  (() -> Void)? { get set }
}

/// Routes MIDI to whichever transport is the active connection. Owns both transports and
/// aggregates their incoming callbacks. Both transports keep scanning/detecting in the
/// background at all times, but only the active transport's messages are forwarded and only
/// the active transport is sent to — a newly available transport never silently takes over
/// mid-session. The active transport changes only when the user explicitly picks a different
/// device, or when the active transport itself disconnects.
final class MidiRouter: MidiDestination {
    enum Transport { case usb, ble }

    let ble = BLEMidi()
    let usb = USBMidi()

    /// The transport currently in control of routing. `nil` means neither transport is
    /// connected, in which case either one connecting claims it.
    private(set) var activeTransport: Transport?
    private var cancellables = Set<AnyCancellable>()

    var onClock: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop:  (() -> Void)?
    var onCC:    ((Int, Int, Int) -> Void)?

    init() {
        usb.onClock = { [weak self] in self?.forwardIfActive(.usb) { self?.onClock?() } }
        usb.onStart = { [weak self] in self?.forwardIfActive(.usb) { self?.onStart?() } }
        usb.onStop  = { [weak self] in self?.forwardIfActive(.usb) { self?.onStop?()  } }
        usb.onCC    = { [weak self] ch, cc, v in
            self?.forwardIfActive(.usb) { self?.onCC?(ch, cc, v) }
        }

        ble.onClock = { [weak self] in self?.forwardIfActive(.ble) { self?.onClock?() } }
        ble.onStart = { [weak self] in self?.forwardIfActive(.ble) { self?.onStart?() } }
        ble.onStop  = { [weak self] in self?.forwardIfActive(.ble) { self?.onStop?()  } }
        ble.onCC    = { [weak self] ch, cc, v in
            self?.forwardIfActive(.ble) { self?.onCC?(ch, cc, v) }
        }

        // Release the active claim the moment its own transport drops the connection, so the
        // other transport (or a fresh connect on the same one) can claim it again. This is the
        // only automatic transition allowed — it never hands control to the OTHER transport
        // just because that one happens to be connected.
        usb.$state
            .sink { [weak self] state in
                guard let self, self.activeTransport == .usb, !state.isConnected else { return }
                self.activeTransport = nil
            }
            .store(in: &cancellables)
        ble.$state
            .sink { [weak self] state in
                guard let self, self.activeTransport == .ble, !state.isConnected else { return }
                self.activeTransport = nil
            }
            .store(in: &cancellables)
    }

    /// Claims the active transport for an explicit user pick (device picker connect buttons).
    func setActiveTransport(_ transport: Transport) {
        activeTransport = transport
    }

    private func forwardIfActive(_ transport: Transport, _ body: () -> Void) {
        // Nothing has claimed routing yet — first transport to speak claims it, preserving
        // today's "auto-connect on launch" behavior when nothing is connected.
        if activeTransport == nil { activeTransport = transport }
        guard activeTransport == transport else { return }
        body()
    }

    func send(_ bytes: [UInt8]) {
        switch activeTransport {
        case .usb: usb.send(bytes)
        case .ble: ble.send(bytes)
        case nil:
            // Nothing claimed yet — fall back to whichever is actually connected.
            if usb.state.isConnected { usb.send(bytes) } else { ble.send(bytes) }
        }
    }
}
