import Foundation
import Testing

@testable import StrictID

// The separator between the prefix and the body: one underscore in the modern format, padding up to
// `ID.prefixSize` in the legacy one. Fixed strings below come from the golden vectors —
// `P__zuYa75Z5` / `P_zuYa75Z5` is (shard 1337, identifier 42, kind "P") and `PL_0mqtJaT7NR` is
// (shard 999, identifier 12345, kind "PL").
//
// Everything here passes `mode:` explicitly. `ID.separatorMode` is process-wide state and tests run
// in parallel, so no test mutates it — its default value is asserted instead, and the tests that
// omit `mode:` exercise it in passing.

private let legacySingle = "P__zuYa75Z5"
private let modernSingle = "P_zuYa75Z5"
private let twoChar = "PL_0mqtJaT7NR"

private struct Alpha: IDPrefixable {
    enum Prefix: String { case alpha = "A" }
    static let IDPrefix: Prefix = .alpha
}

@Suite("SeparatorMode")
struct SeparatorModeTests {

    private func expectInvalidSeparator(_ input: String, mode: ID.SeparatorMode) {
        #expect {
            try ID.parse(input: input, mode: mode)
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidPrefixSeparator = e else { return false }
            return true
        }
    }

    // MARK: - Defaults

    @Test("The default mode renders one underscore and still reads legacy strings")
    func defaultMode() throws {
        #expect(ID.separatorMode == .modern)

        let id = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        #expect(id.stringValue == modernSingle)

        // No `mode:` anywhere below — everything funnels through `ID.separatorMode`.
        let parsed = try ID.parse(input: legacySingle)
        #expect(parsed == id)
        #expect(parsed.stringValue == legacySingle)
        #expect(ID(legacySingle) == id)

        // Codable rides on the same default: legacy JSON decodes, and keeps its spelling on the
        // way back out, so a document round-trip doesn't silently rewrite stored identifiers.
        let decoded = try JSONDecoder().decode(ID.self, from: try JSONEncoder().encode(legacySingle))
        #expect(decoded == id)
        #expect(decoded.stringValue == legacySingle)
        #expect(try JSONEncoder().encode(decoded) == (try JSONEncoder().encode(legacySingle)))
    }

    @Test("Mode flags")
    func modeFlags() {
        #expect(ID.SeparatorMode.allCases == [.strictModern, .modern, .legacy, .strictLegacy])

        #expect(ID.SeparatorMode.strictModern.rendersLegacyPadding == false)
        #expect(ID.SeparatorMode.modern.rendersLegacyPadding == false)
        #expect(ID.SeparatorMode.legacy.rendersLegacyPadding == true)
        #expect(ID.SeparatorMode.strictLegacy.rendersLegacyPadding == true)

        #expect(ID.SeparatorMode.strictModern.acceptsLegacy == false)
        #expect(ID.SeparatorMode.modern.acceptsLegacy == true)
        #expect(ID.SeparatorMode.legacy.acceptsLegacy == true)
        #expect(ID.SeparatorMode.strictLegacy.acceptsLegacy == true)

        #expect(ID.SeparatorMode.strictModern.acceptsModern == true)
        #expect(ID.SeparatorMode.modern.acceptsModern == true)
        #expect(ID.SeparatorMode.legacy.acceptsModern == true)
        #expect(ID.SeparatorMode.strictLegacy.acceptsModern == false)
    }

    // MARK: - Rendering

    @Test("Each mode renders the separator it promises", arguments: ID.SeparatorMode.allCases)
    func rendering(mode: ID.SeparatorMode) throws {
        let single = try ID(shardNumber: 1337, identifier: 42, entityKind: "P", mode: mode)
        #expect(single.stringValue == (mode.rendersLegacyPadding ? legacySingle : modernSingle))

        // A two-character prefix fills the legacy prefix zone by itself — same string either way.
        let double = try ID(shardNumber: 999, identifier: 12345, entityKind: "PL", mode: mode)
        #expect(double.stringValue == twoChar)

        // Whatever a mode renders, that same mode reads back.
        #expect(try ID.parse(input: single.stringValue, mode: mode) == single)
        #expect(try ID.parse(input: double.stringValue, mode: mode) == double)
    }

    @Test("Every initializer honours the mode", arguments: ID.SeparatorMode.allCases)
    func allInitializersHonourMode(mode: ID.SeparatorMode) throws {
        enum Prefix: String { case page = "P" }
        let expected = mode.rendersLegacyPadding ? legacySingle : modernSingle

        #expect(try ID(shardNumber: 1337, identifier: 42, entityKind: "P", mode: mode).stringValue == expected)
        #expect(try ID(shardNumber: 1337, identifier: 42, entityKind: Prefix.page, mode: mode).stringValue == expected)
        #expect(try ID(rawValues: [1337, 80, 42], entityKind: "P", mode: mode).stringValue == expected)
        #expect(
            try ID(firstValue: 1337, secondValue: 80, thirdValue: 42, entityKind: "P", mode: mode).stringValue
                == expected
        )
    }

    // MARK: - Parse acceptance matrix

    @Test(
        "Legacy input: accepted everywhere except .strictModern",
        arguments: [
            (mode: ID.SeparatorMode.strictLegacy, accepted: true),
            (mode: ID.SeparatorMode.legacy, accepted: true),
            (mode: ID.SeparatorMode.modern, accepted: true),
            (mode: ID.SeparatorMode.strictModern, accepted: false),
        ])
    func legacyInputAcceptance(c: (mode: ID.SeparatorMode, accepted: Bool)) throws {
        guard c.accepted else {
            return self.expectInvalidSeparator(legacySingle, mode: c.mode)
        }

        let id = try ID.parse(input: legacySingle, mode: c.mode)
        #expect(id.entityKind == "P")
        #expect(id.shardNumber == 1337)
        #expect(id.identifier == 42)
        #expect(id.stringValue == legacySingle, "parse hands the string back exactly as given")
    }

    @Test(
        "Modern input: accepted everywhere except .strictLegacy",
        arguments: [
            (mode: ID.SeparatorMode.strictModern, accepted: true),
            (mode: ID.SeparatorMode.modern, accepted: true),
            (mode: ID.SeparatorMode.legacy, accepted: true),
            (mode: ID.SeparatorMode.strictLegacy, accepted: false),
        ])
    func modernInputAcceptance(c: (mode: ID.SeparatorMode, accepted: Bool)) throws {
        guard c.accepted else {
            return self.expectInvalidSeparator(modernSingle, mode: c.mode)
        }

        let id = try ID.parse(input: modernSingle, mode: c.mode)
        #expect(id.entityKind == "P")
        #expect(id.shardNumber == 1337)
        #expect(id.identifier == 42)
        #expect(id.stringValue == modernSingle)
    }

    @Test("A two-character prefix parses in every mode — one format, not two", arguments: ID.SeparatorMode.allCases)
    func twoCharPrefixIsModeAgnostic(mode: ID.SeparatorMode) throws {
        let id = try ID.parse(input: twoChar, mode: mode)
        #expect(id.entityKind == "PL")
        #expect(id.shardNumber == 999)
        #expect(id.identifier == 12345)
        #expect(id.stringValue == twoChar)
    }

    @Test("A separator that belongs to neither format is always rejected", arguments: ID.SeparatorMode.allCases)
    func overlongSeparatorRejected(mode: ID.SeparatorMode) {
        self.expectInvalidSeparator("P___zuYa75Z5", mode: mode)  // three underscores
        self.expectInvalidSeparator("PL__0mqtJaT7NR", mode: mode)  // two after a two-char prefix
    }

    // MARK: - One identifier, two spellings

    @Test("Both spellings are the same identifier: equality, hashing, collections")
    func crossFormatIdentity() throws {
        let legacy = try ID.parse(input: legacySingle, mode: .legacy)
        let modern = try ID.parse(input: modernSingle, mode: .modern)

        #expect(legacy.stringValue != modern.stringValue)
        #expect(legacy == modern)
        #expect(legacy.hashValue == modern.hashValue)
        #expect(legacy.rawValues == modern.rawValues)
        #expect(legacy.entityKind == modern.entityKind)

        // The point of value-based equality: mixed-format data doesn't produce phantom duplicates.
        #expect(Set([legacy, modern]).count == 1)

        var dict: [ID: Int] = [:]
        dict[legacy] = 1
        dict[modern] = 2
        #expect(dict.count == 1)
        #expect(dict[legacy] == 2)
    }

    @Test("Re-rendering a parsed legacy identifier in the modern format")
    func normalization() throws {
        let legacy = try ID.parse(input: legacySingle, mode: .legacy)
        let normalized = try ID(rawValues: legacy.rawValues, entityKind: legacy.entityKind, mode: .modern)

        #expect(normalized.stringValue == modernSingle)
        #expect(normalized == legacy)
        #expect(try ID.parse(input: normalized.stringValue, mode: .strictModern) == legacy)
    }

    // MARK: - IDOf

    @Test("IDOf.parse passes the mode through to ID.parse")
    func idOfHonoursMode() throws {
        let legacy = try ID(shardNumber: 1, identifier: 1, entityKind: "A", mode: .legacy).stringValue
        let modern = try ID(shardNumber: 1, identifier: 1, entityKind: "A", mode: .modern).stringValue
        #expect(legacy != modern)

        let fromLegacy = try IDOf<Alpha>.parse(input: legacy, mode: .modern)
        let fromModern = try IDOf<Alpha>.parse(input: modern, mode: .modern)
        #expect(fromLegacy.stringValue == legacy)
        #expect(fromModern.stringValue == modern)
        #expect(fromLegacy == fromModern)

        #expect {
            try IDOf<Alpha>.parse(input: legacy, mode: .strictModern)
        } throws: { error in
            guard let e = error as? IDOf<Alpha>.E, case .ParseError(let underlying) = e,
                case .InvalidPrefixSeparator = underlying
            else { return false }
            return true
        }
    }

    // MARK: - Round-trips

    @Test("Cross-mode acceptance holds for random identifiers", arguments: 0..<20)
    func crossModeAcceptance(_: Int) throws {
        let shard = Int64.random(in: 0...9_999_999)
        let identifier = Int64.random(in: 0...ID.maxIdentifier)

        for kind in ["X", "XY"] {
            for writer in ID.SeparatorMode.allCases {
                let id = try ID(shardNumber: shard, identifier: identifier, entityKind: kind, mode: writer)

                for reader in ID.SeparatorMode.allCases {
                    // A two-character prefix has a single spelling, so every reader takes it; for a
                    // one-character one it comes down to what the writer rendered.
                    let accepted =
                        kind.count == 2
                        ? true
                        : (writer.rendersLegacyPadding ? reader.acceptsLegacy : reader.acceptsModern)

                    let parsed = try? ID.parse(input: id.stringValue, mode: reader)
                    #expect((parsed != nil) == accepted, "writer \(writer) → reader \(reader), kind \(kind)")

                    if let parsed {
                        #expect(parsed == id)
                        #expect(parsed.stringValue == id.stringValue)
                        #expect(parsed.shardNumber == shard)
                        #expect(parsed.identifier == identifier)
                        #expect(parsed.entityKind == kind)
                    }
                }
            }
        }
    }

    @Test("Malformed input is rejected in every mode, never crashes", arguments: ID.SeparatorMode.allCases)
    func malformedInput(mode: ID.SeparatorMode) {
        let inputs = [
            "", "_", "__", "___", "P", "PL", "P_", "P__", "P___", "_P", "__P",
            "P_x", "P__x", "P___x", "PL_x", "PL__x", "ABC_xyz", "ABCD__xyz", "!!!", "P__!!!",
            "_U", "_U_", "_UU_x", "P" + String(repeating: "_", count: 40) + "zuYa75Z5",
        ]
        for input in inputs {
            #expect(throws: (any Error).self, "parse(\(input.debugDescription), mode: \(mode))") {
                try ID.parse(input: input, mode: mode)
            }
        }
    }

    @Test("Round-trip through a string in every mode", arguments: ID.SeparatorMode.allCases)
    func roundTripInEveryMode(mode: ID.SeparatorMode) throws {
        for kind in ["X", "XY", "_U"] {
            for identifier in [Int64(0), 1, 999_999, ID.maxIdentifier] {
                let original =
                    kind == "_U"
                    ? try ID(externalUUID: UUID(), entityKind: kind)
                    : try ID(shardNumber: 7, identifier: identifier, entityKind: kind, mode: mode)
                let restored = try ID.parse(input: original.stringValue, mode: mode)

                #expect(restored == original)
                #expect(restored.stringValue == original.stringValue)
                #expect(restored.entityKind == original.entityKind)
                #expect(restored.rawValues == original.rawValues)
            }
        }
    }
}
