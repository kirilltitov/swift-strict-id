import Foundation
import Testing
@testable import StrictID

@Suite("External UUID")
struct ExternalUUIDTests {

    // MARK: - Helpers

    /// Full e2e round-trip: UUID → ID → string → parse → UUID, plus a version-preservation check.
    private func assertRoundTrip(_ uuidString: String, expectedVersion: Int) throws {
        let uuid = try #require(UUID(uuidString: uuidString), "invalid UUID string in test")

        // UUID → ID
        let id = try ID(externalUUID: uuid)
        #expect(id.entityKind.first == "_", "external ID must have the underscore marker")
        #expect(id.externalUUID == uuid)

        // ID → string → parse → ID (via the standard string interface)
        let restored = try ID.parse(input: id.stringValue)
        #expect(restored == id)
        #expect(restored.externalUUID == uuid, "round-trip through a string must be lossless")

        // version (high nibble of byte 6) survived packing
        let restoredUUID = try #require(restored.externalUUID)
        let version = Int(restoredUUID.uuid.6 >> 4)
        #expect(version == expectedVersion)
    }

    // MARK: - e2e across versions 1..8 (separate tests, fixed UUIDs)

    @Test("e2e: UUID v1")
    func v1() throws { try assertRoundTrip("f47ac10b-58cc-1372-8567-0e02b2c3d479", expectedVersion: 1) }

    @Test("e2e: UUID v2")
    func v2() throws { try assertRoundTrip("f47ac10b-58cc-2372-9567-0e02b2c3d479", expectedVersion: 2) }

    @Test("e2e: UUID v3")
    func v3() throws { try assertRoundTrip("f47ac10b-58cc-3372-a567-0e02b2c3d479", expectedVersion: 3) }

    @Test("e2e: UUID v4")
    func v4() throws { try assertRoundTrip("f47ac10b-58cc-4372-b567-0e02b2c3d479", expectedVersion: 4) }

    @Test("e2e: UUID v5")
    func v5() throws { try assertRoundTrip("f47ac10b-58cc-5372-8567-0e02b2c3d479", expectedVersion: 5) }

    @Test("e2e: UUID v6")
    func v6() throws { try assertRoundTrip("1ec9414c-232a-6b00-9c8a-9e6bdeced846", expectedVersion: 6) }

    @Test("e2e: UUID v7")
    func v7() throws { try assertRoundTrip("017f22e2-79b0-7cc3-a8c4-dc0c0c07398f", expectedVersion: 7) }

    @Test("e2e: UUID v8")
    func v8() throws { try assertRoundTrip("f47ac10b-58cc-8372-b567-0e02b2c3d479", expectedVersion: 8) }

    // MARK: - Fuzzing: 1000 random UUIDs on the fly

    @Test("e2e: 1000 random UUIDs round-trip through a string")
    func randomRoundTrip() throws {
        for _ in 0..<1000 {
            let uuid = UUID()
            let id = try ID(externalUUID: uuid)
            #expect(id.externalUUID == uuid)

            let restored = try ID.parse(input: id.stringValue)
            #expect(restored == id)
            #expect(restored.externalUUID == uuid)
        }
    }

    @Test("pack/unpack is a bijection for 1000 random UUIDs")
    func packUnpackBijection() {
        for _ in 0..<1000 {
            let uuid = UUID()
            let tuple = ID.pack(uuid)
            #expect(tuple.count == 3)
            #expect(tuple[2] <= ID.maxIdentifier)  // identifier slot within bounds
            #expect(tuple.allSatisfy { $0 >= 0 })  // sqids requires non-negative values
            #expect(ID.unpack(tuple) == uuid)
        }
    }

    // MARK: - Boundary UUIDs

    @Test("nil UUID (all zeros) round-trip")
    func nilUUID() throws {
        let uuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let id = try ID(externalUUID: uuid)
        #expect(id.externalUUID == uuid)
        #expect(try ID.parse(input: id.stringValue).externalUUID == uuid)
    }

    @Test("max UUID (all 0xFF) round-trip — boundaries of the 53/53/22 packing fields")
    func maxUUID() throws {
        let f: UInt8 = 0xFF
        let uuid = UUID(uuid: (f, f, f, f, f, f, f, f, f, f, f, f, f, f, f, f))
        let id = try ID(externalUUID: uuid)
        #expect(id.externalUUID == uuid)
        #expect(try ID.parse(input: id.stringValue).externalUUID == uuid)
    }

    // MARK: - Custom marker character

    @Test("Custom external prefix character (`_X`)")
    func customExternalKind() throws {
        let uuid = UUID()
        let id = try ID(externalUUID: uuid, entityKind: "_X")
        #expect(id.entityKind == "_X")
        #expect(id.externalUUID == uuid)
        #expect(try ID.parse(input: id.stringValue).externalUUID == uuid)
    }

    @Test("Invalid external prefix (no marker) is rejected")
    func invalidExternalKindNoMarker() {
        #expect {
            try ID(externalUUID: UUID(), entityKind: "PL")
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidExternalEntityKind = e else { return false }
            return true
        }
    }

    @Test("Invalid external prefix (marker only) is rejected")
    func invalidExternalKindMarkerOnly() {
        #expect {
            try ID(externalUUID: UUID(), entityKind: "_")
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidExternalEntityKind = e else { return false }
            return true
        }
    }

    // MARK: - Additivity: internal IDs are unaffected

    @Test("An internal ID is not considered external: externalUUID == nil")
    func internalIDNotExternal() throws {
        let id = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        #expect(id.externalUUID == nil)
    }

    @Test("An internal ID parses as before (parse isn't broken)")
    func internalParseUnaffected() throws {
        let id = try ID(shardNumber: 1337, identifier: 42, entityKind: "PL")
        let restored = try ID.parse(input: id.stringValue)
        #expect(restored == id)
        #expect(restored.entityKind == "PL")
        #expect(restored.externalUUID == nil)
    }

    // MARK: - Codable for an external ID

    @Test("Codable: external ID round-trip through JSON")
    func externalCodable() throws {
        let uuid = UUID()
        let id = try ID(externalUUID: uuid)
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ID.self, from: data)
        #expect(decoded == id)
        #expect(decoded.externalUUID == uuid)
    }
}
