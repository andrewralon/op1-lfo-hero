import XCTest
@testable import op1_lfo_hero

/// Saved-state migration.
///
/// Before this work, `loadSettings` decoded with `try?` and fell back to defaults, and Swift's
/// synthesized `Decodable` ignores property defaults for missing keys — so adding a single
/// field to the settings struct silently erased every saved LFO chip, track state and BPM.
/// These tests exist to make sure that can never happen again: old blobs must load, and
/// unknown or partial blobs must degrade rather than reset.
@MainActor
final class SettingsMigrationTests: XCTestCase {

    private func decodeSettings(_ json: String) throws -> AppState.Settings {
        try JSONDecoder().decode(AppState.Settings.self, from: Data(json.utf8))
    }

    // MARK: - v0 → v1

    /// A realistic pre-multi-device blob: no version, no deviceId, no perDevice envelope,
    /// clips keyed by `parameter` rather than `paramId`.
    private let v0Blob = """
    {
      "lfoWave": "triangle",
      "lfoParam": "fx 2",
      "lfoRate": 5,
      "lfoDepth": 22.0,
      "lfoCenter": 70.0,
      "trackOn": {"1": 1, "2": 2, "3": 0, "4": 0},
      "masterOn": 1,
      "isClockMaster": false,
      "bpm": 128.0,
      "activeLfos": [
        {"id": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "track": 2, "parameter": "volume",
         "wave": "sine", "rateTicks": 24, "depth": 20.0, "centerValue": 100.0,
         "inverted": false, "loop": true, "isEnabled": true, "originalValue": 115.0},
        {"id": "2B4E28BA-2FA1-11D2-883F-0016D3CCA427", "track": 0, "parameter": "lfo 3",
         "wave": "square", "rateTicks": 96, "depth": 10.0, "centerValue": 64.0,
         "inverted": true, "loop": true, "isEnabled": false, "originalValue": 64.0}
      ]
    }
    """

    func testV0BlobMigratesIntoTheOP1Bucket() throws {
        let s = try decodeSettings(v0Blob)
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.deviceId, "op1")
        let st = try XCTUnwrap(s.perDevice["op1"], "v0 state must land in the op1 bucket")

        XCTAssertEqual(st.lfoWave, .triangle)
        XCTAssertEqual(st.lfoRate, 5)
        XCTAssertEqual(st.lfoDepth, 22.0)
        XCTAssertEqual(st.lfoCenter, 70.0)
        XCTAssertEqual(st.masterOn, 1)
        XCTAssertEqual(st.bpm, 128.0)
        XCTAssertFalse(st.isClockMaster)
        XCTAssertEqual(st.trackOn, [1: 1, 2: 2, 3: 0, 4: 0])
    }

    /// The old `lfoParam` raw value maps straight onto the new id — the OP-1 profile's
    /// parameter ids are deliberately those same strings.
    func testV0EditorParameterSurvives() throws {
        let st = try XCTUnwrap(try decodeSettings(v0Blob).perDevice["op1"])
        XCTAssertEqual(st.lfoParamId, "fx 2")
        XCTAssertNotNil(DeviceProfile.op1Field.param(st.lfoParamId),
                        "migrated parameter id must resolve in the OP-1 profile")
    }

    /// The whole point: chips saved by an older build must still be there afterwards.
    func testV0ClipsSurviveWithAllFields() throws {
        let st = try XCTUnwrap(try decodeSettings(v0Blob).perDevice["op1"])
        XCTAssertEqual(st.activeLfos.count, 2)

        let first = st.activeLfos[0]
        XCTAssertEqual(first.paramId, "volume")
        XCTAssertEqual(first.deviceId, "op1", "clips with no deviceId must default to op1")
        XCTAssertEqual(first.track, 2)
        XCTAssertEqual(first.wave, .sine)
        XCTAssertEqual(first.rateTicks, 24)
        XCTAssertEqual(first.depth, 20.0)
        XCTAssertEqual(first.centerValue, 100.0)
        XCTAssertEqual(first.originalValue, 115.0)
        XCTAssertTrue(first.loop)
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(first.inverted)

        let second = st.activeLfos[1]
        XCTAssertEqual(second.paramId, "lfo 3")
        XCTAssertEqual(second.track, 0, "master clips keep track 0")
        XCTAssertTrue(second.inverted)
        XCTAssertFalse(second.isEnabled, "a paused chip must stay paused")

        for clip in st.activeLfos {
            XCTAssertNotNil(DeviceProfile.op1Field.param(clip.paramId),
                            "migrated clip '\(clip.paramId)' must resolve")
        }
    }

    // MARK: - v1 round trip

    func testV1RoundTripsThroughEncodeAndDecode() throws {
        var st = AppState.DeviceState()
        st.lfoParamId = "env D"
        st.lfoWave = .saw
        st.bpm = 90
        st.trackOn = [1: 0, 2: 1]
        st.volumes = [1: 55, 2: 60]
        st.activeLfos = [LfoClip(deviceId: "op1", track: 3, paramId: "fx 4", wave: .exp,
                                 rateTicks: 48, depth: 12, centerValue: 70,
                                 inverted: true, loop: true, originalValue: 70)]
        var s = AppState.Settings()
        s.deviceId = "op1"
        s.perDevice["op1"] = st

        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppState.Settings.self, from: data)

        XCTAssertEqual(back.version, 1)
        let r = try XCTUnwrap(back.perDevice["op1"])
        XCTAssertEqual(r.lfoParamId, "env D")
        XCTAssertEqual(r.lfoWave, .saw)
        XCTAssertEqual(r.bpm, 90)
        XCTAssertEqual(r.trackOn, [1: 0, 2: 1])
        XCTAssertEqual(r.volumes, [1: 55, 2: 60])
        XCTAssertEqual(r.activeLfos.count, 1)
        XCTAssertEqual(r.activeLfos[0].paramId, "fx 4")
        XCTAssertEqual(r.activeLfos[0].track, 3)
        XCTAssertTrue(r.activeLfos[0].inverted)
    }

    /// Multiple devices coexist; saving one must not disturb another's bucket.
    func testPerDeviceBucketsAreIndependent() throws {
        var s = AppState.Settings()
        var op1 = AppState.DeviceState(); op1.bpm = 100; op1.lfoParamId = "volume"
        var other = AppState.DeviceState(); other.bpm = 140; other.lfoParamId = "tx6.eqHi"
        s.perDevice = ["op1": op1, "tx6": other]

        let back = try JSONDecoder().decode(AppState.Settings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.perDevice["op1"]?.bpm, 100)
        XCTAssertEqual(back.perDevice["tx6"]?.bpm, 140)
        XCTAssertEqual(back.perDevice["tx6"]?.lfoParamId, "tx6.eqHi")
    }

    // MARK: - Degrading instead of resetting

    /// The regression that motivated all of this: a blob missing a field must keep everything
    /// else, not throw and wipe the lot.
    func testMissingFieldsFallBackIndividually() throws {
        let partial = """
        {"version": 1, "deviceId": "op1", "perDevice": {"op1": {"bpm": 111.0}}}
        """
        let st = try XCTUnwrap(try decodeSettings(partial).perDevice["op1"])
        XCTAssertEqual(st.bpm, 111.0, "the field that was present must be read")
        XCTAssertEqual(st.lfoWave, .sine, "missing fields fall back to defaults")
        XCTAssertEqual(st.lfoParamId, "volume")
        XCTAssertEqual(st.lfoRate, 3)
        XCTAssertTrue(st.activeLfos.isEmpty)
    }

    /// A clip missing everything but its id must still decode — one bad clip cannot take the
    /// whole save file down with it.
    func testClipWithMissingFieldsStillDecodes() throws {
        let blob = """
        {"version": 1, "deviceId": "op1", "perDevice": {"op1": {"activeLfos": [
          {"track": 1, "paramId": "pan", "wave": "sine", "rateTicks": 24,
           "depth": 5.0, "centerValue": 64.0, "inverted": false, "loop": true}
        ]}}}
        """
        let st = try XCTUnwrap(try decodeSettings(blob).perDevice["op1"])
        XCTAssertEqual(st.activeLfos.count, 1)
        XCTAssertTrue(st.activeLfos[0].isEnabled, "missing isEnabled defaults to enabled")
        XCTAssertEqual(st.activeLfos[0].originalValue, 64.0,
                       "missing originalValue falls back to the clip's center")
    }

    /// An id from a device the app no longer knows must decode (the load path filters it out
    /// later) rather than throwing during decode.
    func testUnknownParamIdDecodesAndIsDetectable() throws {
        let blob = """
        {"version": 1, "deviceId": "op1", "perDevice": {"op1": {"activeLfos": [
          {"track": 1, "paramId": "nonexistent.param", "wave": "sine", "rateTicks": 24,
           "depth": 5.0, "centerValue": 64.0, "inverted": false, "loop": true,
           "originalValue": 64.0}
        ]}}}
        """
        let st = try XCTUnwrap(try decodeSettings(blob).perDevice["op1"])
        XCTAssertEqual(st.activeLfos.count, 1)
        XCTAssertNil(DeviceProfile.op1Field.param(st.activeLfos[0].paramId),
                     "load must be able to detect and drop this clip")
    }

    func testGarbageBlobYieldsDefaultsWithoutCrashing() {
        for junk in ["", "null", "[]", "{", "\"a string\"", "{\"perDevice\": 17}"] {
            let s = try? decodeSettings(junk)
            // Either it fails to decode (caller falls back to Settings()) or it decodes to
            // something usable — the one unacceptable outcome is a crash.
            if let s { XCTAssertTrue(s.perDevice.isEmpty || s.perDevice["op1"] != nil) }
        }
    }
}

/// Renaming a `ParamSpec.id` orphans anything that saved the old one, so every rename needs a
/// `legacyParamIdMap` entry — and it has to be applied to saved *clips*, not just the selected
/// parameter, or the chips using it are dropped as unresolvable while the picker looks fine.
@MainActor
final class ParamIdRenameTests: XCTestCase {

    /// `tp7.speed` became `tp7.pitchbend` once measurement showed bend is a signed velocity
    /// offset rather than a speed multiplier.
    func testSpeedMigratesToPitchBend() {
        XCTAssertEqual(AppState.migratedParamId("tp7.speed"), "tp7.pitchbend")
    }

    /// Ids with no rename must pass through untouched.
    func testUnrenamedIdsAreUnchanged() {
        for id in ["volume", "pan", "mute", "fx 1", "tx6.vol", "tp7.loop", "nonsense"] {
            XCTAssertEqual(AppState.migratedParamId(id), id)
        }
    }

    /// The point of the map: the migrated id must actually resolve in the profile.
    func testMigratedIdResolvesButTheOldOneIsGone() {
        let p = DeviceProfile.tp7
        XCTAssertNil(p.param("tp7.speed"), "the old id should no longer exist")
        XCTAssertNotNil(p.param(AppState.migratedParamId("tp7.speed")),
                        "and the migrated id must resolve")
    }

    /// Every entry in the map must point at an id that exists in some profile — a typo there
    /// would silently drop clips instead of rescuing them.
    func testEveryMigrationTargetExists() {
        for old in ["tp7.speed"] {
            let new = AppState.migratedParamId(old)
            XCTAssertTrue(DeviceRegistry.all.contains { $0.param(new) != nil },
                          "migration target '\(new)' resolves in no profile")
        }
    }
}
