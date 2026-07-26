import Foundation
import sqids

extension ID {
    /// The symbols an identifier's body is spelled with, in the order that gives them their values.
    ///
    /// Both the *set* of symbols and their *order* are yours to choose — a smaller alphabet for
    /// longer but plainer identifiers, a bigger one for shorter identifiers, a permuted one so that
    /// identifiers can't be read by anybody running stock sqids. The order is part of the format:
    /// the same numbers over the same symbols in a different order encode to a different string.
    ///
    /// Symbols are limited to what sqids itself can encode: **printable ASCII**, no space, and not
    /// the underscore, which is reserved for the prefix separator. That's `allowedSymbols` — 93
    /// characters, which is therefore also the largest an alphabet can be. sqids reads the byte
    /// value of every character while shuffling its internal alphabet, so anything outside ASCII —
    /// Cyrillic, Greek, emoji — is out of reach of the algorithm, not just of this type.
    ///
    /// > Warning: only `default`'s 62 alphanumerics travel everywhere unescaped. `allowedSymbols` is
    /// > everything *sqids* can encode, which is a far lower bar than everything a URL, a JSON
    /// > string, a shell command, a filename, a CSV field or a regex can carry as-is: an alphabet
    /// > reaching into its punctuation yields identifiers like `O_C[4<KD}u` or `O_x?y&z`, which need
    /// > percent-encoding, quoting or escaping in each of those, and change what a URL *means* if
    /// > they don't get it. If you want more symbols and still no escaping, stop at the RFC 3986
    /// > unreserved set — `default.symbols + ["-", ".", "~"]`, 65 symbols. See the README for what
    /// > the wider alphabet actually buys (one character on the longest possible identifier).
    public struct Alphabet: Sendable {
        public enum E: Error {
            /// An alphabet needs at least `Alphabet.minCount` symbols
            case TooFewSymbols

            /// Symbols must be unique
            case DuplicateSymbols

            /// The underscore is reserved for the prefix separator and can't be a symbol
            case ReservedSeparatorSymbol

            /// sqids encodes ASCII only — every symbol must be an ASCII character
            case NonASCIISymbols

            /// Symbols must be printable and not a space: control characters have no business in an
            /// identifier that travels through logs, URLs and databases
            case NonPrintableSymbols
        }

        /// Deterministic, portable PRNG behind `Alphabet.shuffled(seed:)`. **Not cryptographic** —
        /// see the warning on `shuffled(seed:)`.
        ///
        /// A seed is an arbitrary string — a base64 blob out of `openssl rand -base64 32`, a
        /// passphrase, whatever a deployment hands over at runtime; what's in it is the caller's
        /// business. Its UTF-8 bytes are folded into 64 bits with FNV-1a and SplitMix64 produces the
        /// stream from there. Both steps are written out rather than borrowed from the standard
        /// library so that the permutation for a given seed is stable across platforms, Swift
        /// versions and other language implementations of this format.
        public struct SeededGenerator: RandomNumberGenerator, Sendable {
            private var state: UInt64

            /// Folds the seed into the PRNG state with FNV-1a: `hash = 0xcbf29ce484222325`, then for
            /// every UTF-8 byte `hash = (hash ^ byte) * 0x100000001b3`, wrapping on overflow.
            public init(seed: String) {
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a 64-bit offset basis
                for byte in seed.utf8 {
                    hash ^= UInt64(byte)
                    hash = hash &* 0x0000_0100_0000_01b3  // FNV-1a 64-bit prime
                }
                self.state = hash
            }

            public mutating func next() -> UInt64 {
                self.state = self.state &+ 0x9e37_79b9_7f4a_7c15
                var z = self.state
                z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
                z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
                return z ^ (z >> 31)
            }
        }

        /// Every symbol an alphabet may draw on: printable ASCII in code-point order, minus the
        /// space and the reserved underscore. The 62 alphanumerics come first, so
        /// `allowedSymbols.prefix(62)` is exactly `default`.
        ///
        /// The 31 that follow are punctuation, and identifiers spelled with them are **not** safe to
        /// hand to a URL, a JSON string, a shell, a filename or a regex unescaped — see the warning
        /// on `Alphabet` before reaching for the full set.
        public static let allowedSymbols: [Character] = {
            let printable = (0x21...0x7e).map { Character(UnicodeScalar(UInt8($0))) }
            let alphanumeric = printable.filter { $0.isLetter || $0.isNumber }
            let punctuation = printable.filter { !($0.isLetter || $0.isNumber) && $0 != ID.underscore }
            return alphanumeric + punctuation
        }()

        /// The fewest symbols sqids will encode with.
        public static let minCount = Sqids.minAlphabetLength

        /// The most symbols an alphabet can hold — every symbol in `allowedSymbols`, once.
        public static let maxCount = Self.allowedSymbols.count

        /// The built-in alphabet: digits, uppercase and lowercase Latin in code-point order. What
        /// every identifier was spelled with before alphabets became configurable.
        public static let `default` = Alphabet(unchecked: Array(Self.allowedSymbols.prefix(62)))

        /// The symbols, in the order that gives them their numeric values.
        public let symbols: [Character]

        internal let sqids: Sqids

        /// The symbols as a string, in order.
        @inlinable
        public var string: String { String(self.symbols) }

        /// How many symbols the alphabet holds.
        @inlinable
        public var count: Int { self.symbols.count }

        /// Builds an alphabet from symbols in the order you want them.
        ///
        /// Reordering by hand is just handing over a different order — there's nothing else to it:
        /// ```swift
        /// let hex = try ID.Alphabet("0123456789abcdef")
        /// let reversed = try ID.Alphabet(ID.Alphabet.default.symbols.reversed())
        /// let everything = try ID.Alphabet(ID.Alphabet.allowedSymbols)
        /// ```
        ///
        /// - Throws: `E` when the symbols can't spell identifiers — fewer than `minCount` of them,
        ///   duplicates, the reserved `_`, or anything that isn't printable ASCII.
        public init(_ symbols: some Sequence<Character>) throws(E) {
            let symbols = Array(symbols)

            guard symbols.count >= Self.minCount else { throw E.TooFewSymbols }
            guard Set(symbols).count == symbols.count else { throw E.DuplicateSymbols }
            guard !symbols.contains(ID.underscore) else { throw E.ReservedSeparatorSymbol }
            // Together with uniqueness, these two leave at most `maxCount` symbols standing, so
            // there's no size ceiling to check separately — an oversized alphabet always trips one of
            // them. `isASCII` alone isn't enough: `\r\n` is a single ASCII `Character`.
            guard symbols.allSatisfy(\.isASCII) else { throw E.NonASCIISymbols }
            guard symbols.allSatisfy({ $0.isPrintableASCII }) else { throw E.NonPrintableSymbols }

            self.init(unchecked: symbols)
        }

        /// Trusted init for symbols already known to be valid — the built-in alphabet and
        /// permutations of an existing one, which can't break any of the validated guarantees.
        internal init(unchecked symbols: [Character]) {
            self.symbols = symbols
            self.sqids = Sqids(alphabet: String(symbols), minLength: ID.minLength)
        }

        /// The same symbols in a different order, derived from `seed`: the same seed gives the same
        /// permutation on every platform, in every run, forever — and in any other implementation
        /// that follows the recipe below.
        ///
        /// ```swift
        /// let alphabet = ID.Alphabet.default.shuffled(seed: "GkPmS0/HH5Sb4pOXwm+3RCkuVezYX5B8AeAvXtnGqBQ=")
        /// try ID.bootstrap(alphabet: alphabet)
        /// // or, equivalently, in one step:
        /// try ID.bootstrap(seed: "GkPmS0/HH5Sb4pOXwm+3RCkuVezYX5B8AeAvXtnGqBQ=")
        /// ```
        ///
        /// The seed is an arbitrary string, meant to arrive at runtime as a deployment secret.
        ///
        /// The recipe, in full: `SeededGenerator` folds the seed's UTF-8 bytes into 64 bits with
        /// FNV-1a and runs SplitMix64 from there, and the symbols are permuted by a Fisher–Yates walk
        /// down from the last index, taking `j = next() % (i + 1)` at every step. Nothing here leans
        /// on standard-library internals, so a port to another language is a mechanical exercise.
        ///
        /// > Warning: this is **obfuscation, not encryption**. sqids is not a cipher and neither is
        /// > a permuted alphabet: it only makes identifiers unguessable to someone who hasn't seen
        /// > enough of them. Anybody who collects a modest number of your identifiers — or who reads
        /// > the seed out of your configuration, environment or crash dump — can recover the
        /// > ordering. Never treat a secret seed as access control, authentication, or a reason to
        /// > let an identifier stand in for a capability.
        public func shuffled(seed: String) -> Self {
            var generator = SeededGenerator(seed: seed)
            return self.shuffled(using: &generator)
        }

        /// The same symbols permuted by any generator, for when you want to drive the order
        /// yourself. Fisher–Yates, walking down from the last index.
        public func shuffled(using generator: inout some RandomNumberGenerator) -> Self {
            var symbols = self.symbols
            var i = symbols.count - 1
            while i > 0 {
                let j = Int(generator.next() % UInt64(i + 1))
                symbols.swapAt(i, j)
                i -= 1
            }
            return Self(unchecked: symbols)
        }

        /// Encodes `rawValues` into a body spelled with these symbols.
        @usableFromInline
        internal func encode(_ rawValues: RawValues) throws(ID.E) -> String {
            do {
                return try self.sqids.encode(rawValues)
            } catch {
                throw ID.E.ParseError
            }
        }

        /// Decodes a body back into raw values. A body holding symbols this alphabet doesn't have
        /// decodes to nothing, which the caller reports as `InvalidInputRawValuesSize`; a body whose
        /// symbols all fit but were written in a *different order* decodes to different numbers, and
        /// nothing flags that — the format carries no checksum.
        @usableFromInline
        internal func decode(_ body: String) throws(ID.E) -> RawValues {
            do {
                return try self.sqids.decode(body)
            } catch {
                throw ID.E.ParseError
            }
        }
    }
}

extension ID.Alphabet: Equatable {
    /// The symbols and their order are the whole identity — the sqids instance is derived from them.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.symbols == rhs.symbols
    }
}

extension ID.Alphabet: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.symbols)
    }
}

extension Character {
    /// Printable ASCII, excluding the space: code points 0x21...0x7E.
    internal var isPrintableASCII: Bool {
        guard let ascii = self.asciiValue else { return false }
        return 0x21...0x7e ~= ascii
    }
}
