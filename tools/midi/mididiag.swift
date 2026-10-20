import CoreMIDI
import Foundation

// What is that TP-7 endpoint actually attached to?
//
// A USB device appears as device -> entity -> endpoints. A network or bridged session appears as
// endpoints with no backing device, or with a driver owner like the network session. Sends can
// still land while receives never arrive, which is the state being diagnosed.

func s(_ e: MIDIObjectRef, _ p: CFString) -> String {
    var v: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(e, p, &v) == noErr, let x = v else { return "" }
    return x.takeRetainedValue() as String
}
func i(_ e: MIDIObjectRef, _ p: CFString) -> Int32? {
    var v: Int32 = 0
    guard MIDIObjectGetIntegerProperty(e, p, &v) == noErr else { return nil }
    return v
}
func describe(_ e: MIDIEndpointRef, _ label: String) {
    var entity = MIDIEntityRef()
    let hasEntity = MIDIEndpointGetEntity(e, &entity) == noErr && entity != 0
    var device = MIDIDeviceRef()
    let hasDevice = hasEntity && MIDIEntityGetDevice(entity, &device) == noErr && device != 0
    print("  \(label): '\(s(e, kMIDIPropertyDisplayName))'")
    print("      driver   : '\(s(e, kMIDIPropertyDriverOwner))'")
    print("      offline  : \(i(e, kMIDIPropertyOffline).map(String.init) ?? "?")")
    print("      uniqueID : \(i(e, kMIDIPropertyUniqueID).map(String.init) ?? "?")")
    if hasDevice {
        print("      device   : '\(s(device, kMIDIPropertyName))'  (entity '\(s(entity, kMIDIPropertyName))')")
    } else {
        print("      device   : NONE — virtual or bridged endpoint, not a directly attached device")
    }
}

print("=== SOURCES (\(MIDIGetNumberOfSources())) ===")
for n in 0..<MIDIGetNumberOfSources() { describe(MIDIGetSource(n), "src[\(n)]") }
print("=== DESTINATIONS (\(MIDIGetNumberOfDestinations())) ===")
for n in 0..<MIDIGetNumberOfDestinations() { describe(MIDIGetDestination(n), "dst[\(n)]") }
print("=== DEVICES (\(MIDIGetNumberOfDevices())) ===")
for n in 0..<MIDIGetNumberOfDevices() {
    let d = MIDIGetDevice(n)
    print("  '\(s(d, kMIDIPropertyName))'  offline=\(i(d, kMIDIPropertyOffline).map(String.init) ?? "?")  entities=\(MIDIDeviceGetNumberOfEntities(d))")
}
