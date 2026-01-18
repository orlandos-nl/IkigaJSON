import Foundation
import NIOCore
import Synchronization
import _JSONCore

var isoFormatter: ISO8601DateFormatter { ISO8601DateFormatter() }
let isoDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
  return formatter
}()

#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
  struct InlineBuffer<let size: Int, Element: Sendable>: Sendable {
    private(set) var storage: InlineArray<size, Element>
    private(set) var count: Int
    var isEmpty: Bool { count == 0 }

    subscript(index: Int) -> Element {
      get {
        precondition(index >= 0 && index < size, "Index out of bounds")
        return storage[index]
      }
      set {
        precondition(index >= 0 && index < size, "Index out of bounds")
        storage[index] = newValue
      }
    }

    mutating func append(_ element: Element) {
      precondition(count < size, "Coding path is full")
      self[count] = element
      count += 1
    }

    init(repeating element: Element) {
      self.storage = .init(repeating: element)
      self.count = 0
    }
  }

  private struct StubCodingKey: CodingKey {
    var stringValue: String { preconditionFailure() }
    var intValue: Int? { preconditionFailure() }
    init() {}
    init?(stringValue: String) {
      preconditionFailure()
    }
    init?(intValue: Int) {
      preconditionFailure()
    }
  }

  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
  extension InlineBuffer where Element == any CodingKey {
    init() {
      self.storage = .init(repeating: StubCodingKey())
      self.count = 0
    }
  }
#endif

func date(from string: String) throws -> Date {
  if #available(OSX 10.12, iOS 11, *) {
    guard let date = isoFormatter.date(from: string) else {
      throw JSONDecoderError.invalidDate(string)
    }

    return date
  } else {
    guard let date = isoDateFormatter.date(from: string) else {
      throw JSONDecoderError.invalidDate(string)
    }

    return date
  }
}

/// Used by `KeyedDecodingContainer.superDecoder()` and `KeyedEncodingContainer.superEncoder()`.
internal enum SuperCodingKey: String, CodingKey { case `super` }

/// These settings can be used to alter the decoding process.
public struct JSONDecoderSettings: @unchecked Sendable {
  public init() {}

  /// This userInfo is accessible by the Decodable types that are being created
  public var userInfo = [CodingUserInfoKey: Any]()

  /// When strings are read, no extra effort is put into decoding unicode characters such as `\u00ff`
  ///
  /// `true` by default
  public var decodeUnicode = true

  /// Defines how to act when `nil` and missing keys and values are encountered during decoding.
  public var nilValueDecodingStrategy: NilValueDecodingStrategy = .default

  /// When a key is not set in the JSON Object it is regarded as `null` if the value is `true`.
  ///
  /// `true` by default
  ///
  /// - Warning: This property is deprecated. Use `nilValueDecodingStrategy` instead. This property
  ///   will return true if the strategy is `.decodeNilForKeyNotFound`, false otherwise. Setting
  ///   this property to true selects the `.decodeNilForKeyNotFound` strategy. Setting this property
  ///   to false selects the `treatNilValuesAsMissing` strategy, if and only if the property's setter
  ///   is explicitly called. In other words, if this property is never set, the strategy remains `.default`.
  @available(*, deprecated, message: "Use `nilValueDecodingStrategy` instead.")
  public var decodeMissingKeyAsNil = true

  /// Defines the method used when decoding keys
  public var keyDecodingStrategy = JSONDecoder.KeyDecodingStrategy.useDefaultKeys

  /// The method used to decode Foundation `Date` types
  public var dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.deferredToDate

  /// The method used to decode Foundation `Data` types
  public var dataDecodingStrategy = JSONDecoder.DataDecodingStrategy.base64
}

private struct LockedJSONDescription: @unchecked Sendable {
  private let description: JSONDescription
  private let lock: NSLock

  init() {
    self.description = JSONDescription()
    self.lock = NSLock()
  }

  func withDescription<T>(_ body: (JSONDescription) throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    description.reset()
    return try body(description)
  }
}

/// A JSON Decoder that aims to be largely functionally equivalent to Foundation.JSONDecoder with more for optimization.
#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
public struct IkigaJSONDecoder: Sendable {
  /// These settings can be used to alter the decoding process.
  public var settings: JSONDecoderSettings
  private let description: LockedJSONDescription

  public init(settings: JSONDecoderSettings = JSONDecoderSettings()) {
    self.settings = settings
    self.description = LockedJSONDescription()
  }

  /// Parses the Decodable type from `Data`. This is the equivalent for JSONDecoder's Decode function.
  public func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return try decode(type, from: buffer)
  }

  /// Parses the Decodable type from an `UnsafeBufferPointer<UInt8>`.
  @unsafe
  public func decode<D: Decodable>(_ type: D.Type, from buffer: UnsafeBufferPointer<UInt8>) throws
    -> D
  {
    try unsafe _decode(type, from: buffer).element
  }

  /// Parses the Decodable type from an `UnsafeBufferPointer<UInt8>`, returning both the decoded element and the number of bytes parsed.
  @unsafe
  public func _decode<D: Decodable>(_ type: D.Type, from buffer: UnsafeBufferPointer<UInt8>) throws
    -> (element: D, parsed: Int)
  {
    let bytes = unsafe Array(buffer)
    return try description.withDescription { description in
      let span = unsafe Span<UInt8>(_unsafeElements: buffer)
      var parser = JSONTokenizer(
        span: span,
        destination: description
      )
      try parser.scanValue()

      let decoder = _JSONDecoder(
        description: parser.destination.readOnlySubDescription(offset: 0),
        codingPath: .init(),
        bytes: bytes,
        settings: settings
      )
      return (try D(from: decoder), parser.currentOffset)
    }
  }

  /// Parses the Decodable type from a JSONObject.
  public func decode<D: Decodable>(_ type: D.Type, from object: JSONObject) throws -> D {
    let bytes = object.jsonBuffer.getBytes(at: 0, length: object.jsonBuffer.readableBytes) ?? []
    let decoder = _JSONDecoder(
      description: object.jsonDescription.readOnlySubDescription(offset: 0),
      codingPath: .init(),
      bytes: bytes,
      settings: settings
    )
    return try D(from: decoder)
  }

  /// Parses the Decodable type from a JSONArray.
  public func decode<D: Decodable>(_ type: D.Type, from array: JSONArray) throws -> D {
    let bytes = array.jsonBuffer.getBytes(at: 0, length: array.jsonBuffer.readableBytes) ?? []
    let decoder = _JSONDecoder(
      description: array.jsonDescription.readOnlySubDescription(offset: 0),
      codingPath: .init(),
      bytes: bytes,
      settings: settings
    )
    return try D(from: decoder)
  }

  /// Parses the Decodable type from a SwiftNIO `ByteBuffer`.
  public func decode<D: Decodable>(_ type: D.Type, from byteBuffer: ByteBuffer) throws -> D {
    let bytes = byteBuffer.getBytes(at: 0, length: byteBuffer.readableBytes) ?? []
    return try description.withDescription { description in
      unsafe bytes.withUnsafeBufferPointer { buffer in
        Result<D, any Error> {
          let span = unsafe Span<UInt8>(_unsafeElements: buffer)
          var parser = JSONTokenizer(
            span: span,
            destination: description
          )
          try parser.scanValue()

          let decoder = _JSONDecoder(
            description: parser.destination.readOnlySubDescription(offset: 0),
            codingPath: .init(),
            bytes: bytes,
            settings: settings
          )
          return try D(from: decoder)
        }
      }
    }.get()
  }

  /// Parses the Decodable type from a SwiftNIO `ByteBuffer`.
  public func decode<D: Decodable>(_ type: D.Type, from byteBuffer: inout ByteBuffer) throws -> D {
    let bytes = byteBuffer.getBytes(at: 0, length: byteBuffer.readableBytes) ?? []
    return try description.withDescription { description in
      unsafe bytes.withUnsafeBufferPointer { buffer in
        Result<D, any Error> {
          let span = unsafe Span<UInt8>(_unsafeElements: buffer)
          var parser = JSONTokenizer(
            span: span,
            destination: description
          )
          try parser.scanValue()

          let decoder = _JSONDecoder(
            description: parser.destination.readOnlySubDescription(offset: 0),
            codingPath: .init(),
            bytes: bytes,
            settings: settings
          )
          return try D(from: decoder)
        }
      }
    }.get()
  }

  /// Parses the Decodable type from `[UInt8]`. This is the equivalent for JSONDecoder's Decode function.
  public func decode<D: Decodable, S: Sequence>(_: D.Type, from bytes: S) throws -> D
  where S.Element == UInt8 {
    return try self.decode(D.self, from: Data(bytes))
  }

  /// Parses the Decodable type from a String. This is the equivalent for JSONDecoder's Decode function.
  public func decode<D: Decodable, S: StringProtocol>(_: D.Type, from string: S) throws -> D {
    return try self.decode(D.self, from: Data(string.utf8))
  }

  public func parse<D: Decodable>(
    _ type: D.Type,
    from buffer: inout ByteBuffer,
    settings: JSONDecoderSettings = JSONDecoderSettings()
  ) throws -> D {
    let bytes = buffer.getBytes(at: 0, length: buffer.readableBytes) ?? []
    return try description.withDescription { description in
      unsafe bytes.withUnsafeBufferPointer { bufferPointer in
        Result<D, any Error> {
          let span = unsafe Span<UInt8>(_unsafeElements: bufferPointer)
          var parser = JSONTokenizer(
            span: span,
            destination: description
          )
          try parser.scanValue()

          let decoder = _JSONDecoder(
            description: parser.destination.readOnlySubDescription(offset: 0),
            codingPath: .init(),
            bytes: bytes,
            settings: settings
          )
          return try D(from: decoder)
        }
      }
    }.get()
  }
}

#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
private final class _JSONDecoder: Decoder {
  let description: JSONDescriptionView
  let bytes: [UInt8]
  let settings: JSONDecoderSettings
  var snakeCasing: Bool

  /// Incrementally built key cache using byte positions (avoids String allocation).
  /// Stores (keyStart, keyLength, valueOffset, usesEscaping) for direct byte comparison.
  private var _keyOffsetCache: [(keyStart: Int, keyLength: Int, valueOffset: Int, usesEscaping: Bool)] = []
  /// Next index offset to scan from (0 means uninitialized, use firstChildOffset)
  private var _cacheNextOffset: Int = 0
  /// Number of keys remaining to scan (negative means uninitialized)
  private var _cacheRemainingKeys: Int = -1
  /// Last cache index where we found a key (optimization for sequential access)
  private var _lastCacheHitIndex: Int = 0

  /// Compare key bytes directly without String allocation
  @inline(__always)
  private func keyMatches(_ entry: (keyStart: Int, keyLength: Int, valueOffset: Int, usesEscaping: Bool), key: String) -> Bool {
    // For escaped strings or snake_case conversion, we need special handling
    if entry.usesEscaping || snakeCasing {
      // Fall back to String comparison for complex cases
      let keyBytes = Array(bytes[entry.keyStart..<(entry.keyStart + entry.keyLength)])
      let jsonKey: String?
      if entry.usesEscaping {
        jsonKey = description.processEscapedString(keyBytes, convertingSnakeCasing: snakeCasing)
      } else {
        var mutableBytes = keyBytes
        description.removeSnakeCasing(from: &mutableBytes)
        jsonKey = String(bytes: mutableBytes, encoding: .utf8)
      }
      return jsonKey == key
    }

    // Fast path: direct byte comparison using slice elementsEqual
    let keyUTF8 = key.utf8
    guard keyUTF8.count == entry.keyLength else { return false }
    return bytes[entry.keyStart..<(entry.keyStart + entry.keyLength)].elementsEqual(keyUTF8)
  }

  @usableFromInline
  func cachedValueOffset(forKey key: String) -> Int? {
    // Check cache starting from last hit position (Codable often accesses keys in order)
    let cacheCount = _keyOffsetCache.count
    if cacheCount > 0 {
      // Search from last hit to end
      for i in _lastCacheHitIndex..<cacheCount {
        if keyMatches(_keyOffsetCache[i], key: key) {
          _lastCacheHitIndex = i
          return _keyOffsetCache[i].valueOffset
        }
      }
      // Search from start to last hit
      for i in 0..<_lastCacheHitIndex {
        if keyMatches(_keyOffsetCache[i], key: key) {
          _lastCacheHitIndex = i
          return _keyOffsetCache[i].valueOffset
        }
      }
    }

    // If we've scanned everything, key doesn't exist
    if _cacheRemainingKeys == 0 {
      return nil
    }

    // Initialize on first access
    if _cacheRemainingKeys < 0 {
      guard description.topLevelType == .object else { return nil }
      _cacheRemainingKeys = description.arrayObjectCount()
      _cacheNextOffset = Constants.firstArrayObjectChildOffset
      // Static reserve of 8 - covers most JSON objects without over-allocating
      _keyOffsetCache.reserveCapacity(8)
    }

    // Continue scanning from where we left off
    while _cacheRemainingKeys > 0 {
      let bounds = description.dataBounds(atIndexOffset: _cacheNextOffset)
      let keyStart = Int(bounds.offset)
      let keyLength = Int(bounds.length)
      let usesEscaping = description.type(atOffset: _cacheNextOffset) == .stringWithEscaping

      // Skip the key index to get value offset
      description.skipIndex(atOffset: &_cacheNextOffset)
      let valueOffset = _cacheNextOffset

      // Skip the value index for next iteration
      description.skipIndex(atOffset: &_cacheNextOffset)
      _cacheRemainingKeys -= 1

      // Add to cache (just positions, no String allocation)
      let entry = (keyStart: keyStart, keyLength: keyLength, valueOffset: valueOffset, usesEscaping: usesEscaping)
      _keyOffsetCache.append(entry)

      // Check if this is the key we're looking for
      if keyMatches(entry, key: key) {
        return valueOffset
      }
    }

    return nil
  }

  #if swift(>=6.2.1) && Spans
    typealias CodingPath = InlineBuffer<32, any CodingKey>
    var _codingPath: CodingPath
    var codingPath: [any CodingKey] {
      var array = [any CodingKey]()
      array.reserveCapacity(CodingPath.size)
      for index in 0..<32 {
        array.append(_codingPath[index])
      }
      return array
    }
  #else
    typealias CodingPath = [any CodingKey]
    var _codingPath: [any CodingKey]

    @usableFromInline
    var codingPath: [any CodingKey] {
      return _codingPath
    }
  #endif

  var userInfo: [CodingUserInfoKey: Any] {
    return settings.userInfo
  }

  func string<Key: CodingKey>(forKey key: Key) -> String {
    if case .custom(let builder) = settings.keyDecodingStrategy {
      return builder(codingPath + [key]).stringValue
    } else {
      return key.stringValue
    }
  }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
  where Key: CodingKey {
    guard description.topLevelType == .object else {
      throw JSONDecoderError.missingKeyedContainer
    }

    let container = KeyedJSONDecodingContainer<Key>(decoder: self)
    return KeyedDecodingContainer(container)
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    guard description.topLevelType == .array else {
      throw JSONDecoderError.missingUnkeyedContainer
    }

    return UnkeyedJSONDecodingContainer(decoder: self)
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    return SingleValueJSONDecodingContainer(decoder: self)
  }

  init(
    description: JSONDescriptionView, codingPath: CodingPath, bytes: [UInt8],
    settings: JSONDecoderSettings
  ) {
    self.description = description
    self.bytes = bytes
    self._codingPath = codingPath
    self.settings = settings

    if case .convertFromSnakeCase = settings.keyDecodingStrategy {
      self.snakeCasing = true
    } else {
      self.snakeCasing = false
    }
  }

  func subDecoder(offsetBy offset: Int) -> _JSONDecoder {
    let subDescription = self.description.readOnlySubDescription(offset: offset)
    return _JSONDecoder(
      description: subDescription, codingPath: _codingPath, bytes: bytes, settings: settings)
  }

  func decode<D: Decodable>(_ type: D.Type) throws -> D {
    switch type {
    case is Date.Type:
      switch self.settings.dateDecodingStrategy {
      case .deferredToDate:
        break
      case .secondsSince1970:
        let interval = try singleValueContainer().decode(Double.self)
        return Date(timeIntervalSince1970: interval) as! D
      case .millisecondsSince1970:
        let interval = try singleValueContainer().decode(Double.self)
        return Date(timeIntervalSince1970: interval / 1000) as! D
      case .iso8601:
        let string = try singleValueContainer().decode(String.self)

        return try date(from: string) as! D
      #if !canImport(FoundationEssentials) || swift(<5.10)
        case .formatted(let formatter):
          let string = try singleValueContainer().decode(String.self)

          guard let date = formatter.date(from: string) else {
            throw JSONDecoderError.invalidDate(string)
          }

          return date as! D
      #endif
      case .custom(let makeDate):
        return try makeDate(self) as! D
      @unknown default:
        throw JSONDecoderError.unknownJSONStrategy
      }
    case is Data.Type:
      switch self.settings.dataDecodingStrategy {
      case .deferredToData:
        break
      case .base64:
        let string = try singleValueContainer().decode(String.self)

        guard let data = Data(base64Encoded: string) else {
          throw JSONDecoderError.invalidData(string)
        }

        return data as! D
      case .custom(let makeData):
        return try makeData(self) as! D
      @unknown default:
        throw JSONDecoderError.unknownJSONStrategy
      }
    case is URL.Type:
      let string = try singleValueContainer().decode(String.self)

      guard let url = URL(string: string) else {
        throw JSONDecoderError.invalidURL(string)
      }

      return url as! D
    case is Decimal.Type:
      let double = try singleValueContainer().decode(Double.self)
      return Decimal(floatLiteral: double) as! D
    default:
      break
    }

    return try D.init(from: self)
  }
}

#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
private struct KeyedJSONDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  var codingPath: [CodingKey] { decoder.codingPath }
  var allKeys: [Key] { allStringKeys.compactMap(Key.init) }
  let decoder: _JSONDecoder

  private var allStringKeys: [String] {
    return decoder.description.keys(
      in: decoder.bytes,
      unicode: decoder.settings.decodeUnicode,
      convertingSnakeCasing: self.decoder.snakeCasing
    )
  }

  private func floatingBounds(forKey key: Key) -> JSONToken.Number? {
    guard let offset = decoder.cachedValueOffset(forKey: decoder.string(forKey: key)) else {
      return nil
    }
    return decoder.description.floatingBounds(atOffset: offset, in: decoder.bytes)
  }

  private func integerBounds(forKey key: Key) -> JSONToken.Number? {
    guard let offset = decoder.cachedValueOffset(forKey: decoder.string(forKey: key)) else {
      return nil
    }
    return decoder.description.integerBounds(atOffset: offset, in: decoder.bytes)
  }

  func contains(_ key: Key) -> Bool {
    return decoder.cachedValueOffset(forKey: decoder.string(forKey: key)) != nil
  }

  private func typeForKey(_ key: Key) -> JSONType? {
    guard let offset = decoder.cachedValueOffset(forKey: decoder.string(forKey: key)) else {
      return nil
    }
    return decoder.description.type(atOffset: offset)
  }

  func decodeNil(forKey key: Key) throws -> Bool {
    let type = typeForKey(key)
    switch (decoder.settings.nilValueDecodingStrategy, type) {
    case (.default, .none), (.treatNilValuesAsMissing, .none),
      (.treatNilValuesAsMissing, .some(.null)):
      throw JSONDecoderError.decodingError(expected: Void?.self, keyPath: codingPath + [key])
    case (.decodeNilForKeyNotFound, .none), (_, .some(.null)): return true
    default: return false
    }
  }

  func decodeIfPresentNil(forKey key: Key) throws -> Bool {
    let type = typeForKey(key)
    switch (decoder.settings.nilValueDecodingStrategy, type) {
    case (.treatNilValuesAsMissing, .none), (.treatNilValuesAsMissing, .some(.null)):
      throw JSONDecoderError.decodingError(expected: Void?.self, keyPath: codingPath + [key])
    case (.default, .none), (.decodeNilForKeyNotFound, .none), (_, .some(.null)): return true
    default: return false
    }
  }

  func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }
  func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T: Decodable {
    return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key)
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    switch typeForKey(key) {
    case .some(.boolTrue): return true
    case .some(.boolFalse): return false
    default: throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath + [key])
    }
  }

  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    guard
      let offset = decoder.cachedValueOffset(forKey: decoder.string(forKey: key)),
      let bounds = decoder.description.stringBounds(atOffset: offset, in: decoder.bytes)
    else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath + [key])
    }

    guard
      let string = bounds.makeString(
        from: decoder.bytes,
        unicode: decoder.settings.decodeUnicode
      )
    else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath + [key])
    }

    return string
  }

  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    return try Float(self.decode(Double.self, forKey: key))
  }
  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    guard let bounds = floatingBounds(forKey: key) else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath + [key])
    }

    return bounds.makeDouble(from: decoder.bytes)
  }

  func decodeInt<F: FixedWidthInteger & Sendable>(_ type: F.Type, forKey key: Key) throws -> F {
    guard
      let result = try integerBounds(forKey: key)?.makeInt(from: decoder.bytes)?.convert(
        to: F.self)
    else {
      throw JSONDecoderError.decodingError(expected: F.self, keyPath: codingPath)
    }
    return result
  }
  func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
    return try decodeInt(type, forKey: key)
  }
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
    return try decodeInt(type, forKey: key)
  }

  private func subDecoder<NestedKey: CodingKey>(
    forKey key: NestedKey, orThrow failureError: Error, appendingToPath: Bool = true
  ) throws -> _JSONDecoder {
    let keyString = self.decoder.string(forKey: key)
    guard let offset = self.decoder.cachedValueOffset(forKey: keyString) else {
      throw failureError
    }
    let subDecoder = self.decoder.subDecoder(offsetBy: offset)
    subDecoder._codingPath.append(key)
    return subDecoder
  }

  func decode<T>(_: T.Type, forKey key: Key) throws -> T where T: Decodable {
    return try self.subDecoder(
      forKey: key,
      orThrow: JSONDecoderError.decodingError(expected: T.self, keyPath: self.codingPath),
      appendingToPath: false
    ).decode(T.self)
  }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
    -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
  {
    return try self.subDecoder(forKey: key, orThrow: JSONDecoderError.missingKeyedContainer)
      .container(keyedBy: NestedKey.self)
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
    return try self.subDecoder(forKey: key, orThrow: JSONDecoderError.missingUnkeyedContainer)
      .unkeyedContainer()
  }

  func superDecoder() throws -> Decoder {
    return try self.subDecoder(
      forKey: SuperCodingKey.super, orThrow: JSONDecoderError.missingSuperDecoder)
  }

  func superDecoder(forKey key: Key) throws -> Decoder {
    return try self.subDecoder(forKey: key, orThrow: JSONDecoderError.missingSuperDecoder)
  }
}

#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
private struct UnkeyedJSONDecodingContainer: UnkeyedDecodingContainer {
  let decoder: _JSONDecoder
  private var offset = 17  // Array descriptions are 17 bytes

  var codingPath: [CodingKey] { decoder.codingPath }
  var currentIndex = 0
  var count: Int? {
    decoder.description.arrayObjectCount()
  }
  var isAtEnd: Bool { currentIndex >= (count ?? 0) }

  init(decoder: _JSONDecoder) {
    self.decoder = decoder
  }

  mutating func decodeNil() throws -> Bool {
    if isAtEnd, decoder.settings.nilValueDecodingStrategy == .decodeNilForKeyNotFound {
      return true
    }
    try assertHasMore()
    guard decoder.description.type(atOffset: offset) == .null else { return false }

    if decoder.settings.nilValueDecodingStrategy == .treatNilValuesAsMissing {
      throw JSONDecoderError.decodingError(expected: Void?.self, keyPath: codingPath)
    }
    skipValue()
    return true
  }

  mutating func skipValue() {
    decoder.description.skipIndex(atOffset: &offset)
    currentIndex = currentIndex &+ 1
  }

  func assertHasMore() throws {
    guard !isAtEnd else {
      throw JSONDecoderError.endOfArray
    }
  }

  mutating func decodeIfPresent(_ type: Bool.Type) throws -> Bool? {
    return try self.decodeNil() ? nil : self.decode(Bool.self)
  }
  mutating func decodeIfPresent(_ type: String.Type) throws -> String? {
    return try self.decodeNil() ? nil : self.decode(String.self)
  }
  mutating func decodeIfPresent(_ type: Float.Type) throws -> Float? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: Double.Type) throws -> Double? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: Int.Type) throws -> Int? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: Int8.Type) throws -> Int8? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: Int16.Type) throws -> Int16? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: Int32.Type) throws -> Int32? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: Int64.Type) throws -> Int64? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: UInt.Type) throws -> UInt? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? {
    return try self.decodeNil() ? nil : self.decode(type)
  }
  mutating func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T: Decodable {
    return try self.decodeNil() ? nil : self.decode(type)
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool {
    try assertHasMore()
    let type = decoder.description.type(atOffset: offset)
    skipValue()

    switch type {
    case .boolTrue: return true
    case .boolFalse: return false
    default: throw JSONDecoderError.decodingError(expected: Bool.self, keyPath: codingPath)
    }
  }

  mutating func floatingBounds() -> JSONToken.Number? {
    if isAtEnd { return nil }
    let type = decoder.description.type(atOffset: offset)
    guard type == .integer || type == .floatingNumber else { return nil }
    let bounds = decoder.description.dataBounds(atIndexOffset: offset)
    skipValue()
    return JSONToken.Number(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      isInteger: type == .integer
    )
  }

  mutating func integerBounds() -> JSONToken.Number? {
    if isAtEnd { return nil }
    let type = decoder.description.type(atOffset: offset)
    guard type == .integer else { return nil }
    let bounds = decoder.description.dataBounds(atIndexOffset: offset)
    skipValue()
    return JSONToken.Number(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      isInteger: true
    )
  }

  mutating func decode(_ type: String.Type) throws -> String {
    try assertHasMore()
    let type = decoder.description.type(atOffset: offset)

    if type != .string && type != .stringWithEscaping {
      throw JSONDecoderError.decodingError(expected: String.self, keyPath: codingPath)
    }

    let bounds = decoder.description.dataBounds(atIndexOffset: offset)
    let token = JSONToken.String(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      usesEscaping: type == .stringWithEscaping
    )

    guard
      let string = token.makeString(
        from: decoder.bytes,
        unicode: decoder.settings.decodeUnicode
      )
    else {
      throw JSONDecoderError.decodingError(expected: String.self, keyPath: codingPath)
    }

    skipValue()
    return string
  }

  mutating func decode(_ type: Double.Type) throws -> Double {
    guard let bounds = floatingBounds() else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }

    return bounds.makeDouble(from: decoder.bytes)
  }

  mutating func decode(_ type: Float.Type) throws -> Float {
    return Float(try self.decode(Double.self))
  }

  mutating func decodeInt<F: FixedWidthInteger & Sendable>(_ type: F.Type) throws -> F {
    guard
      let bounds = integerBounds(),
      let int = bounds.makeInt(from: decoder.bytes)
    else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }

    return try int.convert(to: F.self)
  }

  mutating func decode(_ type: Int.Type) throws -> Int { return try decodeInt(type) }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { return try decodeInt(type) }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { return try decodeInt(type) }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { return try decodeInt(type) }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { return try decodeInt(type) }
  mutating func decode(_ type: UInt.Type) throws -> UInt { return try decodeInt(type) }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { return try decodeInt(type) }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { return try decodeInt(type) }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { return try decodeInt(type) }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { return try decodeInt(type) }
  mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
    let decoder = self.decoder.subDecoder(offsetBy: offset)
    skipValue()
    return try decoder.decode(type)
  }

  mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
    -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
  {
    let decoder = self.decoder.subDecoder(offsetBy: offset)
    skipValue()
    return try decoder.container(keyedBy: NestedKey.self)
  }

  mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
    let decoder = self.decoder.subDecoder(offsetBy: offset)
    skipValue()
    return try decoder.unkeyedContainer()
  }

  mutating func superDecoder() throws -> Decoder {
    let decoder = self.decoder.subDecoder(offsetBy: offset)
    skipValue()
    return decoder
  }
}

#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
private struct SingleValueJSONDecodingContainer: SingleValueDecodingContainer {
  var codingPath: [CodingKey] { decoder.codingPath }
  let decoder: _JSONDecoder

  func decodeNil() -> Bool { return decoder.description.topLevelType == .null }

  func floatingBounds() -> JSONToken.Number? {
    let type = decoder.description.topLevelType
    guard type == .integer || type == .floatingNumber else { return nil }
    let bounds = decoder.description.dataBounds(atIndexOffset: 0)
    return JSONToken.Number(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      isInteger: type == .integer
    )
  }

  func integerBounds() -> JSONToken.Number? {
    guard decoder.description.topLevelType == .integer else { return nil }
    let bounds = decoder.description.dataBounds(atIndexOffset: 0)
    return JSONToken.Number(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      isInteger: true
    )
  }

  func decode(_ type: Bool.Type) throws -> Bool {
    switch decoder.description.topLevelType {
    case .boolTrue: return true
    case .boolFalse: return false
    default: throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }
  }

  func decode(_ type: String.Type) throws -> String {
    let jsonType = decoder.description.topLevelType
    guard jsonType == .string || jsonType == .stringWithEscaping else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }
    let bounds = decoder.description.dataBounds(atIndexOffset: 0)
    let token = JSONToken.String(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      usesEscaping: jsonType == .stringWithEscaping
    )
    guard
      let string = token.makeString(
        from: decoder.bytes,
        unicode: decoder.settings.decodeUnicode
      )
    else {
      throw JSONDecoderError.decodingError(expected: String.self, keyPath: codingPath)
    }
    return string
  }

  func decode(_ type: Double.Type) throws -> Double {
    guard let token = floatingBounds() else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }

    return token.makeDouble(from: decoder.bytes)
  }

  func decode(_ type: Float.Type) throws -> Float { return try Float(decode(Double.self)) }

  func decodeInt<F: FixedWidthInteger & Sendable>(ofType type: F.Type) throws -> F {
    let jsonType = decoder.description.topLevelType
    guard jsonType == .integer else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }
    let bounds = decoder.description.dataBounds(atIndexOffset: 0)
    let token = JSONToken.Number(
      start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
      byteLength: Int(bounds.length),
      isInteger: true
    )
    guard let int = token.makeInt(from: self.decoder.bytes) else {
      throw JSONDecoderError.decodingError(expected: type, keyPath: codingPath)
    }
    return try int.convert(to: type)
  }

  func decode(_ type: Int.Type) throws -> Int { return try decodeInt(ofType: type) }
  func decode(_ type: Int8.Type) throws -> Int8 { return try decodeInt(ofType: type) }
  func decode(_ type: Int16.Type) throws -> Int16 { return try decodeInt(ofType: type) }
  func decode(_ type: Int32.Type) throws -> Int32 { return try decodeInt(ofType: type) }
  func decode(_ type: Int64.Type) throws -> Int64 { return try decodeInt(ofType: type) }
  func decode(_ type: UInt.Type) throws -> UInt { return try decodeInt(ofType: type) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { return try decodeInt(ofType: type) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { return try decodeInt(ofType: type) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { return try decodeInt(ofType: type) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { return try decodeInt(ofType: type) }
  func decode<T>(_ type: T.Type) throws -> T where T: Decodable { return try decoder.decode(type) }
}

extension FixedWidthInteger where Self: Sendable {
  /// Converts the current FixedWidthInteger to another FixedWithInteger type `I`
  ///
  /// Throws a `TypeConversionError` if the range of `I` does not contain `self`
  internal func convert<I: FixedWidthInteger & Sendable>(
    to int: I.Type
  ) throws(TypeConversionError<Self>) -> I {
    // If I is smaller in width we need to see if the current integer fits inside of I
    if I.bitWidth < Self.bitWidth {
      if numericCast(I.max) < self {
        throw TypeConversionError(from: self, to: I.self)
      } else if numericCast(I.min) > self {
        throw TypeConversionError(from: self, to: I.self)
      }
    } else if !I.isSigned {
      // BSON doesn't store unsigned ints and unsigned ints can't be negative
      guard self >= 0 else {
        throw TypeConversionError(from: self, to: I.self)
      }
    }

    return numericCast(self)
  }
}
