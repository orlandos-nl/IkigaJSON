import Foundation

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
    
    // TODO: Support
    
    /// Defines the method used when decoding keys
    public var keyDecodingStrategy = JSONDecoder.KeyDecodingStrategy.useDefaultKeys
    
    /// The method used to decode Foundation `Date` types
    public var dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.deferredToDate
    
    /// The method used to decode Foundation `Data` types
    public var dataDecodingStrategy = JSONDecoder.DataDecodingStrategy.base64
}

/// A JSON Decoder that aims to be largely functionally equivalent to Foundation.JSONDecoder with more for optimization.
public struct IkigaJSONDecoder {
    /// These settings can be used to alter the decoding process.
    public var settings: JSONDecoderSettings
    
    public init(settings: JSONDecoderSettings = JSONDecoderSettings()) {
        self.settings = settings
    }
    
    /// Parses the Decodable type from an UnsafeBufferPointer.
    /// This API can be used when the data wasn't originally available as `Data` so you remove the need for copying data.
    /// This can save a lot of performance.
    public func decode<D: Decodable>(_ type: D.Type, from buffer: UnsafeBufferPointer<UInt8>) throws -> D {
        let pointer = buffer.baseAddress!
        let value = try JSONParser.scanValue(fromPointer: pointer, count: buffer.count)
        
        let decoder = _JSONDecoder(value: value, pointer: pointer, settings: settings)
        return try D(from: decoder)
    }
    
    /// Parses the Decodable type from `Data`. This is the equivalent for JSONDecoder's Decode function.
    public func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D {
        let count = data.count
        
        return try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            return try decode(type, from: UnsafeBufferPointer(start: pointer, count: count))
        }
    }
}

fileprivate struct _JSONDecoder: Decoder {
    let value: JSONValue
    let pointer: UnsafePointer<UInt8>
    let settings: JSONDecoderSettings
    
    var codingPath = [CodingKey]()
    var userInfo: [CodingUserInfoKey : Any] {
        return settings.userInfo
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        guard case .object(let object) = value.storage else {
            throw JSONError.missingKeyedContainer
        }
        
        let container = KeyedJSONDecodingContainer<Key>(pointer: pointer, object: object, decoder: self)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = value.storage else {
            throw JSONError.missingUnkeyedContainer
        }
        
        return UnkeyedJSONDecodingContainer(pointer: pointer, array: array, decoder: self, currentIndex: 0)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SingleValueJSONDecodingContainer(pointer: pointer, value: value, decoder: self)
    }
    
    init(value: JSONValue, pointer: UnsafePointer<UInt8>, settings: JSONDecoderSettings) {
        self.value = value
        self.pointer = pointer
        self.settings = settings
    }
}

fileprivate struct KeyedJSONDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let pointer: UnsafePointer<UInt8>
    var codingPath: [CodingKey] {
        return decoder.codingPath
    }
    let object: JSONObjectDescription
    let decoder: _JSONDecoder
    
    var allKeys: [Key] {
        return object.pairs.compactMap { (key, _) in
            if let key = key.makeString(from: pointer, unicode: decoder.settings.decodeUnicode) {
                return Key(stringValue: key)
            }
            
            return nil
        }
    }
    
    func index(of key: Key) -> Int? {
        let string = key.stringValue
        let length = string.utf8.count
        
        return string.withCString { pointer in
            return pointer.withMemoryRebound(to: UInt8.self, capacity: length) { pointer in
                nextPair: for i in 0..<object.pairs.count {
                    let key = object.pairs[i].key
                    
                    guard key.length == length else {
                        continue nextPair
                    }
                    
                    if memcmp(pointer, self.pointer + key.offset, length) == 0 {
                        return i
                    }
                }
                
                return nil
            }
        }
    }
    
    func contains(_ key: Key) -> Bool {
        return index(of: key) != nil
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = value(forKey: key) else {
            return decoder.settings.decodeMissingKeyAsNil
        }
        
        return value.isNull
    }
    
    func value(forKey key: Key) -> JSONValue? {
        let string = key.stringValue
        let length = string.utf8.count
        
        return string.withCString { pointer in
            return pointer.withMemoryRebound(to: UInt8.self, capacity: length) { pointer in
                nextPair: for i in 0..<object.pairs.count {
                    let pair = object.pairs[i]
                    
                    guard pair.key.length == length else {
                        continue nextPair
                    }
                    
                    if memcmp(pointer, self.pointer + pair.key.offset, length) == 0 {
                        return pair.value
                    }
                }
                
                return nil
            }
        }
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        if let bool = value(forKey: key)?.bool {
            return bool
        }
        
        throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath)
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        if let value = value(forKey: key), let string = value.makeString(from: pointer, unicode: decoder.settings.decodeUnicode) {
            return string
        }
        
        throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        if let value = value(forKey: key), let double = value.makeDouble(from: pointer) {
            return double
        }
        
        throw JSONError.decodingError(expected: Double.self, keyPath: codingPath)
    }
    
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        if
            let value = value(forKey: key),
            let double = value.makeDouble(from: pointer)
        {
            return Float(double)
        }
        
        throw JSONError.decodingError(expected: Float.self, keyPath: codingPath)
    }
    
    func decodeInt<F: FixedWidthInteger>(_ type: F.Type, forKey key: Key) throws -> F {
        if let value = value(forKey: key), let int = value.makeInt(from: pointer) {
            return try int.convert(to: F.self)
        }
        
        throw JSONError.decodingError(expected: F.self, keyPath: codingPath)
    }
    
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        if let value = value(forKey: key), let int = value.makeInt(from: pointer) {
            return int
        }
        
        throw JSONError.decodingError(expected: Int.self, keyPath: codingPath)
    }
    
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return try decodeInt(Int8.self, forKey: key)
    }
    
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return try decodeInt(Int16.self, forKey: key)
    }
    
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return try decodeInt(Int32.self, forKey: key)
    }
    
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        return try decodeInt(Int64.self, forKey: key)
    }
    
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        return try decodeInt(UInt.self, forKey: key)
    }
    
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        return try decodeInt(UInt8.self, forKey: key)
    }
    
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        return try decodeInt(UInt16.self, forKey: key)
    }
    
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        return try decodeInt(UInt32.self, forKey: key)
    }
    
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        return try decodeInt(UInt64.self, forKey: key)
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        guard let value = value(forKey: key) else {
            throw JSONError.decodingError(expected: T.self, keyPath: codingPath)
        }
        
        let decoder = _JSONDecoder(value: value, pointer: pointer, settings: self.decoder.settings)
        return try T.init(from: decoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let value = value(forKey: key) else {
            throw JSONError.missingKeyedContainer
        }
        
        var decoder = _JSONDecoder(value: value, pointer: pointer, settings: self.decoder.settings)
        decoder.codingPath.append(key)
        return try decoder.container(keyedBy: NestedKey.self)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        guard let value = value(forKey: key) else {
            throw JSONError.missingKeyedContainer
        }
        
        var decoder = _JSONDecoder(value: value, pointer: pointer, settings: self.decoder.settings)
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
    let pointer: UnsafePointer<UInt8>
    let array: JSONArrayDescription
    let decoder: _JSONDecoder
    
    var count: Int? {
        return array.values.count
    }
    
    var nextValue: JSONValue {
        return array.values[currentIndex]
    }
    
    var isAtEnd: Bool { return currentIndex == array.values.count }
    var currentIndex: Int
    
    mutating func decodeNil() throws -> Bool {
        let null = nextValue.isNull
        currentIndex = currentIndex &+ 1
        return null
    }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        if let bool = nextValue.bool {
            currentIndex = currentIndex &+ 1
            return bool
        }
        
        throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath)
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        if let string = nextValue.makeString(from: pointer, unicode: decoder.settings.decodeUnicode) {
            currentIndex = currentIndex &+ 1
            return string
        }
        
        throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        if let double = nextValue.makeDouble(from: pointer) {
            currentIndex = currentIndex &+ 1
            return double
        }
        
        throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
    }
    
    mutating func decode(_ type: Float.Type) throws -> Float {
        if let double = nextValue.makeDouble(from: pointer) {
            currentIndex = currentIndex &+ 1
            return Float(double)
        }
        
        throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
    }
    
    mutating func decodeInt<F: FixedWidthInteger>(_ type: F.Type) throws -> F {
        if let int = nextValue.makeInt(from: pointer) {
            currentIndex = currentIndex &+ 1
            return try int.convert(to: F.self)
        }
        
        throw JSONError.decodingError(expected: F.self, keyPath: codingPath)
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        if let int = nextValue.makeInt(from: pointer) {
            currentIndex = currentIndex &+ 1
            return int
        }
        
        throw JSONError.decodingError(expected: Int.self, keyPath: codingPath)
    }
    
    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        return try decodeInt(Int8.self)
    }
    
    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        return try decodeInt(Int16.self)
    }
    
    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        return try decodeInt(Int32.self)
    }
    
    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        return try decodeInt(Int64.self)
    }
    
    mutating func decode(_ type: UInt.Type) throws -> UInt {
        return try decodeInt(UInt.self)
    }
    
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try decodeInt(UInt8.self)
    }
    
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try decodeInt(UInt16.self)
    }
    
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try decodeInt(UInt32.self)
    }
    
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try decodeInt(UInt64.self)
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        let decoder = _JSONDecoder(value: nextValue, pointer: pointer, settings: self.decoder.settings)
        currentIndex = currentIndex &+ 1
        return try T(from: decoder)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        let decoder = _JSONDecoder(value: nextValue, pointer: pointer, settings: self.decoder.settings)
        currentIndex = currentIndex &+ 1
        return try decoder.container(keyedBy: NestedKey.self)
    }
    
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let decoder = _JSONDecoder(value: nextValue, pointer: pointer, settings: self.decoder.settings)
        currentIndex = currentIndex &+ 1
        return try decoder.unkeyedContainer()
    }
    
    mutating func superDecoder() throws -> Decoder {
        return decoder
    }
}

fileprivate struct SingleValueJSONDecodingContainer: SingleValueDecodingContainer {
    let pointer: UnsafePointer<UInt8>
    var codingPath: [CodingKey] {
        return decoder.codingPath
    }
    let value: JSONValue
    let decoder: _JSONDecoder
    
    func decodeNil() -> Bool {
        return value.isNull
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        if let bool = value.bool {
            return bool
        }
        throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath)
    }
    
    func decode(_ type: String.Type) throws -> String {
        if let string = value.makeString(from: pointer, unicode: decoder.settings.decodeUnicode) {
            return string
        }
        
        throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        if let double = value.makeDouble(from: pointer) {
            return double
        }
        
        throw JSONError.decodingError(expected: Double.self, keyPath: codingPath)
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        if let double = value.makeDouble(from: pointer) {
            return Float(double)
        }
        
        throw JSONError.decodingError(expected: Float.self, keyPath: codingPath)
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
        if let int = value.makeInt(from: pointer) {
            return try int.convert(to: type)
        }
        
        throw JSONError.decodingError(expected: type, keyPath: codingPath)
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        let decoder = _JSONDecoder(value: value, pointer: pointer, settings: self.decoder.settings)
        return try T.init(from: decoder)
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
