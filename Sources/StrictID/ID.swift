import Foundation
import sqids

/// A strict string identifier of the form `{PREFIX}_{sqids}` (for example, `P_I7kLcO0z`).
///
/// The prefix and the body are separated by a single underscore. Identifiers created before the
/// format change pad the prefix zone to `prefixSize` characters instead (`P__I7kLcO0z`);
/// `SeparatorMode` selects which of the two forms is rendered and which ones `parse` accepts.
///
/// The internal representation `rawValues` is an array of **three** `Int64` values:
/// ```
/// [shardNumber, bytesSum(entityKind), identifier]
/// ```
/// The middle element (`bytesSum`) is the sum of the UTF-8 bytes of `entityKind`. Its purpose is
/// to make encoded strings of different entity types look visually distinct even when
/// `shardNumber` and `identifier` are identical. It's computed automatically in
/// `init(shardNumber:identifier:entityKind:)`; when using `init(rawValues:entityKind:)` the
/// middle element must be computed manually.
public struct ID: Sendable {
    public typealias RawValue = Int64
    public typealias RawValues = [RawValue]

    public enum E: Error {
        /// Sqids parsing error
        case ParseError

        /// Input string has an invalid length
        case InvalidInputStringSize

        /// Input raw values is not a 3 integers array
        case InvalidInputRawValuesSize

        /// Identifier must be less than `Self.maxIdentifier`
        case TooBigIdentifier

        /// Entity prefix must be 1 or 2 characters long
        case InvalidEntityPrefixLength

        /// External-UUID entity prefix must be the reserved marker `_` followed by exactly one non-`_` character
        case InvalidExternalEntityKind

        /// The underscore run between the prefix and the body doesn't match the `SeparatorMode` in effect
        case InvalidPrefixSeparator
    }

    /// How the separator between the entity prefix and the sqids body is rendered, and which
    /// separators `parse` accepts.
    ///
    /// The prefix zone used to be padded with underscores to a fixed width of `prefixSize` (3)
    /// characters, so a one-character prefix was followed by **two** underscores (`P__zuYa75Z5`).
    /// That padding served a fixed-width layout which no longer exists — the body length is
    /// variable anyway — so the modern format separates the prefix from the body with exactly one
    /// underscore (`P_zuYa75Z5`). Only one-character prefixes are affected: a two-character prefix
    /// (`PL_lDm0uwOeWd1aU9uIj`) and an external-UUID prefix (`_U_brd1jN`) are byte-identical in
    /// both formats.
    ///
    /// The cases form a migration ladder — `.strictLegacy` → `.legacy` → `.modern` →
    /// `.strictModern` — where every step is deployable while peers are one step behind: teach
    /// every reader to accept both formats first, then flip the writers over, then optionally
    /// tighten back down once no legacy string is left anywhere.
    public enum SeparatorMode: Sendable, Hashable, CaseIterable {
        /// Renders one underscore; accepts one underscore only — legacy input throws
        /// `E.InvalidPrefixSeparator`.
        case strictModern

        /// Renders one underscore; accepts both formats. The default.
        case modern

        /// Renders the legacy padding; accepts both formats.
        case legacy

        /// Renders the legacy padding; accepts the legacy format only — modern input throws
        /// `E.InvalidPrefixSeparator`.
        case strictLegacy

        /// Whether new string values pad the prefix zone to `ID.prefixSize` characters.
        @inlinable
        public var rendersLegacyPadding: Bool {
            switch self {
            case .strictModern, .modern: false
            case .legacy, .strictLegacy: true
            }
        }

        /// Whether `ID.parse(input:mode:)` accepts the legacy padded separator.
        @inlinable
        public var acceptsLegacy: Bool { self != .strictModern }

        /// Whether `ID.parse(input:mode:)` accepts the modern single-underscore separator.
        @inlinable
        public var acceptsModern: Bool { self != .strictLegacy }
    }

    @usableFromInline
    internal static let underscore: Character = "_"

    /// Underscore strings of length 0...2, indexed by length. The separator between the prefix and
    /// the body is always one of them.
    @usableFromInline
    internal static let underscores: [String] = (0...2).map { String(repeating: "_", count: $0) }

    /// The symbols of the installed alphabet, in order — `Alphabet.default`'s digits, uppercase and
    /// lowercase Latin unless `bootstrap` installed something else. The underscore is never among
    /// them: it's reserved for the prefix separator.
    public static var rawAlphabet: [Character] { Self.configuration.alphabet.symbols }

    public static var alphabet: String { Self.configuration.alphabet.string }
    public static var alphabetSize: Int { Self.configuration.alphabet.count }

    /// The installed alphabet plus the prefix separator — every character a string value can hold,
    /// as long as the entity prefixes are drawn from the alphabet too.
    public static var fullAlphabet: String { Self.alphabet + String(Self.underscore) }
    public static var fullAlphabetSize: Int { Self.alphabetSize + 1 }

    /// The width the prefix zone (`entityKind` plus underscore padding) is filled up to in the
    /// legacy format. Irrelevant to the modern one, where the separator is always a single
    /// underscore regardless of prefix length.
    public static let prefixSize = 3

    public static let minLength = 6

    public static let maxIdentifier: RawValue = 9_007_199_254_740_991

    public let entityKind: String
    public let rawValues: RawValues

    /// The string form of the identifier — the exact input `parse` was handed (so a legacy string
    /// stays legacy on the way out), or the freshly rendered string for an identifier built from
    /// its components.
    public let stringValue: String

    @inlinable
    public var shardNumber: RawValue {
        self.rawValues[0]
    }

    @inlinable
    public var identifier: RawValue {
        self.rawValues[2]
    }

    /// Designated init — skips input string validation, for trusted calls within the type only.
    @usableFromInline
    internal init(rawValues: RawValues, entityKind: String, stringValue: String) throws(E) {
        guard rawValues.count == 3 else { throw E.InvalidInputRawValuesSize }
        guard 1...2 ~= entityKind.count else { throw E.InvalidEntityPrefixLength }
        self.rawValues = rawValues
        self.entityKind = entityKind
        self.stringValue = stringValue
        guard self.identifier <= Self.maxIdentifier else { throw E.TooBigIdentifier }
    }

    @inlinable
    public init(
        rawValues: RawValues,
        entityKind: String,
        alphabet: Alphabet = ID.configuration.alphabet,
        mode: SeparatorMode = ID.configuration.separatorMode
    ) throws(E) {
        guard rawValues.count == 3 else { throw E.InvalidInputRawValuesSize }
        guard 1...2 ~= entityKind.count else { throw E.InvalidEntityPrefixLength }
        guard rawValues[2] <= Self.maxIdentifier else { throw E.TooBigIdentifier }
        let encoded = try alphabet.encode(rawValues)
        let sv = entityKind + Self.separator(for: entityKind, mode: mode) + encoded
        try self.init(rawValues: rawValues, entityKind: entityKind, stringValue: sv)
    }

    @inlinable
    public init(
        shardNumber: RawValue,
        identifier: RawValue,
        entityKind: String,
        alphabet: Alphabet = ID.configuration.alphabet,
        mode: SeparatorMode = ID.configuration.separatorMode
    ) throws(E) {
        try self.init(
            rawValues: [
                shardNumber,
                getBytes(entityKind).reduce(RawValue(0)) { $0 + RawValue($1) },
                identifier,
            ],
            entityKind: entityKind,
            alphabet: alphabet,
            mode: mode
        )
    }

    @inlinable
    public init<IDPrefixEnum: RawRepresentable>(
        shardNumber: RawValue,
        identifier: RawValue,
        entityKind: IDPrefixEnum,
        alphabet: Alphabet = ID.configuration.alphabet,
        mode: SeparatorMode = ID.configuration.separatorMode
    ) throws(E) where IDPrefixEnum.RawValue == String {
        try self.init(
            shardNumber: shardNumber,
            identifier: identifier,
            entityKind: entityKind.rawValue,
            alphabet: alphabet,
            mode: mode
        )
    }

    @inlinable
    public init(
        firstValue: RawValue,
        secondValue: RawValue,
        thirdValue: RawValue,
        entityKind: String,
        alphabet: Alphabet = ID.configuration.alphabet,
        mode: SeparatorMode = ID.configuration.separatorMode
    ) throws(E) {
        try self.init(
            rawValues: [firstValue, secondValue, thirdValue],
            entityKind: entityKind,
            alphabet: alphabet,
            mode: mode
        )
    }

    /// The underscore run that goes between the prefix and the body.
    ///
    /// A single underscore in the modern format; in the legacy one, as many as it takes to fill the
    /// prefix zone up to `prefixSize` — two for a one-character prefix, one for a two-character
    /// one, which is exactly why two-character prefixes render identically in both formats.
    ///
    /// Only ever called after `entityKind.count` has been validated to be 1 or 2.
    @usableFromInline
    internal static func separator(for entityKind: String, mode: SeparatorMode) -> String {
        mode.rendersLegacyPadding
            ? Self.underscores[Self.prefixSize - entityKind.count]
            : Self.underscores[1]
    }

    /// Checks a parsed separator against the mode: exactly one underscore is the modern form,
    /// exactly `prefixSize - entityKind.count` of them the legacy one. Anything else (three or
    /// more underscores, say) belongs to neither format and is always rejected.
    internal static func validateSeparator(
        length separatorLength: Int,
        entityKind: String,
        mode: SeparatorMode
    ) throws(E) {
        if separatorLength == 1, mode.acceptsModern { return }
        if separatorLength == Self.prefixSize - entityKind.count, mode.acceptsLegacy { return }
        throw E.InvalidPrefixSeparator
    }

    public static func parse(
        input: String,
        alphabet: Alphabet = ID.configuration.alphabet,
        mode: SeparatorMode = ID.configuration.separatorMode
    ) throws(E) -> Self {
        // External UUID: the prefix starts with the reserved underscore marker. Regular
        // identifiers never start with `_`, so this branch is strictly additive — all the
        // logic below is untouched and keeps handling them exactly as before.
        if input.first == Self.underscore {
            return try Self.parseExternal(input: input, alphabet: alphabet)
        }

        // The prefix zone is a leading run of non-`_` characters (the `entityKind`) followed by a
        // run of underscores; the body starts at the first non-`_` character after them. Neither
        // the prefix nor a sqids body can contain an underscore, so the scan is unambiguous — the
        // separator length is what tells the two formats apart.
        var entityType: String = ""
        var separatorLength = 0
        var prefixEnd: String.Index = input.startIndex
        for pos in input.indices {
            let char = input[pos]
            if char == Self.underscore {
                separatorLength += 1
            } else if separatorLength > 0 {
                prefixEnd = pos
                break
            } else {
                entityType.append(char)
            }
        }

        if separatorLength > 0 {
            try Self.validateSeparator(length: separatorLength, entityKind: entityType, mode: mode)
        }

        let rawID = String(input[prefixEnd...])
        let rawValues = try alphabet.decode(rawID)

        guard rawValues.count == 3 else {
            throw E.InvalidInputRawValuesSize
        }

        return try self.init(rawValues: rawValues, entityKind: entityType, stringValue: input)
    }
}

// MARK: - External UUID compatibility
//
// An external UUID (of any version) fits into a triple of numbers without loss: the 3×Int64
// container under the real constraints (fields ≥ 0, identifier ≤ 2⁵³−1) gives 63+63+53 = 179
// usable bits, while a UUID is only 128 bits. The layout is fixed: identifier(53) + shard(53) +
// bytesSum-slot(22). The UUID version/variant isn't singled out — it simply rides along inside
// those 128 bits as-is.
//
// The marker that "this ID holds an external UUID" is the reserved `_` as the first character of
// the prefix (an `entityKind` of the form `"_X"`). The underscore is already outside the regular
// prefix alphabet, so no alphanumeric letter is lost to the marker; it merely limits the number
// of external subtypes to one free character.
extension ID {
    /// Default prefix for a wrapped external UUID: the marker `_` plus the tag `U`.
    public static let defaultExternalEntityKind = "_U"

    /// Wraps an external UUID (of any version) into an `ID` without loss.
    ///
    /// There's no `mode:` parameter here: an external prefix is two characters long, so both
    /// formats render it with a single underscore and produce the very same string.
    ///
    /// - Parameter entityKind: the external prefix — the marker `_` and exactly one non-`_`
    ///   character (for example `"_U"`).
    public init(
        externalUUID uuid: UUID,
        entityKind: String = ID.defaultExternalEntityKind,
        alphabet: Alphabet = ID.configuration.alphabet
    ) throws(E) {
        guard entityKind.count == 2,
            entityKind.first == Self.underscore,
            entityKind.last != Self.underscore
        else {
            throw E.InvalidExternalEntityKind
        }
        try self.init(rawValues: Self.pack(uuid), entityKind: entityKind, alphabet: alphabet)
    }

    /// The reconstructed external UUID, if this `ID` wraps one (prefix starts with `_`);
    /// otherwise `nil` (this is a regular internal identifier).
    public var externalUUID: UUID? {
        guard self.entityKind.first == Self.underscore else { return nil }
        return Self.unpack(self.rawValues)
    }

    /// Parses an external ID. An external `entityKind` is always two characters (the marker plus
    /// one tag character), so its separator is a single underscore in **both** formats — the prefix
    /// zone occupies exactly `prefixSize` characters and the body starts at that offset regardless
    /// of `SeparatorMode`, which is why this branch needs no mode of its own.
    private static func parseExternal(input: String, alphabet: Alphabet) throws(E) -> Self {
        guard input.count >= Self.prefixSize else { throw E.InvalidInputStringSize }
        let regionEnd = input.index(input.startIndex, offsetBy: Self.prefixSize)

        // entityKind = the prefix zone without TRAILING underscores (the leading marker is kept).
        var region = String(input[input.startIndex..<regionEnd])
        while region.last == Self.underscore { region.removeLast() }
        let entityKind = region

        let body = String(input[regionEnd...])
        let rawValues = try alphabet.decode(body)
        guard rawValues.count == 3 else { throw E.InvalidInputRawValuesSize }

        return try self.init(rawValues: rawValues, entityKind: entityKind, stringValue: input)
    }

    /// Packs a 128-bit UUID into `[shard(53), bytesSum-slot(22), identifier(53)]`.
    static func pack(_ uuid: UUID) -> RawValues {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        var hi: UInt64 = 0
        var lo: UInt64 = 0
        for i in 0..<8 { hi = (hi << 8) | UInt64(bytes[i]) }
        for i in 8..<16 { lo = (lo << 8) | UInt64(bytes[i]) }

        let mask53: UInt64 = (1 << 53) - 1
        let mask42: UInt64 = (1 << 42) - 1
        let mask22: UInt64 = (1 << 22) - 1

        let identifier = lo & mask53  // bits 0..52
        let shard = (lo >> 53) | ((hi & mask42) << 11)  // bits 53..105
        let slot = (hi >> 42) & mask22  // bits 106..127

        return [RawValue(shard), RawValue(slot), RawValue(identifier)]
    }

    /// Unpacks the triple back into the original UUID (the exact inverse of `pack`).
    static func unpack(_ rawValues: RawValues) -> UUID {
        let shard = UInt64(rawValues[0])
        let slot = UInt64(rawValues[1])
        let identifier = UInt64(rawValues[2])

        let mask53: UInt64 = (1 << 53) - 1
        let mask22: UInt64 = (1 << 22) - 1
        let mask11: UInt64 = (1 << 11) - 1

        let lo = (identifier & mask53) | ((shard & mask11) << 53)
        let hi = ((shard & mask53) >> 11) | ((slot & mask22) << 42)

        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[7 - i] = UInt8((hi >> (8 * UInt64(i))) & 0xFF) }
        for i in 0..<8 { bytes[15 - i] = UInt8((lo >> (8 * UInt64(i))) & 0xFF) }

        var t: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &t) { $0.copyBytes(from: bytes) }
        return UUID(uuid: t)
    }
}

extension ID: Equatable {
    /// Identity is `(entityKind, rawValues)` — what the identifier *is*, not how it happens to be
    /// spelled. The two separator formats of one identifier are therefore equal
    /// (`P__zuYa75Z5` == `P_zuYa75Z5`), which is what keeps a `Set<ID>` or an `[ID: T]` free of
    /// duplicates while both formats are in circulation. Compare `stringValue` directly when the
    /// literal spelling is what matters.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValues == rhs.rawValues && lhs.entityKind == rhs.entityKind
    }
}

extension ID: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawValues)
        hasher.combine(self.entityKind)
    }
}

extension ID: CustomStringConvertible {
    public var description: String {
        self.stringValue
    }
}

extension ID: LosslessStringConvertible {
    public init?(_ description: String) {
        guard let result = try? Self.parse(input: description) else {
            return nil
        }

        self = result
    }
}

extension ID: Codable {
    enum CodingKeys: CodingKey {
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        self = try Self.parse(input: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(self.stringValue)
    }
}

extension ID: CustomReflectable {
    public var customMirror: Mirror {
        return Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .struct
        )
    }
}

extension Sqids: @unchecked @retroactive Sendable {}
