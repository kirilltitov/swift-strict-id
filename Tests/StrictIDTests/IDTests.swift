import Foundation
import Testing
@testable import StrictID

@Suite("ID")
struct IDTests {

    // MARK: - Properties and initialization

    @Test("shardNumber and identifier match the passed values")
    func properties() throws {
        let id = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        #expect(id.shardNumber == 1337)
        #expect(id.identifier == 42)
        #expect(id.entityKind == "P")
    }

    @Test("Single-character entityKind")
    func singleCharEntityKind() throws {
        let id = try ID(shardNumber: 0, identifier: 1, entityKind: "P")
        #expect(id.entityKind == "P")
    }

    @Test("Two-character entityKind")
    func twoCharEntityKind() throws {
        let id = try ID(shardNumber: 0, identifier: 1, entityKind: "PL")
        #expect(id.entityKind == "PL")
    }

    // MARK: - String format

    @Test("Single-character entityKind yields a double underscore")
    func stringFormatSingleChar() throws {
        let id = try ID(shardNumber: 0, identifier: 1, entityKind: "P")
        #expect(id.stringValue.hasPrefix("P__"))
    }

    @Test("Two-character entityKind yields a single underscore")
    func stringFormatTwoChars() throws {
        let id = try ID(shardNumber: 0, identifier: 1, entityKind: "PL")
        #expect(id.stringValue.hasPrefix("PL_"))
    }

    @Test("String length is at least 6 characters")
    func minStringLength() throws {
        let id = try ID(shardNumber: 0, identifier: 0, entityKind: "T")
        #expect(id.stringValue.count >= ID.minLength)
    }

    @Test("The string only contains characters from fullAlphabet")
    func validAlphabetCharacters() throws {
        let id = try ID(shardNumber: 1337, identifier: 99999, entityKind: "H")
        let validChars = Set(ID.fullAlphabet)
        for char in id.stringValue {
            #expect(validChars.contains(char), "Unexpected character: \(char)")
        }
    }

    // MARK: - Round-trip through parse

    @Test("Round-trip: single-character entityKind")
    func roundTripSingleChar() throws {
        let original = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
        #expect(original.entityKind == restored.entityKind)
        #expect(original.shardNumber == restored.shardNumber)
        #expect(original.identifier == restored.identifier)
    }

    @Test("Round-trip: two-character entityKind")
    func roundTripTwoChars() throws {
        let original = try ID(shardNumber: 999, identifier: 12345, entityKind: "PL")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
        #expect(original.entityKind == restored.entityKind)
        #expect(original.shardNumber == restored.shardNumber)
        #expect(original.identifier == restored.identifier)
    }

    @Test("Round-trip: minimal identifier (0)")
    func roundTripMinIdentifier() throws {
        let original = try ID(shardNumber: 0, identifier: 0, entityKind: "T")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
    }

    @Test("Round-trip: maximum identifier")
    func roundTripMaxIdentifier() throws {
        let original = try ID(shardNumber: 0, identifier: ID.maxIdentifier, entityKind: "T")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
    }

    @Test("Round-trip: random values", arguments: 0..<20)
    func roundTripRandom(_: Int) throws {
        let shard = Int64.random(in: 0...9_999)
        let identifier = Int64.random(in: 0...ID.maxIdentifier)
        let entityKind = Bool.random() ? "X" : "XY"

        let original = try ID(shardNumber: shard, identifier: identifier, entityKind: entityKind)
        let restored = try ID.parse(input: original.stringValue)

        #expect(original == restored)
        #expect(original.shardNumber == restored.shardNumber)
        #expect(original.identifier == restored.identifier)
        #expect(original.entityKind == restored.entityKind)
    }

    // MARK: - LosslessStringConvertible

    @Test("LosslessStringConvertible: valid string")
    func losslessStringConvertible() throws {
        let original = try ID(shardNumber: 1337, identifier: 777, entityKind: "U")
        let restored = ID(original.description)
        #expect(restored != nil)
        #expect(restored == original)
    }

    @Test("LosslessStringConvertible: an invalid string returns nil")
    func losslessStringConvertibleInvalid() {
        let result = ID("!!!")
        #expect(result == nil)
    }

    // MARK: - Codable

    @Test("Codable: round-trip through JSON")
    func codableRoundTrip() throws {
        let original = try ID(shardNumber: 42, identifier: 1000, entityKind: "H")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ID.self, from: data)
        #expect(original == decoded)
    }

    @Test("Codable: encodes as a string")
    func codableEncodesAsString() throws {
        let id = try ID(shardNumber: 0, identifier: 1, entityKind: "P")
        let data = try JSONEncoder().encode(id)
        let json = try JSONDecoder().decode(String.self, from: data)
        #expect(json == id.stringValue)
    }

    // MARK: - Equatable / Hashable

    @Test("Two IDs with the same values are equal")
    func equalIDs() throws {
        let id1 = try ID(shardNumber: 1, identifier: 2, entityKind: "P")
        let id2 = try ID(shardNumber: 1, identifier: 2, entityKind: "P")
        #expect(id1 == id2)
    }

    @Test("IDs with different identifiers are not equal")
    func differentIdentifiers() throws {
        let id1 = try ID(shardNumber: 1, identifier: 1, entityKind: "P")
        let id2 = try ID(shardNumber: 1, identifier: 2, entityKind: "P")
        #expect(id1 != id2)
    }

    @Test("IDs with different entityKind are not equal")
    func differentEntityKinds() throws {
        let id1 = try ID(shardNumber: 1, identifier: 1, entityKind: "P")
        let id2 = try ID(shardNumber: 1, identifier: 1, entityKind: "T")
        #expect(id1 != id2)
    }

    @Test("Hashable: identical IDs produce the same hash")
    func hashableConsistency() throws {
        let id1 = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        let id2 = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        #expect(id1.hashValue == id2.hashValue)
    }

    @Test("Hashable: can be used as a dictionary key")
    func hashableInDictionary() throws {
        let id = try ID(shardNumber: 0, identifier: 1, entityKind: "P")
        var dict: [ID: String] = [:]
        dict[id] = "value"
        #expect(dict[id] == "value")
    }

    // MARK: - Edge cases and errors

    @Test("Error: rawValues with a count != 3")
    func invalidRawValuesSizeTooFew() {
        #expect {
            try ID(rawValues: [1, 2], entityKind: "P")
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidInputRawValuesSize = e else { return false }
            return true
        }
    }

    @Test("Error: rawValues with four elements")
    func invalidRawValuesSizeTooMany() {
        #expect {
            try ID(rawValues: [1, 2, 3, 4], entityKind: "P")
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidInputRawValuesSize = e else { return false }
            return true
        }
    }

    @Test("Error: empty entityKind")
    func emptyEntityKind() {
        #expect {
            try ID(shardNumber: 0, identifier: 1, entityKind: "")
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidEntityPrefixLength = e else { return false }
            return true
        }
    }

    @Test("Error: entityKind longer than two characters")
    func tooLongEntityKind() {
        #expect {
            try ID(shardNumber: 0, identifier: 1, entityKind: "ABC")
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidEntityPrefixLength = e else { return false }
            return true
        }
    }

    @Test("Error: identifier exceeds maxIdentifier")
    func tooBigIdentifier() {
        #expect {
            try ID(rawValues: [0, 0, ID.maxIdentifier + 1], entityKind: "P")
        } throws: { error in
            guard let e = error as? ID.E, case .TooBigIdentifier = e else { return false }
            return true
        }
    }

    @Test("parse: ParseError on sqids overflow (a too-long body)")
    func parseErrorSqidsOverflow() {
        // sqids throws an overflow error when decoding a string that overflows Int64.
        // A 20-character string of 'Z' reliably triggers it.
        let overflowInput = "P__" + String(repeating: "Z", count: 20)
        #expect {
            try ID.parse(input: overflowInput)
        } throws: { error in
            guard let e = error as? ID.E, case .ParseError = e else { return false }
            return true
        }
    }

    @Test("parse: InvalidInputRawValuesSize when sqids decodes a count != 3")
    func parseErrorWrongRawValuesCount() {
        // Encode 2 values instead of 3 and substitute them as the ID body.
        let twoValueEncoded = try! ID.sqids.encode([1337, 42])
        let fakeInput = "X__" + twoValueEncoded
        #expect {
            try ID.parse(input: fakeInput)
        } throws: { error in
            guard let e = error as? ID.E, case .InvalidInputRawValuesSize = e else { return false }
            return true
        }
    }

    @Test("Codable: decoding fails on an invalid string in JSON")
    func codableDecodingInvalidString() throws {
        let data = try JSONEncoder().encode("P__!!!")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ID.self, from: data)
        }
    }

    // MARK: - Large values

    @Test(
        "Round-trip: values on the order of a million",
        arguments: [
            (shard: Int64(1_000_000), identifier: Int64(999_999)),
            (shard: Int64(999_999), identifier: Int64(1_000_000)),
            (shard: Int64(1_234_567), identifier: Int64(7_654_321)),
        ])
    func largeMillion(pair: (shard: Int64, identifier: Int64)) throws {
        let original = try ID(shardNumber: pair.shard, identifier: pair.identifier, entityKind: "P")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
        #expect(original.shardNumber == restored.shardNumber)
        #expect(original.identifier == restored.identifier)
    }

    @Test(
        "Round-trip: values on the order of a billion",
        arguments: [
            (shard: Int64(1_000_000_000), identifier: Int64(999_999_999)),
            (shard: Int64(999_999_999), identifier: Int64(1_000_000_000)),
            (shard: Int64(1_234_567_890), identifier: Int64(9_876_543_210)),
        ])
    func largeBillion(pair: (shard: Int64, identifier: Int64)) throws {
        let original = try ID(shardNumber: pair.shard, identifier: pair.identifier, entityKind: "PL")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
        #expect(original.shardNumber == restored.shardNumber)
        #expect(original.identifier == restored.identifier)
    }

    @Test(
        "Round-trip: values on the order of a trillion",
        arguments: [
            (shard: Int64(1_000_000_000_000), identifier: Int64(999_999_999_999)),
            (shard: Int64(999_999_999_999), identifier: Int64(1_000_000_000_000)),
            (shard: Int64(1_234_567_890_123), identifier: Int64(9_007_199_254_000_000)),
        ])
    func largeTrillion(pair: (shard: Int64, identifier: Int64)) throws {
        let original = try ID(shardNumber: pair.shard, identifier: pair.identifier, entityKind: "T")
        let restored = try ID.parse(input: original.stringValue)
        #expect(original == restored)
        #expect(original.shardNumber == restored.shardNumber)
        #expect(original.identifier == restored.identifier)
    }

    // MARK: - Uncovered branches

    @Test("Initializer with a RawRepresentable enum entityKind")
    func enumEntityKindInit() throws {
        enum Prefix: String { case page = "P"; case link = "PL" }
        let id1 = try ID(shardNumber: 1337, identifier: 42, entityKind: Prefix.page)
        let id2 = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        #expect(id1 == id2)

        let id3 = try ID(shardNumber: 0, identifier: 1, entityKind: Prefix.link)
        let id4 = try ID(shardNumber: 0, identifier: 1, entityKind: "PL")
        #expect(id3 == id4)
    }

    @Test("customMirror returns a Mirror with struct display style")
    func customMirror() throws {
        let id = try ID(shardNumber: 1, identifier: 1, entityKind: "P")
        let mirror = Mirror(reflecting: id)
        #expect(mirror.displayStyle == .struct)
        #expect(mirror.children.isEmpty)
    }
}
