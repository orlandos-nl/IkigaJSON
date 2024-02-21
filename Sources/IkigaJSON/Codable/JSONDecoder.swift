import Foundation
import NIOConcurrencyHelpers
import NIO

enum JSONDecoderError: Error {
    case invalidURL(String)
    case invalidDecimal(String)
}

@available(OSX 10.12, iOS 10, *)
let isoFormatter = ISO8601DateFormatter()
let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter
}()
    
func date(from string: String) throws -> Date {
    if #available(OSX 10.12, iOS 11, *) {
        guard let date = isoFormatter.date(from: string) else {
            throw JSONParserError.invalidDate(string)
        }
        
        return date
    } else {
        guard let date = isoDateFormatter.date(from: string) else {
            throw JSONParserError.invalidDate(string)
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
    public var userInfo = [CodingUserInfoKey : Any]()
    
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

/// A JSON Decoder that aims to be largely functionally equivalent to Foundation.JSONDecoder with more for optimization.
public final class IkigaJSONDecoder: Sendable {
    private let settingsBox: NIOLockedValueBox<JSONDecoderSettings>
    
    /// These settings can be used to alter the decoding process.
    public var settings: JSONDecoderSettings {
        get { settingsBox.withLockedValue { $0 } }
        set { settingsBox.withLockedValue { $0 = newValue } }
    }
    
    public init(settings: JSONDecoderSettings = JSONDecoderSettings()) {
        self.settingsBox = .init(settings)
    }
    
    /// Parses the Decodable type from an UnsafeBufferPointer.
    /// This API can be used when the data wasn't originally available as `Data` so you remove the need for copying data.
    /// This can save a lot of performance.
    public func decode<D: Decodable>(_ type: D.Type, from buffer: UnsafeBufferPointer<UInt8>) throws -> D {
        let pointer = buffer.baseAddress!
        var parser = JSONParser(pointer: pointer, count: buffer.count)
        try parser.scanValue()
        
        let decoder = _JSONDecoder(description: parser.description, codingPath: [], pointer: pointer, settings: settings)
        let type = try D(from: decoder)
        return type
    }
    
    /// Parses the Decodable type from `Data`. This is the equivalent for JSONDecoder's Decode function.
    public func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D {
        return try data.withUnsafeBytes { buffer in
            return try decode(type, from: buffer.bindMemory(to: UInt8.self))
        }
    }
    
    /// Parses the Decodable type from a JSONObject.
    public func decode<D: Decodable>(_ type: D.Type, from object: JSONObject) throws -> D {
        return try object.jsonBuffer.withUnsafeReadableBytes { buffer in
            let decoder = _JSONDecoder(
                description: object.description,
                codingPath: [],
                pointer: buffer.baseAddress!.bindMemory(to: UInt8.self, capacity: buffer.count),
                settings: settings
            )
            
            return try D(from: decoder)
        }
    }
    
    /// Parses the Decodable type from a JSONArray.
    public func decode<D: Decodable>(_ type: D.Type, from array: JSONArray) throws -> D {
        return try array.jsonBuffer.withUnsafeReadableBytes { buffer in
            let decoder = _JSONDecoder(
                description: array.description,
                codingPath: [],
                pointer: buffer.baseAddress!.bindMemory(to: UInt8.self, capacity: buffer.count),
                settings: settings
            )
            
            return try D(from: decoder)
        }
    }
    
    /// Parses the Decodable type from a SwiftNIO `ByteBuffer`.
    public func decode<D: Decodable>(_ type: D.Type, from byteBuffer: ByteBuffer) throws -> D {
        return try byteBuffer.withUnsafeReadableBytes { buffer in
            return try self.decode(type, from: buffer.bindMemory(to: UInt8.self))
        }
    }
    
    /// Parses the Decodable type from `[UInt8]`. This is the equivalent for JSONDecoder's Decode function.
    public func decode<D: Decodable, S: Sequence>(_: D.Type, from bytes: S) throws -> D where S.Element == UInt8 {
        // N.B.: As of Swift 5.3, everything String-related and almost every sequence and collection type (other than transforms like LazySequence) provides contiguous storage. This is currently the most efficient known way of getting UTF-8 bytes from a non-bridged String.
        let model = try bytes.withContiguousStorageIfAvailable {
            try self.decode(D.self, from: $0)
        }
        
        if let model = model {
            return model
        } else {
            return try self.decode(D.self, from: Data(bytes))
        }
    }
    
    /// Parses the Decodable type from `[UInt8]`. This is the equivalent for JSONDecoder's Decode function.
    public func decode<D: Decodable, S: StringProtocol>(_: D.Type, from string: S) throws -> D {
        // `.withUTF8()` is mutating, so can't use it here, use UTF8View to go through the Sequence overload
        return try self.decode(D.self, from: string.utf8)
    }
    
    public func parse<D: Decodable>(
        _ type: D.Type,
        from buffer: inout ByteBuffer,
        settings: JSONDecoderSettings = JSONDecoderSettings()
    ) throws -> D {
        return try buffer.readWithUnsafeMutableReadableBytes { buffer -> (Int, D) in
            let buffer = buffer.bindMemory(to: UInt8.self)
            let pointer = buffer.baseAddress!
            var parser = JSONParser(pointer: pointer, count: buffer.count)
            try parser.scanValue()
            
            let decoder = _JSONDecoder(description: parser.description, codingPath: [], pointer: pointer, settings: settings)
            let type = try D(from: decoder)
            return (parser.currentOffset, type)
        }
    }
    
    internal func decode<D: Decodable>(
        _ type: D.Type,
        from buffer: UnsafeBufferPointer<UInt8>,
        parser: JSONParser,
        settings: JSONDecoderSettings = JSONDecoderSettings()
    ) throws -> D {
        let decoder = _JSONDecoder(description: parser.description, codingPath: [], pointer: buffer.baseAddress!, settings: settings)
        return try D(from: decoder)
    }
}

fileprivate struct _JSONDecoder: Decoder {
    let description: JSONDescription
    let pointer: UnsafePointer<UInt8>
    let settings: JSONDecoderSettings
    var snakeCasing: Bool
    
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey : Any] {
        return settings.userInfo
    }
    
    func string<Key: CodingKey>(forKey key: Key) -> String {
        if case .custom(let builder) = settings.keyDecodingStrategy {
            return builder(codingPath + [key]).stringValue
        } else {
            return key.stringValue
        }
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        guard description.topLevelType == .object else {
            throw JSONParserError.missingKeyedContainer
        }
        
        let container = KeyedJSONDecodingContainer<Key>(decoder: self)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard description.topLevelType == .array else {
            throw JSONParserError.missingUnkeyedContainer
        }
        
        return UnkeyedJSONDecodingContainer(decoder: self)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SingleValueJSONDecodingContainer(decoder: self)
    }
    
    init(description: JSONDescription, codingPath: [CodingKey], pointer: UnsafePointer<UInt8>, settings: JSONDecoderSettings) {
        self.description = description
        self.pointer = pointer
        self.codingPath = codingPath
        self.settings = settings
        
        if case .convertFromSnakeCase = settings.keyDecodingStrategy {
            self.snakeCasing = true
        } else {
            self.snakeCasing = false
        }
    }
    
    func subDecoder(offsetBy offset: Int) -> _JSONDecoder {
        let subDescription = self.description.subDescription(offset: offset)
        return _JSONDecoder(description: subDescription, codingPath: codingPath, pointer: pointer, settings: settings)
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
            case .formatted(let formatter):
                let string = try singleValueContainer().decode(String.self)
                
                guard let date = formatter.date(from: string) else {
                    throw JSONParserError.invalidDate(string)
                }
                
                return date as! D
            case .custom(let makeDate):
                return try makeDate(self) as! D
            @unknown default:
                throw JSONParserError.unknownJSONStrategy
            }
        case is Data.Type:
            switch self.settings.dataDecodingStrategy {
            case .deferredToData:
                break
            case .base64:
                let string = try singleValueContainer().decode(String.self)
                
                guard let data = Data(base64Encoded: string) else {
                    throw JSONParserError.invalidData(string)
                }
                
                return data as! D
            case .custom(let makeData):
                return try makeData(self) as! D
            @unknown default:
                throw JSONParserError.unknownJSONStrategy
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

fileprivate struct KeyedJSONDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] { decoder.codingPath }
    var allKeys: [Key] { allStringKeys.compactMap(Key.init) }
    let decoder: _JSONDecoder
    
    private var allStringKeys: [String] {
        return decoder.description.keys(
            inPointer: decoder.pointer,
            unicode: decoder.settings.decodeUnicode,
            convertingSnakeCasing: self.decoder.snakeCasing
        )
    }
    
    private func floatingBounds(forKey key: Key) -> (Bounds, Bool)? {
        return decoder.description.floatingBounds(
            forKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        )
    }
    
    private func integerBounds(forKey key: Key) -> Bounds? {
        return decoder.description.integerBounds(
            forKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        )
    }
    
    func contains(_ key: Key) -> Bool {
        return decoder.description.containsKey(
            decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            inPointer: decoder.pointer,
            unicode: decoder.settings.decodeUnicode
        )
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        switch (
            decoder.settings.nilValueDecodingStrategy,
            decoder.description.type(
                ofKey: decoder.string(forKey: key),
                convertingSnakeCasing: self.decoder.snakeCasing,
                in: decoder.pointer
            )
        ) {
            case (.default, .none), (.treatNilValuesAsMissing, .none), (.treatNilValuesAsMissing, .some(.null)):
                throw JSONParserError.decodingError(expected: Void?.self, keyPath: codingPath + [key])
            case (.decodeNilForKeyNotFound, .none), (_, .some(.null)): return true
            default: return false
        }
    }
    
    func decodeIfPresentNil(forKey key: Key) throws -> Bool {
        switch (
            decoder.settings.nilValueDecodingStrategy,
            decoder.description.type(
                ofKey: decoder.string(forKey: key),
                convertingSnakeCasing: self.decoder.snakeCasing,
                in: decoder.pointer
            )
        ) {
        case (.treatNilValuesAsMissing, .none), (.treatNilValuesAsMissing, .some(.null)):
            throw JSONParserError.decodingError(expected: Void?.self, keyPath: codingPath + [key])
        case (.default, .none), (.decodeNilForKeyNotFound, .none), (_, .some(.null)): return true
        default: return false
        }
    }
    
    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool?     { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float?   { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int?       { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8?     { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16?   { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32?   { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64?   { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt?     { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8?   { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T : Decodable { return try self.decodeIfPresentNil(forKey: key) ? nil : self.decode(type, forKey: key) }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        switch decoder.description.type(
            ofKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        ) {
        case .some(.boolTrue): return true
        case .some(.boolFalse): return false
        default: throw JSONParserError.decodingError(expected: type, keyPath: codingPath + [key])
        }
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        guard let (bounds, escaped) = decoder.description.stringBounds(
            forKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        ) else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: escaped,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        return string
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { return try Float(self.decode(Double.self, forKey: key)) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        guard let (bounds, floating) = floatingBounds(forKey: key) else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        return bounds.makeDouble(from: decoder.pointer, floating: floating)
    }
        
    func decodeInt<F: FixedWidthInteger>(_ type: F.Type, forKey key: Key) throws -> F {
        guard let result = try integerBounds(forKey: key)?.makeInt(from: decoder.pointer)?.convert(to: F.self) else {
            throw JSONParserError.decodingError(expected: F.self, keyPath: codingPath)
        }
        return result
    }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { return try decodeInt(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { return try decodeInt(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { return try decodeInt(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { return try decodeInt(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { return try decodeInt(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { return try decodeInt(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { return try decodeInt(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { return try decodeInt(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { return try decodeInt(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { return try decodeInt(type, forKey: key) }
    
    private func subDecoder<NestedKey: CodingKey>(forKey key: NestedKey, orThrow failureError: Error, appendingToPath: Bool = true) throws -> _JSONDecoder {
        guard let (_, offset) = self.decoder.description.valueOffset(
            forKey: self.decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: self.decoder.pointer
        ) else {
            throw failureError
        }
        var subDecoder = self.decoder.subDecoder(offsetBy: offset)
        subDecoder.codingPath.append(key)
        return subDecoder
    }
    
    func decode<T>(_: T.Type, forKey key: Key) throws -> T where T : Decodable {
        return try self.subDecoder(
            forKey: key,
            orThrow: JSONParserError.decodingError(expected: T.self, keyPath: self.codingPath),
            appendingToPath: false
        ).decode(T.self)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try self.subDecoder(forKey: key, orThrow: JSONParserError.missingKeyedContainer).container(keyedBy: NestedKey.self)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return try self.subDecoder(forKey: key, orThrow: JSONParserError.missingUnkeyedContainer).unkeyedContainer()
    }
    
    func superDecoder() throws -> Decoder {
        return try self.subDecoder(forKey: SuperCodingKey.super, orThrow: JSONParserError.missingSuperDecoder)
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        return try self.subDecoder(forKey: key, orThrow: JSONParserError.missingSuperDecoder)
    }
}

fileprivate struct UnkeyedJSONDecodingContainer: UnkeyedDecodingContainer {
    let decoder: _JSONDecoder
    private var offset = 17 // Array descriptions are 17 bytes

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
        if isAtEnd, decoder.settings.nilValueDecodingStrategy == .decodeNilForKeyNotFound { return true }
        try assertHasMore()
        guard decoder.description.type(atOffset: offset) == .null else { return false }

        if decoder.settings.nilValueDecodingStrategy == .treatNilValuesAsMissing {
            throw JSONParserError.decodingError(expected: Void?.self, keyPath: codingPath)
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
            throw JSONParserError.endOfArray
        }
    }
    
    mutating func decodeIfPresent(_ type: Bool.Type) throws -> Bool?     { return try self.decodeNil() ? nil : self.decode(Bool.self) }
    mutating func decodeIfPresent(_ type: String.Type) throws -> String? { return try self.decodeNil() ? nil : self.decode(String.self) }
    mutating func decodeIfPresent(_ type: Float.Type) throws -> Float?   { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: Double.Type) throws -> Double? { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: Int.Type) throws -> Int?       { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: Int8.Type) throws -> Int8?     { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: Int16.Type) throws -> Int16?   { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: Int32.Type) throws -> Int32?   { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: Int64.Type) throws -> Int64?   { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: UInt.Type) throws -> UInt?     { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8?   { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? { return try self.decodeNil() ? nil : self.decode(type) }
    mutating func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T : Decodable { return try self.decodeNil() ? nil : self.decode(type) }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        try assertHasMore()
        let type = decoder.description.type(atOffset: offset)
        skipValue()
        
        switch type {
        case .boolTrue: return true
        case .boolFalse: return false
        default: throw JSONParserError.decodingError(expected: Bool.self, keyPath: codingPath)
        }
    }
    
    mutating func floatingBounds() -> (Bounds, Bool)? {
        if isAtEnd { return nil }
        let type = decoder.description.type(atOffset: offset)
        guard type == .integer || type == .floatingNumber else { return nil }
        let bounds = decoder.description.dataBounds(atIndexOffset: offset)
        skipValue()
        return (bounds, type == .floatingNumber)
    }
    
    mutating func integerBounds() -> Bounds? {
        if isAtEnd { return nil }
        let type = decoder.description.type(atOffset: offset)
        guard type == .integer else { return nil }
        let bounds = decoder.description.dataBounds(atIndexOffset: offset)
        skipValue()
        return bounds
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        try assertHasMore()
        let type = decoder.description.type(atOffset: offset)
        
        if type != .string && type != .stringWithEscaping {
            throw JSONParserError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: offset)
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: type == .stringWithEscaping,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONParserError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        skipValue()
        return string
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        guard let (bounds, floating) = floatingBounds() else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return bounds.makeDouble(from: decoder.pointer, floating: floating)
    }
    
    mutating func decode(_ type: Float.Type) throws -> Float { return Float(try self.decode(Double.self)) }
    
    mutating func decodeInt<F: FixedWidthInteger>(_ type: F.Type) throws -> F {
        guard
            let bounds = integerBounds(),
            let int = bounds.makeInt(from: decoder.pointer)
        else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return try int.convert(to: F.self)
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int       { return try decodeInt(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8     { return try decodeInt(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16   { return try decodeInt(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32   { return try decodeInt(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64   { return try decodeInt(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt     { return try decodeInt(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8   { return try decodeInt(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { return try decodeInt(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { return try decodeInt(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { return try decodeInt(type) }
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable { let decoder = self.decoder.subDecoder(offsetBy: offset)
        skipValue()
        return try decoder.decode(type)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
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

fileprivate struct SingleValueJSONDecodingContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey] { decoder.codingPath }
    let decoder: _JSONDecoder
    
    func decodeNil() -> Bool { return decoder.description.topLevelType == .null }
    
    func floatingBounds() -> (Bounds, Bool)? {
        let type = decoder.description.topLevelType
        guard type == .integer || type == .floatingNumber else { return nil }
        let bounds = decoder.description.dataBounds(atIndexOffset: 0)
        return (bounds, type == .floatingNumber)
    }
    
    func integerBounds() -> Bounds? {
        guard decoder.description.topLevelType == .integer else { return nil }
        return decoder.description.dataBounds(atIndexOffset: 0)
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        switch decoder.description.topLevelType {
        case .boolTrue: return true
        case .boolFalse: return false
        default: throw JSONParserError.decodingError(expected: type, keyPath: codingPath)
        }
    }
    
    func decode(_ type: String.Type) throws -> String {
        let jsonType = decoder.description.topLevelType
        guard jsonType == .string || jsonType == .stringWithEscaping else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath)
        }
        let bounds = decoder.description.dataBounds(atIndexOffset: 0)
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: jsonType == .stringWithEscaping,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONParserError.decodingError(expected: String.self, keyPath: codingPath)
        }
        return string
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        guard let (bounds, floating) = floatingBounds() else {
            throw JSONParserError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return bounds.makeDouble(from: decoder.pointer, floating: floating)
    }
    
    func decode(_ type: Float.Type) throws -> Float { return try Float(decode(Double.self)) }
    
    func decodeInt<F: FixedWidthInteger>(ofType type: F.Type) throws -> F {
        let jsonType = decoder.description.topLevelType
        guard jsonType == .integer else { throw JSONParserError.decodingError(expected: type, keyPath: codingPath) }
        let bounds = decoder.description.dataBounds(atIndexOffset: 0)
        guard let int = bounds.makeInt(from: self.decoder.pointer) else { throw JSONParserError.decodingError(expected: type, keyPath: codingPath) }
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
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable { return try decoder.decode(type) }
}

extension FixedWidthInteger {
    /// Converts the current FixedWidthInteger to another FixedWithInteger type `I`
    ///
    /// Throws a `BSONTypeConversionError` if the range of `I` does not contain `self`
    internal func convert<I: FixedWidthInteger>(to int: I.Type) throws -> I {
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
