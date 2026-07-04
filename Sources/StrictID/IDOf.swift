/// A typed wrapper over `ID` that prevents mixing identifiers of different entity types.
///
/// `IDOf<T>` is parameterized by a type `T: IDPrefixable` and, at initialization, checks that the
/// base `ID`'s prefix matches `T.IDPrefix`. This makes `IDOf<Organization>` and `IDOf<User>` distinct,
/// mutually incompatible types at compile time.
public struct IDOf<T: IDPrefixable>: Sendable {
    public enum E: Error {
        case ParseError(ID.E)
        case WrongIdPrefix
    }

    public let base: ID

    public var stringValue: String {
        self.base.stringValue
    }

    public init(base: ID) throws(E) {
        guard T.IDPrefix.rawValue == base.entityKind else {
            throw E.WrongIdPrefix
        }

        self.base = base
    }

    public static func parse(input: String) throws(E) -> Self {
        let baseId: ID

        do throws(ID.E) {
            baseId = try ID.parse(input: input)
        } catch {
            throw E.ParseError(error)
        }

        return try .init(base: baseId)
    }
}

public extension ID {
    func of<T>(_: T.Type) throws(IDOf<T>.E) -> IDOf<T> {
        try IDOf<T>(base: self)
    }
}

extension IDOf: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stringValue == rhs.stringValue
    }
}

extension IDOf: Hashable {}

extension IDOf: CustomStringConvertible {
    public var description: String {
        self.base.description
    }
}

extension IDOf: LosslessStringConvertible {
    public init?(_ description: String) {
        guard let base = ID(description) else {
            return nil
        }
        try? self.init(base: base)
    }
}

extension IDOf: Codable {
    enum CodingKeys: CodingKey {
        case value
    }

    public init(from decoder: any Decoder) throws {
        try self.init(base: ID(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try self.base.encode(to: encoder)
    }
}

extension IDOf: CustomReflectable {
    public var customMirror: Mirror {
        return self.base.customMirror
    }
}
