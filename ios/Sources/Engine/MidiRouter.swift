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
    var onContinue: (() -> Void)? { get set }
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
    private(set) var activeTransport: Transport? {
        didSet {
            // Claims happen on MIDI threads and change what the app shows (the status text and
            // the device layout), so tell subscribers, serialised on the main thread.
            let t = activeTransport
            DispatchQueue.main.async { [weak self] in self?.activeTransportChanged.send(t) }
        }
    }
    /// Emits whenever `activeTransport` changes, so the UI can follow a claim as well as a connect.
    let activeTransportChanged = CurrentValueSubject<Transport?, Never>(nil)
    private var cancellables = Set<AnyCancellable>()

    var onClock: (() -> Void)?
    var onStart: (() -> Void)?
    var onContinue: (() -> Void)?
    var onStop:  (() -> Void)?
    var onCC:    ((Int, Int, Int) -> Void)?

    init() {
        ble.shouldAutoConnect = { [weak self] in self?.mayAutoConnect ?? true }
        usb.onClock = { [weak self] in self?.forwardIfActive(.usb) { self?.onClock?() } }
        usb.onStart = { [weak self] in self?.forwardIfActive(.usb) { self?.onStart?() } }
        usb.onContinue = { [weak self] in self?.forwardIfActive(.usb) { self?.onContinue?() } }
        usb.onStop  = { [weak self] in self?.forwardIfActive(.usb) { self?.onStop?()  } }
        usb.onCC    = { [weak self] ch, cc, v in
            self?.forwardIfActive(.usb) { self?.onCC?(ch, cc, v) }
        }

        ble.onClock = { [weak self] in self?.forwardIfActive(.ble) { self?.onClock?() } }
        ble.onStart = { [weak self] in self?.forwardIfActive(.ble) { self?.onStart?() } }
        ble.onContinue = { [weak self] in self?.forwardIfActive(.ble) { self?.onContinue?() } }
        ble.onStop  = { [weak self] in self?.forwardIfActive(.ble) { self?.onStop?()  } }
        ble.onCC    = { [weak self] ch, cc, v in
            self?.forwardIfActive(.ble) { self?.onCC?(ch, cc, v) }
        }

        // The first transport to connect owns the routing, and keeps it: a device that connects later
        // never takes over an active connection. When the owner disconnects, the other transport
        // takes over if it is connected (a device being unplugged or going away is the one time
        // the app moves on by itself); with neither connected the claim is released, so the next
        // one to connect claims it. Claiming at connect time, not at the first message, matters:
        // an OP-1 in midi sync sends nothing, and a claim that waits for a message lets a later
        // connection win.
        usb.$state
            .sink { [weak self] state in
                guard let self else { return }
                self.activeTransport = Self.transportAfterChange(
                    current: self.activeTransport,
                    usbConnected: state.isConnected, bleConnected: self.ble.state.isConnected,
                    bleConnecting: self.ble.state.isConnecting)
            }
            .store(in: &cancellables)
        ble.$state
            .sink { [weak self] state in
                guard let self else { return }
                self.activeTransport = Self.transportAfterChange(
                    current: self.activeTransport,
                    usbConnected: self.usb.state.isConnected, bleConnected: state.isConnected,
                    bleConnecting: state.isConnecting)
            }
            .store(in: &cancellables)
    }

    /// Who owns the routing after a connection change. A claim is kept while its transport is
    /// connected **or still connecting**: tapping a Bluetooth device in the picker claims the
    /// routing at once, and the state passes through "connecting" before "connected", so judging the
    /// claim on "connected" alone lost an explicit choice within a fraction of a second. A
    /// connection that fails stops connecting, and the claim then falls back to a working device.
    /// Otherwise (no claim yet, or the owner dropped) the first *connected* transport takes it, USB
    /// first only as a tie-break; with nothing connected there is no claim.
    static func transportAfterChange(current: Transport?, usbConnected: Bool, bleConnected: Bool,
                                     bleConnecting: Bool = false) -> Transport? {
        if let current, current == .usb ? usbConnected : (bleConnected || bleConnecting) { return current }
        if usbConnected { return .usb }
        if bleConnected { return .ble }
        return nil
    }

    /// Whether a transport may connect to a device on its own (an auto-connect on discovery): only
    /// when nothing is connected or claimed. A device found while another is active is listed in the
    /// device picker, and a tap there connects it as an explicit choice.
    var mayAutoConnect: Bool { activeTransport == nil && !usb.state.isConnected && !ble.state.isConnected }

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

    /// The transport MIDI actually travels over right now. Auto-connect never claims the router,
    /// and a device that sends nothing (an OP-1 in midi sync) never makes the router claim it
    /// either, so `activeTransport` can stay unset while a device is connected and working. In
    /// that case this resolves it the same way `send` does: USB if connected, else Bluetooth.
    static func effectiveTransport(active: Transport?, usbConnected: Bool, bleConnected: Bool) -> Transport? {
        if let active { return active }
        if usbConnected { return .usb }
        if bleConnected { return .ble }
        return nil
    }

    var effectiveTransport: Transport? {
        Self.effectiveTransport(active: activeTransport,
                                usbConnected: usb.state.isConnected,
                                bleConnected: ble.state.isConnected)
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
