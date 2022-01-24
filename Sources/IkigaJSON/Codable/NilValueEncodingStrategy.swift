/// Defines the possible strategies for choosing whether to omit or emit optional
/// encoded values that are `nil`.
public enum NilValueEncodingStrategy: Equatable {
    /// Follow `Encodable`'s default behavior:
    ///   - Always omit if `encodeIfPresent()` was called.
    ///   - Always emit if `encodeNil()` was called.
    case `default`
    
    /// Never emit `nil` encoded values into the output, even if `encodeNil()` is
    /// explicitly called. For keyed encoding containers, the value's key will also
    /// be ommitted.
    case neverEncodeNil
    
    /// Always emit `nil` encoded values into the output, even if `encodeIfPresent()`
    /// is used.
    ///
    /// - Note: This strategy can not prevent an `encode(to:)` implementation from
    ///   simply skipping over encode calls for `nil` values if it so desires. All
    ///   it can do is negate the silencing effect of `encodeIfPresent()`.
    case alwaysEncodeNil
}
