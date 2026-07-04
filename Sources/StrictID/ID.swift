import Foundation
import sqids

/// A strict string identifier of the form `{PREFIX}_{sqids}` (for example, `P__I7kLcO0z`).
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
    }

    @usableFromInline
    internal static let underscore: Character = "_"

    @usableFromInline
    internal static let underscorePadding: [String] = (0...2).map { String(repeating: "_", count: $0) }

    public static let rawAlphabet = Array<Character>([
        "0", "1", "2", "3", "4",
        "5", "6", "7", "8", "9",
        "a", "b", "c", "d", "e",
        "f", "g", "h", "i", "j",
        "k", "l", "m", "n", "o",
        "p", "q", "r", "s", "t",
        "u", "v", "w", "x", "y",
        "z",
        "A", "B", "C", "D", "E",
        "F", "G", "H", "I", "J",
        "K", "L", "M", "N", "O",
        "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y",
        "Z",
        // also an underscore is a valid character, but it's reserved for prefixes
    ])

    public static let alphabet: String = String(Self.rawAlphabet.sorted())
    public static let alphabetSize = Self.alphabet.count
    public static let fullAlphabet = Self.alphabet + String(Self.underscore)
    public static let fullAlphabetSize = Self.fullAlphabet.count

    @usableFromInline
    internal static let sqids: Sqids = Sqids(
        alphabet: Self.alphabet,
        minLength: Self.minLength
    )

    public static let prefixSize = 3

    public static let minLength = 6

    public static let maxIdentifier: RawValue = 9_007_199_254_740_991

    public let entityKind: String
    public let rawValues: RawValues
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
    public init(rawValues: RawValues, entityKind: String) throws(E) {
        guard rawValues.count == 3 else { throw E.InvalidInputRawValuesSize }
        guard 1...2 ~= entityKind.count else { throw E.InvalidEntityPrefixLength }
        guard rawValues[2] <= Self.maxIdentifier else { throw E.TooBigIdentifier }
        let encoded: String
        do {
            encoded = try Self.sqids.encode(rawValues)
        } catch {
            throw E.ParseError
        }
        let sv = entityKind + Self.underscorePadding[Self.prefixSize - entityKind.count] + encoded
        try self.init(rawValues: rawValues, entityKind: entityKind, stringValue: sv)
    }

    @inlinable
    public init(shardNumber: RawValue, identifier: RawValue, entityKind: String) throws(E) {
        try self.init(
            rawValues: [
                shardNumber,
                getBytes(entityKind).reduce(RawValue(0)) { $0 + RawValue($1) },
                identifier,
            ],
            entityKind: entityKind
        )
    }

    @inlinable
    public init<IDPrefixEnum: RawRepresentable>(
        shardNumber: RawValue,
        identifier: RawValue,
        entityKind: IDPrefixEnum
    ) throws(E) where IDPrefixEnum.RawValue == String {
        try self.init(shardNumber: shardNumber, identifier: identifier, entityKind: entityKind.rawValue)
    }

    @inlinable
    public init(firstValue: RawValue, secondValue: RawValue, thirdValue: RawValue, entityKind: String) throws(E) {
        try self.init(rawValues: [firstValue, secondValue, thirdValue], entityKind: entityKind)
    }

    public static func parse(input: String) throws(E) -> Self {
        // External UUID: the prefix starts with the reserved underscore marker. Regular
        // identifiers never start with `_`, so this branch is strictly additive — all the
        // logic below is untouched and keeps handling them exactly as before.
        if input.first == Self.underscore {
            return try Self.parseExternal(input: input)
        }

        var entityType: String = ""
        var prefixEnd: String.Index = input.startIndex
        var previousChar: Character = "?"
        for pos in input.indices {
            let char = input[pos]
            if char != Self.underscore {
                if previousChar == Self.underscore {
                    prefixEnd = pos
                    break
                } else {
                    entityType.append(char)
                }
            }
            previousChar = char
        }

        let rawID = String(input[input.index(prefixEnd, offsetBy: 0)...])
        let rawValues: RawValues

        do {
            rawValues = try Self.sqids.decode(rawID)
        } catch {
            throw E.ParseError
        }

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
    /// - Parameter entityKind: the external prefix — the marker `_` and exactly one non-`_`
    ///   character (for example `"_U"`).
    public init(externalUUID uuid: UUID, entityKind: String = ID.defaultExternalEntityKind) throws(E) {
        guard entityKind.count == 2,
            entityKind.first == Self.underscore,
            entityKind.last != Self.underscore
        else {
            throw E.InvalidExternalEntityKind
        }
        try self.init(rawValues: Self.pack(uuid), entityKind: entityKind)
    }

    /// The reconstructed external UUID, if this `ID` wraps one (prefix starts with `_`);
    /// otherwise `nil` (this is a regular internal identifier).
    public var externalUUID: UUID? {
        guard self.entityKind.first == Self.underscore else { return nil }
        return Self.unpack(self.rawValues)
    }

    /// Parses an external ID. The prefix zone always occupies exactly `prefixSize` characters
    /// (`entityKind` plus `_` padding), so the body starts at offset `prefixSize`.
    private static func parseExternal(input: String) throws(E) -> Self {
        guard input.count >= Self.prefixSize else { throw E.InvalidInputStringSize }
        let regionEnd = input.index(input.startIndex, offsetBy: Self.prefixSize)

        // entityKind = the prefix zone without TRAILING underscores (the leading marker is kept).
        var region = String(input[input.startIndex..<regionEnd])
        while region.last == Self.underscore { region.removeLast() }
        let entityKind = region

        let body = String(input[regionEnd...])
        let rawValues: RawValues
        do {
            rawValues = try Self.sqids.decode(body)
        } catch {
            throw E.ParseError
        }
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
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stringValue == rhs.stringValue
    }
}

extension ID: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawValues)
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
