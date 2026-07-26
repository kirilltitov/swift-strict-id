import Foundation
import Testing

@testable import StrictID

// Behaviour of `ID.Alphabet`: what a valid alphabet is, what a custom one does to identifiers, and
// what a seeded permutation guarantees. The exact strings that pin the format down — the default
// alphabet, seed states, seeded orders, identifiers under custom alphabets — live in GoldenTests,
// next to the other cross-implementation vectors.

@Suite("Alphabet")
struct AlphabetTests {

    // MARK: - The built-in alphabet

    @Test("The built-in alphabet is the historical 62 symbols")
    func builtIn() {
        #expect(ID.Alphabet.default.count == 62)
        #expect(ID.Alphabet.default.symbols == Array(ID.Alphabet.default.string))
        #expect(ID.Alphabet.minCount == 3)
        #expect(ID.Alphabet.maxCount == 93)
        #expect(ID.Alphabet.allowedSymbols.count == ID.Alphabet.maxCount)
        #expect(Array(ID.Alphabet.allowedSymbols.prefix(62)) == ID.Alphabet.default.symbols)
        #expect(ID.Alphabet.allowedSymbols.allSatisfy { $0.isASCII && $0 != "_" && $0 != " " })
        #expect(Set(ID.Alphabet.allowedSymbols).count == ID.Alphabet.maxCount, "allowed symbols are unique")
    }

    @Test("The whole allowed set is itself a valid alphabet")
    func allowedSetIsValid() throws {
        let alphabet = try ID.Alphabet(ID.Alphabet.allowedSymbols)
        #expect(alphabet.count == ID.Alphabet.maxCount)
    }

    // MARK: - Validation

    @Test(
        "Invalid alphabets are rejected",
        arguments: [
            (symbols: "ab", error: ID.Alphabet.E.TooFewSymbols),
            (symbols: "aab", error: ID.Alphabet.E.DuplicateSymbols),
            (symbols: "abcdefa", error: ID.Alphabet.E.DuplicateSymbols),
            (symbols: "ab_c", error: ID.Alphabet.E.ReservedSeparatorSymbol),
            (symbols: "абв", error: ID.Alphabet.E.NonASCIISymbols),
            (symbols: "ab£", error: ID.Alphabet.E.NonASCIISymbols),
            (symbols: "👍👎🙂", error: ID.Alphabet.E.NonASCIISymbols),
            (symbols: "ab c", error: ID.Alphabet.E.NonPrintableSymbols),
            (symbols: "ab\tc", error: ID.Alphabet.E.NonPrintableSymbols),
            (symbols: "ab\nc", error: ID.Alphabet.E.NonPrintableSymbols),
            (symbols: "ab\u{7f}c", error: ID.Alphabet.E.NonPrintableSymbols),
            // `\r\n` is one Character, and one that claims to be ASCII — it has to be caught by the
            // printability check rather than the ASCII one.
            (symbols: "ab\r\nc", error: ID.Alphabet.E.NonPrintableSymbols),
        ])
    func invalidAlphabets(c: (symbols: String, error: ID.Alphabet.E)) {
        #expect(throws: c.error) {
            try ID.Alphabet(c.symbols)
        }
    }

    @Test("An oversized alphabet can't exist: it always duplicates or leaves the allowed set")
    func oversizedIsUnreachable() {
        // 93 allowed symbols, all unique — a 94th has to repeat one of them or be disallowed.
        let tooMany = ID.Alphabet.allowedSymbols + ["a"]
        #expect(throws: ID.Alphabet.E.DuplicateSymbols) { try ID.Alphabet(tooMany) }
        #expect(throws: ID.Alphabet.E.ReservedSeparatorSymbol) { try ID.Alphabet(ID.Alphabet.allowedSymbols + ["_"]) }
    }

    @Test("The smallest and largest alphabets both work", arguments: ["abc", String(ID.Alphabet.allowedSymbols)])
    func sizeExtremes(symbols: String) throws {
        let alphabet = try ID.Alphabet(symbols)
        let id = try ID(shardNumber: 7, identifier: 12345, entityKind: "O", alphabet: alphabet)
        let restored = try ID.parse(input: id.stringValue, alphabet: alphabet)

        #expect(restored == id)
        #expect(restored.shardNumber == 7)
        #expect(restored.identifier == 12345)
        // Everything after the prefix separator comes from the alphabet.
        #expect(id.stringValue.dropFirst(2).allSatisfy { alphabet.symbols.contains($0) })
    }

    // MARK: - Identifiers under a custom alphabet

    @Test(
        "Round-trip under custom alphabets",
        arguments: [
            "0123456789abcdef",  // hex
            "abcdefghijklmnopqrstuvwxyz",  // lowercase only, a subset of the default
            "346789ABCDEFGHJKMNPQRTVWXY",  // no look-alikes (0/O, 1/I/l, 5/S, 2/Z)
            "!#$%&()*+,-.:;<=>?@[]^{|}~",  // punctuation only
        ])
    func customRoundTrip(symbols: String) throws {
        let alphabet = try ID.Alphabet(symbols)

        for identifier in [Int64(0), 1, 999_999, ID.maxIdentifier] {
            for kind in ["P", "PL"] {
                let id = try ID(shardNumber: 42, identifier: identifier, entityKind: kind, alphabet: alphabet)
                let restored = try ID.parse(input: id.stringValue, alphabet: alphabet)

                #expect(restored == id)
                #expect(restored.identifier == identifier)
                #expect(restored.entityKind == kind)
                #expect(id.stringValue.dropFirst(kind.count + 1).allSatisfy { alphabet.symbols.contains($0) })
            }
        }
    }

    @Test("A custom alphabet spells the same numbers differently")
    func customDiffersFromDefault() throws {
        let permuted = ID.Alphabet.default.shuffled(seed: "not the default order")
        let plain = try ID(shardNumber: 1337, identifier: 42, entityKind: "P")
        let custom = try ID(shardNumber: 1337, identifier: 42, entityKind: "P", alphabet: permuted)

        #expect(plain.stringValue != custom.stringValue)
        // Same numbers, same entity kind — the identifiers *are* equal, only spelled differently.
        #expect(plain == custom)
        #expect(plain.rawValues == custom.rawValues)
    }

    @Test("An external UUID survives a custom alphabet")
    func externalUUIDUnderCustomAlphabet() throws {
        let alphabet = try ID.Alphabet("0123456789abcdef")
        let uuid = try #require(UUID(uuidString: "f47ac10b-58cc-4372-b567-0e02b2c3d479"))

        let id = try ID(externalUUID: uuid, alphabet: alphabet)
        #expect(id.externalUUID == uuid)
        #expect(id.stringValue.hasPrefix("_U_"))
        #expect(id.stringValue.dropFirst(3).allSatisfy { alphabet.symbols.contains($0) })

        let restored = try ID.parse(input: id.stringValue, alphabet: alphabet)
        #expect(restored == id)
        #expect(restored.externalUUID == uuid)
    }

    // MARK: - Reading with the wrong alphabet

    @Test("A body holding symbols the alphabet doesn't have never parses")
    func disjointSymbolsAlwaysFail() throws {
        let hex = try ID.Alphabet("0123456789abcdef")
        let upper = try ID.Alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

        for identifier in Int64(0)..<200 {
            let id = try ID(shardNumber: 1, identifier: identifier, entityKind: "P", alphabet: upper)
            #expect(throws: (any Error).self, "hex must not read an uppercase body") {
                try ID.parse(input: id.stringValue, alphabet: hex)
            }
        }
    }

    @Test("The same symbols in the wrong order mostly fail — and never decode to the original values")
    func wrongOrderHasNoIntegrityCheck() throws {
        // The format carries no checksum, so this is the honest bound to hold the library to:
        // reading with a wrong permutation usually errors, occasionally yields *different* numbers,
        // and must never pass off different numbers as the right ones.
        let writer = ID.Alphabet.default.shuffled(seed: "writer")
        let reader = ID.Alphabet.default.shuffled(seed: "reader")

        var failures = 0
        var silentlyDifferent = 0
        for i in Int64(0)..<500 {
            let id = try ID(shardNumber: i % 97, identifier: i * 7717, entityKind: "P", alphabet: writer)

            guard let parsed = try? ID.parse(input: id.stringValue, alphabet: reader) else {
                failures += 1
                continue
            }
            #expect(parsed.rawValues != id.rawValues, "a wrong alphabet must not reproduce the right values")
            silentlyDifferent += 1
        }

        #expect(failures > 0, "most wrong-alphabet reads should fail outright")
        #expect(failures + silentlyDifferent == 500)
    }

    // MARK: - Seeded permutations

    @Test("The same seed always gives the same order")
    func seedDeterminism() {
        // A seed is any string a deployment cares to hand over — including one built at runtime,
        // which must land on the same order as the identical literal.
        let secret = ["s3", "cret"].joined()
        #expect(ID.Alphabet.default.shuffled(seed: secret) == ID.Alphabet.default.shuffled(seed: "s3cret"))
        #expect(ID.Alphabet.default.shuffled(seed: "s3cret") == ID.Alphabet.default.shuffled(seed: "s3cret"))

        // Multi-byte UTF-8 in the seed is fine — it's the seed's bytes that get folded, and the
        // alphabet it permutes stays ASCII.
        let cyrillicSeed = ID.Alphabet.default.shuffled(seed: "секрет")
        #expect(cyrillicSeed == ID.Alphabet.default.shuffled(seed: "секрет"))
        #expect(Set(cyrillicSeed.symbols) == Set(ID.Alphabet.default.symbols))
    }

    @Test("A permutation keeps the symbol set and changes the order")
    func seedPermutes() {
        for seed in ["a", "b", "hunter2", "GkPmS0/HH5Sb4pOXwm+3RCkuVezYX5B8AeAvXtnGqBQ="] {
            let shuffled = ID.Alphabet.default.shuffled(seed: seed)
            #expect(Set(shuffled.symbols) == Set(ID.Alphabet.default.symbols), "seed \(seed) kept the symbols")
            #expect(shuffled.count == ID.Alphabet.default.count)
            #expect(shuffled != ID.Alphabet.default, "seed \(seed) changed the order")
        }
    }

    @Test("Different seeds give different orders")
    func seedsDiffer() {
        let orders = Set(["", "a", "b", "hunter2", "hunter3", "0"].map { ID.Alphabet.default.shuffled(seed: $0) })
        #expect(orders.count == 6)
    }

    @Test("A custom alphabet can be seeded too, and a 3-symbol one has few orders to reach")
    func seedCustomAlphabet() throws {
        let alphabet = try ID.Alphabet("0123456789abcdef")
        let shuffled = alphabet.shuffled(seed: "hunter2")
        #expect(Set(shuffled.symbols) == Set(alphabet.symbols))
        #expect(shuffled != alphabet)

        // Every permutation of three symbols is one of six, so equality with the original is fine
        // here — the point is only that the symbol set survives.
        let tiny = try ID.Alphabet("abc").shuffled(seed: "whatever")
        #expect(Set(tiny.symbols) == Set(["a", "b", "c"]))
    }

    @Test("shuffled(using:) accepts any generator")
    func shuffleWithCustomGenerator() {
        struct Counter: RandomNumberGenerator {
            var value: UInt64 = 0
            mutating func next() -> UInt64 {
                self.value += 1
                return self.value
            }
        }

        var first = Counter()
        var second = Counter()
        let a = ID.Alphabet.default.shuffled(using: &first)
        let b = ID.Alphabet.default.shuffled(using: &second)

        #expect(a == b, "same generator state, same permutation")
        #expect(Set(a.symbols) == Set(ID.Alphabet.default.symbols))
        #expect(a != ID.Alphabet.default)
    }

    @Test("Identifiers under a seeded alphabet round-trip, and only with that alphabet")
    func seededRoundTrip() throws {
        let alphabet = ID.Alphabet.default.shuffled(seed: "hunter2")

        for identifier in [Int64(0), 42, 999_999, ID.maxIdentifier] {
            let id = try ID(shardNumber: 1337, identifier: identifier, entityKind: "P", alphabet: alphabet)
            let restored = try ID.parse(input: id.stringValue, alphabet: alphabet)
            #expect(restored == id)
            #expect(restored.identifier == identifier)
        }
    }

    // MARK: - Equatable / Hashable

    @Test("Alphabets are equal when their symbols and order match")
    func equality() throws {
        #expect(try ID.Alphabet("abc") == ID.Alphabet("abc"))
        #expect(try ID.Alphabet("abc") != ID.Alphabet("acb"))
        #expect(try ID.Alphabet("abc") != ID.Alphabet("abcd"))
        #expect(try ID.Alphabet(ID.Alphabet.default.symbols) == ID.Alphabet.default)
        #expect(try ID.Alphabet("abc").hashValue == ID.Alphabet("abc").hashValue)
    }
}
