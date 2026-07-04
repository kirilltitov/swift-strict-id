/// Protocol that must be implemented by any type used as the `IDOf<T>` parameter.
///
/// `associatedtype IDPrefixEnum` is a deliberate compile-time guarantee: each entity is tied to a
/// case of its own prefix enum (`RawValue == String`), not to a "bare" string. This forces adding
/// a new entity to cascade through the entire type chain. Do not simplify this to
/// `static var idPrefix: String`.
public protocol IDPrefixable {
    associatedtype IDPrefixEnum: RawRepresentable where IDPrefixEnum.RawValue == String

    static var IDPrefix: IDPrefixEnum { get }
}
