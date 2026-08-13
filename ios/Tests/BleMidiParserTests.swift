import XCTest
@testable import op1_lfo_hero

/// The BLE-MIDI packet parser.
///
/// Packet layout is a header byte, then for each message a timestamp byte followed by the MIDI
/// bytes. Timestamp and status bytes both have the high bit set and can only be told apart by
/// position, which is what an earlier version got wrong.
final class BleMidiParserTests: XCTestCase {

    private var clocks = 0
    private var starts = 0
    private var stops = 0
    private var ccs: [(ch: Int, cc: Int, val: Int)] = []

    private func parse(_ bytes: [UInt8]) {
        clocks = 0; starts = 0; stops = 0; ccs = []
        BleMidiPacket.parse(Data(bytes),
                            onClock: { self.clocks += 1 },
                            onStart: { self.starts += 1 },
                            onStop:  { self.stops += 1 },
                            onCC:    { self.ccs.append(($0, $1, $2)) })
    }

    // MARK: - The regression

    /// Timestamps span 0x80-0xFF, which includes the real-time status values. A CC whose
    /// timestamp byte happens to be 0xF8 must not be read as a clock tick.
    ///
    /// This is what produced a reading of 640000 BPM from a TX-6 sending nothing but knob
    /// movements: phantom ticks, all inside one packet, so the app measured microsecond
    /// intervals between them.
    func testTimestampBytesAreNotMistakenForRealTime() {
        parse([0x80, 0xF8, 0xB0, 7, 100])          // header, timestamp 0xF8, CC
        XCTAssertEqual(clocks, 0, "0xF8 in the timestamp slot is a timestamp, not a clock tick")
        XCTAssertEqual(ccs.count, 1)
        XCTAssertEqual(ccs.first.map { [$0.ch, $0.cc, $0.val] }, [0, 7, 100])
    }

    /// The same aliasing for start and stop, which is worse than a wrong tempo — phantom
    /// transport would start and stop the user's tape.
    func testTimestampBytesAreNotMistakenForStartOrStop() {
        parse([0x80, 0xFA, 0xB1, 10, 64])
        XCTAssertEqual(starts, 0, "0xFA in the timestamp slot must not start the transport")
        XCTAssertEqual(ccs.count, 1)

        parse([0x80, 0xFC, 0xB2, 11, 20])
        XCTAssertEqual(stops, 0, "0xFC in the timestamp slot must not stop the transport")
        XCTAssertEqual(ccs.count, 1)
    }

    /// A burst of CC — the TX-6 case that triggered the bug. Every message carries its own
    /// timestamp, and several of those land on real-time values.
    func testCCBurstProducesNoPhantomTransport() {
        parse([0x80,
               0xF8, 0xB0, 1, 10,
               0xFA, 0xB0, 2, 20,
               0xFC, 0xB0, 3, 30,
               0xFB, 0xB0, 4, 40])
        XCTAssertEqual(clocks, 0)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertEqual(ccs.count, 4, "all four CCs must survive")
        XCTAssertEqual(ccs.map(\.cc), [1, 2, 3, 4])
        XCTAssertEqual(ccs.map(\.val), [10, 20, 30, 40])
    }

    // MARK: - Real-time still works

    /// Genuine real-time messages sit *after* a timestamp byte, and must still be delivered —
    /// the fix must not simply stop reporting clock.
    func testGenuineRealTimeIsStillDelivered() {
        parse([0x80, 0x81, 0xF8, 0x82, 0xF8, 0x83, 0xF8])
        XCTAssertEqual(clocks, 3)

        parse([0x80, 0x81, 0xFA])
        XCTAssertEqual(starts, 1)

        parse([0x80, 0x81, 0xFC])
        XCTAssertEqual(stops, 1)
    }

    /// Real-time may be interleaved between other messages without disturbing them.
    func testRealTimeInterleavedWithCC() {
        parse([0x80, 0x81, 0xB0, 7, 64, 0x82, 0xF8, 0x83, 0xB0, 8, 32])
        XCTAssertEqual(clocks, 1)
        XCTAssertEqual(ccs.count, 2)
        XCTAssertEqual(ccs.map(\.cc), [7, 8])
    }

    // MARK: - Structure

    /// Running status: a message may omit the status byte, but still carries a timestamp.
    func testRunningStatusIsCarriedBetweenMessages() {
        parse([0x80, 0x81, 0xB0, 7, 64, 0x82, 8, 32])
        XCTAssertEqual(ccs.count, 2)
        XCTAssertEqual(ccs.map { [$0.ch, $0.cc, $0.val] }, [[0, 7, 64], [0, 8, 32]])
    }

    func testChannelIsDecodedFromTheStatusByte() {
        parse([0x80, 0x81, 0xB5, 74, 99])
        XCTAssertEqual(ccs.first?.ch, 5)
    }

    /// Truncated and undersized packets must not read past the end or emit garbage.
    func testTruncatedPacketsAreSafe() {
        for bytes: [UInt8] in [[], [0x80], [0x80, 0x81], [0x80, 0x81, 0xB0], [0x80, 0x81, 0xB0, 7]] {
            parse(bytes)
            XCTAssertEqual(ccs.count, 0, "truncated packet \(bytes) must emit nothing")
            XCTAssertEqual(clocks + starts + stops, 0)
        }
    }
}
