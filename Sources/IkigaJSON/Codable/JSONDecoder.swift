import Foundation
import NIO

@available(OSX 10.12, *)
let isoFormatter = ISO8601DateFormatter()
let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter
}()

#if os(Linux) && !swift(>=4.2.2) && !compiler(>=5.0)
extension JSONDecoder {
    public enum KeyDecodingStrategy {
        case useDefaultKeys
        case convertFromSnakeCase
        case custom(([CodingKey]) -> CodingKey)
    }
}
#endif
    
func date(from string: String) throws -> Date {
    if #available(OSX 10.12, iOS 11, *) {
        guard let date = isoFormatter.date(from: string) else {
            throw JSONError.invalidDate(string)
        }
        
        return date
    } else {
        guard let date = isoDateFormatter.date(from: string) else {
            throw JSONError.invalidDate(string)
        }
        
        return date
    }
}

/// These settings can be used to alter the decoding process.
public struct JSONDecoderSettings {
    public init() {}
    
    /// This userInfo is accessible by the Decodable types that are being created
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// When strings are read, no extra effort is put into decoding unicode characters such as `\u00ff`
    ///
    /// `true` by default
    public var decodeUnicode = true
    
    /// When a key is not set in the JSON Object it is regarded as `null` if the value is `true`.
    ///
    /// `true` by default
    public var decodeMissingKeyAsNil = true
    
    /// Defines the method used when decoding keys
    public var keyDecodingStrategy = JSONDecoder.KeyDecodingStrategy.useDefaultKeys
    
    /// The method used to decode Foundation `Date` types
    public var dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.deferredToDate
    
    /// The method used to decode Foundation `Data` types
    public var dataDecodingStrategy = JSONDecoder.DataDecodingStrategy.base64
}

/// A JSON Decoder that aims to be largely functionally equivalent to Foundation.JSONDecoder with more for optimization.
public final class IkigaJSONDecoder {
    /// These settings can be used to alter the decoding process.
    public var settings: JSONDecoderSettings
    private var parser: JSONParser!
    
    public init(settings: JSONDecoderSettings = JSONDecoderSettings()) {
        self.settings = settings
    }
    
    /// Parses the Decodable type from an UnsafeBufferPointer.
    /// This API can be used when the data wasn't originally available as `Data` so you remove the need for copying data.
    /// This can save a lot of performance.
    public func decode<D: Decodable>(_ type: D.Type, from buffer: UnsafeBufferPointer<UInt8>) throws -> D {
        let pointer = buffer.baseAddress!
        if parser == nil {
            parser = JSONParser(pointer: pointer, count: buffer.count)
        } else {
            parser.recycle(pointer: pointer, count: buffer.count)
        }
        try parser.scanValue()
        
        let decoder = _JSONDecoder(description: parser!.description, pointer: pointer, settings: settings)
        let type = try D(from: decoder)
        return type
    }
    
    /// Parses the Decodable type from `Data`. This is the equivalent for JSONDecoder's Decode function.
    public func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D {
        let count = data.count
        
        return try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            return try decode(type, from: UnsafeBufferPointer(start: pointer, count: count))
        }
    }
    
    /// Parses the Decodable type from a JSONObject.
    public func decode<D: Decodable>(_ type: D.Type, from object: JSONObject) throws -> D {
        return try object.jsonBuffer.withUnsafeReadableBytes { buffer in
            let decoder = _JSONDecoder(
                description: object.description,
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
    public func decode<D: Decodable>(_ type: D.Type, from bytes: [UInt8]) throws -> D {
        return try bytes.withUnsafeBufferPointer { buffer in
            return try decode(type, from: buffer)
        }
    }
    
    /// Parses the Decodable type from `[UInt8]`. This is the equivalent for JSONDecoder's Decode function.
    public func decode<D: Decodable>(_ type: D.Type, from string: String) throws -> D {
        // TODO: Optimize with Swift 5
        guard let data = string.data(using: .utf8) else {
            throw JSONError.invalidData(string)
        }
        
        return try self.decode(type, from: data)
    }
}

fileprivate struct _JSONDecoder: Decoder {
    let description: JSONDescription
    let pointer: UnsafePointer<UInt8>
    let settings: JSONDecoderSettings
    var snakeCasing: Bool
    
    var codingPath = [CodingKey]()
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
            throw JSONError.missingKeyedContainer
        }
        
        let container = KeyedJSONDecodingContainer<Key>(decoder: self)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard description.topLevelType == .array else {
            throw JSONError.missingUnkeyedContainer
        }
        
        return UnkeyedJSONDecodingContainer(decoder: self)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SingleValueJSONDecodingContainer(decoder: self)
    }
    
    init(description: JSONDescription, pointer: UnsafePointer<UInt8>, settings: JSONDecoderSettings) {
        self.description = description
        self.pointer = pointer
        self.settings = settings
        
        if case .convertFromSnakeCase = settings.keyDecodingStrategy {
            self.snakeCasing = true
        } else {
            self.snakeCasing = false
        }
    }
    
    func subDecoder(offsetBy offset: Int) -> _JSONDecoder {
        let subDescription = self.description.subDescription(offset: offset)
        return _JSONDecoder(description: subDescription, pointer: pointer, settings: settings)
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
                    throw JSONError.invalidDate(string)
                }
                
                return date as! D
            case .custom(let makeDate):
                return try makeDate(self) as! D
            }
        case is Data.Type:
            switch self.settings.dataDecodingStrategy {
            case .deferredToData:
                break
            case .base64:
                let string = try singleValueContainer().decode(String.self)
                
                guard let data = Data(base64Encoded: string) else {
                    throw JSONError.invalidData(string)
                }
                
                return data as! D
            case .custom(let makeData):
                return try makeData(self) as! D
            }
        default:
            break
        }

        return try D.init(from: self)
    }
}

fileprivate struct KeyedJSONDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] {
        return decoder.codingPath
    }
    let decoder: _JSONDecoder
    
    var allStringKeys: [String] {
        return decoder.description.keys(
            inPointer: decoder.pointer,
            unicode: decoder.settings.decodeUnicode,
            convertingSnakeCasing: self.decoder.snakeCasing
        )
    }
    
    var allKeys: [Key] {
        return allStringKeys.compactMap(Key.init)
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
        guard let type = decoder.description.type(
            ofKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        ) else {
            return decoder.settings.decodeMissingKeyAsNil
        }
        
        return type == .null
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        guard let jsonType = decoder.description.type(
            ofKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        ) else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        switch jsonType {
        case .boolTrue:
            return true
        case .boolFalse:
            return false
        default:
            throw JSONError.decodingError(expected: type, keyPath: codingPath + [key])
        }
    }
    
    func floatingBounds(forKey key: Key) -> (Bounds, Bool)? {
        return decoder.description.floatingBounds(
            forKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        )
    }
    
    func integerBounds(forKey key: Key) -> Bounds? {
        return decoder.description.integerBounds(
            forKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        )
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        guard let (bounds, escaped) = decoder.description.stringBounds(
            forKey: decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: decoder.pointer
        ) else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: escaped,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        return string
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        guard
            let (bounds, floating) = floatingBounds(forKey: key),
            let double = bounds.makeDouble(from: decoder.pointer, floating: floating)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath + [key])
        }
        
        return double
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        guard
            let (bounds, floating) = floatingBounds(forKey: key),
            let double = bounds.makeDouble(from: decoder.pointer, floating: floating)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return Float(double)
    }
    
    func decodeInt<F: FixedWidthInteger>(_ type: F.Type, forKey key: Key) throws -> F {
        if let bounds = integerBounds(forKey: key), let int = bounds.makeInt(from: decoder.pointer) {
            return try int.convert(to: F.self)
        }
        
        throw JSONError.decodingError(expected: F.self, keyPath: codingPath)
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
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        guard let (_, offset) = self.decoder.description.valueOffset(
            forKey: self.decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: self.decoder.pointer
        ) else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        let decoder = self.decoder.subDecoder(offsetBy: offset)
        return try decoder.decode(type)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let (_, offset) = self.decoder.description.valueOffset(
            forKey: self.decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: self.decoder.pointer
        ) else {
            throw JSONError.missingKeyedContainer
        }
        
        var decoder = self.decoder.subDecoder(offsetBy: offset)
        decoder.codingPath.append(key)
        return try decoder.container(keyedBy: NestedKey.self)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        guard let (_, offset) = self.decoder.description.valueOffset(
            forKey: self.decoder.string(forKey: key),
            convertingSnakeCasing: self.decoder.snakeCasing,
            in: self.decoder.pointer
        ) else {
            throw JSONError.missingUnkeyedContainer
        }
        
        var decoder = self.decoder.subDecoder(offsetBy: offset)
        decoder.codingPath.append(key)
        return try decoder.unkeyedContainer()
    }
    
    func superDecoder() throws -> Decoder {
        return decoder
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        return decoder
    }
}

fileprivate struct UnkeyedJSONDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] {
        return decoder.codingPath
    }
    let decoder: _JSONDecoder
    // Array descriptions are 17 bytes
    var offset = 17
    var currentIndex = 0
    
    init(decoder: _JSONDecoder) {
        self.decoder = decoder
        self._count = decoder.description.arrayObjectCount()
    }
    
    var _count: Int
    var count: Int? {
        return _count
    }
    
    var isAtEnd: Bool {
        return currentIndex >= _count
    }
    
    mutating func decodeNil() throws -> Bool {
        try assertHasMore()
        
        let type = decoder.description.type(atOffset: offset)
        skipValue()
        return type == .null
    }
    
    mutating func skipValue() {
        decoder.description.skipIndex(atOffset: &offset)
        currentIndex = currentIndex &+ 1
    }
    
    func assertHasMore() throws {
        guard !isAtEnd else {
            throw JSONError.endOfObject
        }
    }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        try assertHasMore()
        let type = decoder.description.type(atOffset: offset)
        decoder.description.skipIndex(atOffset: &offset)
        skipValue()
        
        switch type {
        case .boolTrue: return true
        case .boolFalse: return false
        default:
            throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath)
        }
    }
    
    mutating func floatingBounds() -> (Bounds, Bool)? {
        if isAtEnd { return nil }
        
        let type = decoder.description.type(atOffset: offset)
        
        guard
            type == .integer || type == .floatingNumber
        else {
            return nil
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: offset)
        skipValue()
        return (bounds, type == .floatingNumber)
    }
    
    mutating func integerBounds() -> Bounds? {
        if isAtEnd { return nil }
        
        let type = decoder.description.type(atOffset: offset)
        
        if type != .integer {
            return nil
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: offset)
        skipValue()
        return bounds
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        try assertHasMore()
        let type = decoder.description.type(atOffset: offset)
        
        if type != .string && type != .stringWithEscaping {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: offset)
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: type == .stringWithEscaping,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        skipValue()
        return string
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        guard
            let (bounds, floating) = floatingBounds(),
            let double = bounds.makeDouble(from: decoder.pointer, floating: floating)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return double
    }
    
    mutating func decode(_ type: Float.Type) throws -> Float {
        guard
            let (bounds, floating) = floatingBounds(),
            let double = bounds.makeDouble(from: decoder.pointer, floating: floating)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return Float(double)
    }
    
    mutating func decodeInt<F: FixedWidthInteger>(_ type: F.Type) throws -> F {
        guard
            let bounds = integerBounds(),
            let int = bounds.makeInt(from: decoder.pointer)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return try int.convert(to: F.self)
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: UInt.Type) throws -> UInt {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try decodeInt(type)
    }
    
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try decodeInt(type)
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        let decoder = self.decoder.subDecoder(offsetBy: offset)
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
        return decoder
    }
}

fileprivate struct SingleValueJSONDecodingContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey] {
        return decoder.codingPath
    }
    let decoder: _JSONDecoder
    
    func decodeNil() -> Bool {
        return decoder.description.topLevelType == .null
    }
    
    func floatingBounds() -> (Bounds, Bool)? {
        let type = decoder.description.topLevelType
        
        if type != .integer && type != .floatingNumber {
            return nil
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: 0)
        return (bounds, type == .floatingNumber)
    }
    
    func integerBounds() -> Bounds? {
        if decoder.description.topLevelType != .integer {
            return nil
        }
        
        return decoder.description.dataBounds(atIndexOffset: 0)
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        switch decoder.description.topLevelType {
        case .boolTrue: return true
        case .boolFalse: return false
        default: throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
    }
    
    func decode(_ type: String.Type) throws -> String {
        let jsonType = decoder.description.topLevelType
        
        guard jsonType == .string || jsonType == .stringWithEscaping else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: 0)
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: jsonType == .stringWithEscaping,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        return string
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        guard
            let (bounds, floating) = floatingBounds(),
            let double = bounds.makeDouble(from: decoder.pointer, floating: floating)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return double
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        guard
            let (bounds, floating) = floatingBounds(),
            let double = bounds.makeDouble(from: decoder.pointer, floating: floating)
        else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return Float(double)
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try decodeInt(ofType: type)
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try decodeInt(ofType: type)
    }
    
    func decodeInt<F: FixedWidthInteger>(ofType type: F.Type) throws -> F {
        let jsonType = decoder.description.topLevelType
        
        guard jsonType == .integer else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        let bounds = decoder.description.dataBounds(atIndexOffset: 0)
        
        guard let int = bounds.makeInt(from: self.decoder.pointer) else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        return try int.convert(to: type)
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        return try decoder.decode(type)
    }
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
