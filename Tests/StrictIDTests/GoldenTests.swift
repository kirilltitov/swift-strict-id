import Foundation
import Testing

@testable import StrictID

// Golden vectors pinning down the canonical encoding (alphabet, minimum length, sqids algorithm)
// and both separator formats, so neither can drift unnoticed.
//
// The `.legacy` vectors are the ones shared with the Go strictid library's golden_test.go — that
// library still renders the padded prefix zone, so it stays byte-compatible with this one as long
// as `SeparatorMode.legacy` is in play. The `.modern` vectors are the same `rawValues` rendered
// with a single separator underscore: the body is identical, only the prefix zone shrinks for
// one-character prefixes.

@Suite("Golden")
struct GoldenTests {

    private struct Vec {
        let shard: Int64
        let id: Int64
        let kind: String
        let str: String
        let raw: [Int64]
    }

    /// Legacy format: the prefix zone is padded to `ID.prefixSize` characters.
    private static let legacyVecs: [Vec] = [
        Vec(shard: 0, id: 0, kind: "T", str: "T__wsVco91", raw: [0, 84, 0]),
        Vec(shard: 0, id: 1, kind: "P", str: "P__mfWECMA", raw: [0, 80, 1]),
        Vec(shard: 0, id: 9007199254740991, kind: "T", str: "T__3TE4dHokVx6vKvb", raw: [0, 84, 9007199254740991]),
        Vec(shard: 1000000, id: 999999, kind: "P", str: "P__CfTFObGXeZxrN", raw: [1000000, 80, 999999]),
        Vec(
            shard: 1234567890123, id: 9007199254000000, kind: "T", str: "T__M2p1Twud4ecYeDQ45tsLf",
            raw: [1234567890123, 84, 9007199254000000]),
        Vec(
            shard: 1234567890, id: 9876543210, kind: "PL", str: "PL_lDm0uwOeWd1aU9uIj",
            raw: [1234567890, 156, 9876543210]),
        Vec(shard: 1337, id: 42, kind: "P", str: "P__zuYa75Z5", raw: [1337, 80, 42]),
        Vec(shard: 1337, id: 99999, kind: "H", str: "H__rTBmQRi9v2", raw: [1337, 72, 99999]),
        Vec(shard: 42, id: 1000, kind: "H", str: "H__kCzaLTO5", raw: [42, 72, 1000]),
        Vec(shard: 999, id: 12345, kind: "PL", str: "PL_0mqtJaT7NR", raw: [999, 156, 12345]),
    ]

    /// Modern format: exactly one underscore between the prefix and the body. Same order and same
    /// `rawValues` as `legacyVecs`, so the two lists line up index by index.
    private static let modernVecs: [Vec] = [
        Vec(shard: 0, id: 0, kind: "T", str: "T_wsVco91", raw: [0, 84, 0]),
        Vec(shard: 0, id: 1, kind: "P", str: "P_mfWECMA", raw: [0, 80, 1]),
        Vec(shard: 0, id: 9007199254740991, kind: "T", str: "T_3TE4dHokVx6vKvb", raw: [0, 84, 9007199254740991]),
        Vec(shard: 1000000, id: 999999, kind: "P", str: "P_CfTFObGXeZxrN", raw: [1000000, 80, 999999]),
        Vec(
            shard: 1234567890123, id: 9007199254000000, kind: "T", str: "T_M2p1Twud4ecYeDQ45tsLf",
            raw: [1234567890123, 84, 9007199254000000]),
        Vec(
            shard: 1234567890, id: 9876543210, kind: "PL", str: "PL_lDm0uwOeWd1aU9uIj",
            raw: [1234567890, 156, 9876543210]),
        Vec(shard: 1337, id: 42, kind: "P", str: "P_zuYa75Z5", raw: [1337, 80, 42]),
        Vec(shard: 1337, id: 99999, kind: "H", str: "H_rTBmQRi9v2", raw: [1337, 72, 99999]),
        Vec(shard: 42, id: 1000, kind: "H", str: "H_kCzaLTO5", raw: [42, 72, 1000]),
        Vec(shard: 999, id: 12345, kind: "PL", str: "PL_0mqtJaT7NR", raw: [999, 156, 12345]),
    ]

    /// Renders every vector in `mode` and parses it back with every mode that accepts that format.
    private func assertVectors(_ vecs: [Vec], mode: ID.SeparatorMode, acceptedBy readers: [ID.SeparatorMode]) throws {
        for v in vecs {
            let got = try ID(shardNumber: v.shard, identifier: v.id, entityKind: v.kind, mode: mode)
            #expect(got.stringValue == v.str, "ID(\(v.shard),\(v.id),\(v.kind), mode: \(mode)).stringValue")
            #expect(got.rawValues == v.raw, "ID(\(v.shard),\(v.id),\(v.kind), mode: \(mode)).rawValues")

            for reader in readers {
                let parsed = try ID.parse(input: v.str, mode: reader)
                #expect(parsed == got, "parse(\(v.str), mode: \(reader))")
                #expect(parsed.rawValues == v.raw)
                #expect(parsed.entityKind == v.kind)
                // parse hands the string back exactly as it got it, whatever the reader's mode.
                #expect(parsed.stringValue == v.str)
            }
        }
    }

    @Test("Legacy string values match the golden vectors from the Go strictid library")
    func goldenLegacyIDsMatchGo() throws {
        try self.assertVectors(Self.legacyVecs, mode: .legacy, acceptedBy: [.strictLegacy, .legacy, .modern])
    }

    @Test("Modern string values match the single-underscore golden vectors")
    func goldenModernIDs() throws {
        try self.assertVectors(Self.modernVecs, mode: .modern, acceptedBy: [.strictModern, .modern, .legacy])
    }

    @Test("The two golden lists are the same identifiers in two spellings")
    func goldenListsAgree() throws {
        #expect(Self.legacyVecs.count == Self.modernVecs.count)

        for (legacy, modern) in zip(Self.legacyVecs, Self.modernVecs) {
            #expect(legacy.raw == modern.raw)
            #expect(legacy.kind == modern.kind)

            // The sqids body is untouched — the separator is the only difference, and only for
            // one-character prefixes (two-character ones are byte-identical in both formats).
            let legacyBody = legacy.str.dropFirst(legacy.kind.count + (ID.prefixSize - legacy.kind.count))
            let modernBody = modern.str.dropFirst(modern.kind.count + 1)
            #expect(legacyBody == modernBody)
            #expect(legacy.str.hasPrefix(legacy.kind + ID.underscores[ID.prefixSize - legacy.kind.count]))
            #expect(modern.str.hasPrefix(modern.kind + "_"))

            if legacy.kind.count == 1 {
                #expect(legacy.str != modern.str)
            } else {
                #expect(legacy.str == modern.str)
            }

            // Both spellings parse to the same identifier, even though the strings differ.
            let fromLegacy = try ID.parse(input: legacy.str, mode: .legacy)
            let fromModern = try ID.parse(input: modern.str, mode: .modern)
            #expect(fromLegacy == fromModern)
            #expect(fromLegacy.hashValue == fromModern.hashValue)
            #expect(fromLegacy.stringValue == legacy.str)
            #expect(fromModern.stringValue == modern.str)
        }
    }

    @Test("External UUIDs match the golden vectors from the Go strictid library", arguments: ID.SeparatorMode.allCases)
    func goldenExternalUUIDMatchesGo(mode: ID.SeparatorMode) throws {
        struct Vec {
            let uuidStr: String
            let str: String
            let raw: [Int64]
        }
        // An external prefix is two characters long, so its separator is a single underscore in
        // both formats — these vectors hold for every mode, which is what `arguments:` checks.
        let vecs: [Vec] = [
            Vec(uuidStr: "00000000-0000-0000-0000-000000000000", str: "_U_brd1jN", raw: [0, 0, 0]),
            Vec(
                uuidStr: "017f22e2-79b0-7cc3-a8c4-dc0c0c07398f", str: "_U_yE7ZdlvmErxz0ODyLoChboOa",
                raw: [6495697866464582, 24520, 1367844206360975]),
            Vec(
                uuidStr: "f47ac10b-58cc-4372-b567-0e02b2c3d479", str: "_U_fa33IoDBnFpwLjvPyqgSHXkrU",
                raw: [2351607909684651, 4005552, 1985729588876409]),
            Vec(
                uuidStr: "ffffffff-ffff-ffff-ffff-ffffffffffff", str: "_U_p1p4dV0i05G18w7WxpsHE3G3w",
                raw: [9007199254740991, 4194303, 9007199254740991]),
        ]

        for v in vecs {
            let uuid = UUID(uuidString: v.uuidStr)!
            let packed = ID.pack(uuid)
            #expect(packed == v.raw, "pack(\(v.uuidStr))")

            let id = try ID(externalUUID: uuid)
            #expect(id.stringValue == v.str, "NewExternalUUID(\(v.uuidStr)).stringValue")

            let back = id.externalUUID
            #expect(back == uuid)

            let parsed = try ID.parse(input: v.str, mode: mode)
            #expect(parsed == id)
            #expect(parsed.externalUUID == uuid)
        }
    }
}
