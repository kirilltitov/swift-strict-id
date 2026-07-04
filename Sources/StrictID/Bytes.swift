@usableFromInline
typealias Byte = UInt8

@usableFromInline
typealias Bytes = [Byte]

/// The UTF-8 bytes of a string. Used to compute `bytesSum`, the middle element of `rawValues`.
@inlinable
func getBytes(_ string: String) -> Bytes {
    Bytes(string.utf8)
}
