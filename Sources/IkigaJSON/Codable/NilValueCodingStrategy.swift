/// Defines the possible strategies for choosing whether to omit or emit optional
/// encoded values that are `nil`. Note that calling any variant of `encode()`
/// with an `Optional` type is always equivalent to calling `encodeNil()` if the
/// value is `nil`.
public enum NilValueEncodingStrategy: Equatable {
    /// Follow `Encodable`'s default behavior:
    ///
    ///   - `encodeIfPresent()`: Skip encoding for `nil` inputs.
    ///   - `encodeNil()`: Output an explicitly `nil` value.
    case `default`
    
    /// Never emit `nil` encoded values into the output, even if `encodeNil()` is
    /// explicitly called. For keyed encoding containers, the value's key will also
    /// be ommitted.
    ///
    ///   - `encodeIfPresent()`: Skip encoding for `nil` inputs.
    ///   - `encodeNil()`: Do nothing.
    case neverEncodeNil
    
    /// Always emit `nil` encoded values into the output, even if `encodeIfPresent()`
    /// is used.
    ///
    /// - Note: This strategy can not prevent an `encode(to:)` implementation from
    ///   simply skipping over encode calls for `nil` values if it so desires. All
    ///   it can do is negate the silencing effect of `encodeIfPresent()`.
    ///
    ///   - `encodeIfPresent()`: Call `encodeNil()` for `nil` inputs.
    ///   - `encodeNil()`: Output an explicitly `nil` value.
    case alwaysEncodeNil
}

/// Defines the possible strategies for determining whether to treat a missing key
/// or value requested as an optional type as `nil` when decoding.
public enum NilValueDecodingStrategy: Equatable {
    /// Follow `Decodable`'s default behavior:
    ///
    ///   - `decodeNil(forKey:)`: Throw `.keyNotFound` when the key is missing.
    ///   - `decodeNil()`: Throw `.valueNotFound` when unkeyed container is at end or single-value container is empty
    ///   - `decodeIfPresent(forKey:)`: Return `nil` when the key is missing.
    ///   - `decodeIfPresent()`: Return `nil` when unkeyed container is at end or single-value container is empty.
    case `default`
    
    /// When any `decodeNil()` is called on a container, and the key or value is not there, treat it as if the key were
    /// present with `nil` value.
    ///
    ///   - `decodeNil(forKey:)`: Return `nil` when the key is missing.
    ///   - `decodeNil()`: Return `nil` when unkeyed container`.isAtEnd` or single-value container is empty.
    ///   - `decodeIfPresent(forKey:)`: Return `nil` when the key is missing.
    ///   - `decodeIfPresent()`: Return `nil` when unkeyed container is at end or single-value container is empty.
    case decodeNilForKeyNotFound
    
    /// When calling `decodeIfPresent()` or `decodeNil()`, treat a value explicitly given as `nil` as if it were never
    /// specified at all, and throw the appropriate error.

    ///   - `decodeNil(forKey:)`: Throw `.keyNotFound` if the key is missing or has a value of `nil`.
    ///   - `decodeNil()`: Throw `.valueNotFound` if an unkeyed container is at end or single-value container is empty.
    ///   - `decodeIfPresent(forKey:)`: Throw `.keyNotFound` if the key is missing or has a value of `nil`.
    ///   - `decodeIfPresent()`: Throw `valueNotFound` when unkeyed container is at end or single-value container is empty.
    case treatNilValuesAsMissing
}
