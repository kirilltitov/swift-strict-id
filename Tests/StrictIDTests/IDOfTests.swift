import Foundation
import Testing
@testable import StrictID

// Helper types with different prefixes for the tests.

private struct Alpha: IDPrefixable {
    enum Prefix: String { case alpha = "A" }
    static let IDPrefix: Prefix = .alpha
}

private struct Beta: IDPrefixable {
    enum Prefix: String { case beta = "B" }
    static let IDPrefix: Prefix = .beta
}

private struct TwoChar: IDPrefixable {
    enum Prefix: String { case tc = "TC" }
    static let IDPrefix: Prefix = .tc
}

// Stand-ins for "real" entities to exercise the domain scenario.

private struct Organization: IDPrefixable {
    enum Prefix: String { case organization = "O" }
    static let IDPrefix: Prefix = .organization
}

private struct User: IDPrefixable {
    enum Prefix: String { case user = "U" }
    static let IDPrefix: Prefix = .user
}

// MARK: - Helpers

private func makeBaseID(prefix: String, shard: Int64 = 1, identifier: Int64 = 1) throws -> ID {
    try ID(shardNumber: shard, identifier: identifier, entityKind: prefix)
}

@Suite("IDOf")
struct IDOfTests {

    // MARK: - Initialization

    @Test("init(base:) accepts an ID with a matching prefix")
    func initValidPrefix() throws {
        let base = try makeBaseID(prefix: "A")
        let idOf = try IDOf<Alpha>(base: base)
        #expect(idOf.base == base)
    }

    @Test("init(base:) throws WrongIdPrefix on a mismatched prefix")
    func initWrongPrefix() throws {
        let base = try makeBaseID(prefix: "B") // Beta prefix, but Alpha is expected
        #expect {
            try IDOf<Alpha>(base: base)
        } throws: { error in
            guard let e = error as? IDOf<Alpha>.E, case .WrongIdPrefix = e else { return false }
            return true
        }
    }

    @Test("init(base:) works with a two-character prefix")
    func initTwoCharPrefix() throws {
        let base = try makeBaseID(prefix: "TC")
        let idOf = try IDOf<TwoChar>(base: base)
        #expect(idOf.base == base)
    }

    @Test("init(base:) rejects a mismatched two-character prefix")
    func initWrongTwoCharPrefix() throws {
        let base = try makeBaseID(prefix: "A") // single-character instead of two-character
        #expect {
            try IDOf<TwoChar>(base: base)
        } throws: { error in
            guard let e = error as? IDOf<TwoChar>.E, case .WrongIdPrefix = e else { return false }
            return true
        }
    }

    // MARK: - ID.of(_:) extension

    @Test("ID.of(_:) — a convenience method for creating IDOf")
    func idOfExtension() throws {
        let base = try makeBaseID(prefix: "A", shard: 1337, identifier: 42)
        let idOf = try base.of(Alpha.self)
        #expect(idOf.base == base)
        #expect(idOf.stringValue == base.stringValue)
    }

    @Test("ID.of(_:) throws on a mismatched type")
    func idOfExtensionWrongType() throws {
        let base = try makeBaseID(prefix: "B")
        #expect {
            try base.of(Alpha.self)
        } throws: { error in
            guard let e = error as? IDOf<Alpha>.E, case .WrongIdPrefix = e else { return false }
            return true
        }
    }

    // MARK: - parse

    @Test("parse: ParseError on an invalid sqids fragment")
    func parseErrorInvalidInput() {
        #expect {
            try IDOf<Alpha>.parse(input: "A__!!!")
        } throws: { error in
            guard let e = error as? IDOf<Alpha>.E, case .ParseError = e else { return false }
            return true
        }
    }

    // MARK: - stringValue

    @Test("stringValue matches base.stringValue")
    func stringValue() throws {
        let base = try makeBaseID(prefix: "A", shard: 99, identifier: 777)
        let idOf = try IDOf<Alpha>(base: base)
        #expect(idOf.stringValue == base.stringValue)
    }

    // MARK: - Equatable

    @Test("Two IDOf with the same values are equal")
    func equal() throws {
        let base1 = try makeBaseID(prefix: "A", shard: 1, identifier: 2)
        let base2 = try makeBaseID(prefix: "A", shard: 1, identifier: 2)
        let id1 = try IDOf<Alpha>(base: base1)
        let id2 = try IDOf<Alpha>(base: base2)
        #expect(id1 == id2)
    }

    @Test("IDOf with different identifiers are not equal")
    func notEqual() throws {
        let id1 = try IDOf<Alpha>(base: makeBaseID(prefix: "A", identifier: 1))
        let id2 = try IDOf<Alpha>(base: makeBaseID(prefix: "A", identifier: 2))
        #expect(id1 != id2)
    }

    // MARK: - Hashable

    @Test("Identical IDOf produce the same hash")
    func hashConsistency() throws {
        let id1 = try IDOf<Alpha>(base: makeBaseID(prefix: "A", shard: 5, identifier: 10))
        let id2 = try IDOf<Alpha>(base: makeBaseID(prefix: "A", shard: 5, identifier: 10))
        #expect(id1.hashValue == id2.hashValue)
    }

    @Test("IDOf can be used as a dictionary key")
    func hashableInDictionary() throws {
        let id = try IDOf<Alpha>(base: makeBaseID(prefix: "A", identifier: 42))
        var dict: [IDOf<Alpha>: String] = [:]
        dict[id] = "value"
        #expect(dict[id] == "value")
    }

    // MARK: - CustomStringConvertible

    @Test("description matches base.description")
    func description() throws {
        let base = try makeBaseID(prefix: "A", shard: 1337, identifier: 99)
        let idOf = try IDOf<Alpha>(base: base)
        #expect(idOf.description == base.description)
    }

    // MARK: - LosslessStringConvertible

    @Test("init?(_:) accepts a string with the correct prefix")
    func losslessValidPrefix() throws {
        let base = try makeBaseID(prefix: "A", shard: 1337, identifier: 55)
        let stringValue = base.stringValue
        let idOf = IDOf<Alpha>(stringValue)
        #expect(idOf != nil)
        #expect(idOf?.stringValue == stringValue)
    }

    @Test("init?(_:) returns nil for an unparseable string")
    func losslessInvalidString() {
        let idOf = IDOf<Alpha>("!!!")
        #expect(idOf == nil)
    }

    @Test("init?(_:) returns nil for a string with the wrong prefix")
    func losslessWrongPrefix() throws {
        // A valid ID string, but with the Beta prefix instead of Alpha.
        let base = try makeBaseID(prefix: "B", shard: 0, identifier: 1)
        let idOf = IDOf<Alpha>(base.stringValue)
        #expect(idOf == nil)
    }

    // MARK: - Codable

    @Test("Codable: round-trip through JSON")
    func codableRoundTrip() throws {
        let base = try makeBaseID(prefix: "A", shard: 42, identifier: 1000)
        let original = try IDOf<Alpha>(base: base)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IDOf<Alpha>.self, from: data)
        #expect(original == decoded)
    }

    @Test("Codable: encodes as a string (delegates to base)")
    func codableEncodesAsString() throws {
        let base = try makeBaseID(prefix: "A", shard: 0, identifier: 1)
        let idOf = try IDOf<Alpha>(base: base)
        let idData = try JSONEncoder().encode(idOf)
        let baseData = try JSONEncoder().encode(base)
        // IDOf encodes identically to base.
        #expect(idData == baseData)
    }

    @Test("Codable: decoding throws on a mismatched prefix in JSON")
    func codableDecodingWrongPrefix() throws {
        // Build JSON with a Beta-prefixed string, decode it into IDOf<Alpha>.
        let wrongBase = try makeBaseID(prefix: "B", identifier: 1)
        let data = try JSONEncoder().encode(wrongBase)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(IDOf<Alpha>.self, from: data)
        }
    }

    // MARK: - Domain scenario (Organization, User)

    @Test("IDOf<Organization> accepts an ID with prefix 'O'")
    func organizationIDValid() throws {
        let base = try makeBaseID(prefix: "O", shard: 1337, identifier: 100)
        let organizationID = try IDOf<Organization>(base: base)
        #expect(organizationID.stringValue == base.stringValue)
    }

    @Test("IDOf<Organization> rejects an ID with prefix 'U'")
    func organizationIDWrongPrefix() throws {
        let base = try makeBaseID(prefix: "U", identifier: 1)
        #expect {
            try IDOf<Organization>(base: base)
        } throws: { error in
            guard let e = error as? IDOf<Organization>.E, case .WrongIdPrefix = e else { return false }
            return true
        }
    }

    @Test("IDOf<User> accepts an ID with prefix 'U'")
    func userIDValid() throws {
        let base = try makeBaseID(prefix: "U", shard: 0, identifier: 5)
        let userID = try IDOf<User>(base: base)
        #expect(userID.stringValue == base.stringValue)
    }

    @Test("IDOf<Organization> and IDOf<User> from the same shard/identifier are different strings (different prefixes)")
    func differentTypeSameValuesDiffer() throws {
        let organizationBase = try makeBaseID(prefix: "O", shard: 1, identifier: 1)
        let userBase = try makeBaseID(prefix: "U", shard: 1, identifier: 1)
        let organizationID = try IDOf<Organization>(base: organizationBase)
        let userID = try IDOf<User>(base: userBase)
        // The strings must differ (different entityKind → different bytesSum → different sqids).
        #expect(organizationID.stringValue != userID.stringValue)
    }

    // MARK: - CustomReflectable

    @Test("customMirror delegates to base.customMirror")
    func customMirror() throws {
        let base = try makeBaseID(prefix: "A", identifier: 1)
        let idOf = try IDOf<Alpha>(base: base)
        let mirror = Mirror(reflecting: idOf)
        #expect(mirror.displayStyle == .struct)
        #expect(mirror.children.isEmpty)
    }
}
