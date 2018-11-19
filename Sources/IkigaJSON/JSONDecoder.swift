import Foundation

@available(OSX 10.12, *)
let isoFormatter = ISO8601DateFormatter()
let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter
}()
    
func date(from string: String) throws -> Date {
    if #available(OSX 10.12, iOS 11, *) {
        guard let date = isoFormatter.date(from: string) else {
            throw JSONError.invalidDate(string)
        }
        
        return date
    } else {
        guard let date = dateFormatter.date(from: string) else {
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
    private var parser = JSONParser()
    
    public init(settings: JSONDecoderSettings = JSONDecoderSettings()) {
        self.settings = settings
    }
    
    /// Parses the Decodable type from an UnsafeBufferPointer.
    /// This API can be used when the data wasn't originally available as `Data` so you remove the need for copying data.
    /// This can save a lot of performance.
    public func decode<D: Decodable>(_ type: D.Type, from buffer: UnsafeBufferPointer<UInt8>) throws -> D {
        let pointer = buffer.baseAddress!
        parser.initialize(pointer: pointer, count: buffer.count)
        try parser.scanValue()
        let readOnly = parser.description.readOnly
        
        let decoder = _JSONDecoder(description: readOnly, pointer: pointer, settings: settings)
        let type = try D(from: decoder)
        parser.recycle()
        return type
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
    let description: ReadOnlyJSONDescription
    let pointer: UnsafePointer<UInt8>
    let settings: JSONDecoderSettings
    
    var codingPath = [CodingKey]()
    var userInfo: [CodingUserInfoKey : Any] {
        return settings.userInfo
    }
    
    func string<Key: CodingKey>(forKey key: Key) -> String {
        switch self.settings.keyDecodingStrategy {
        case .useDefaultKeys:
            return key.stringValue
        case .convertFromSnakeCase:
            var characters = [UInt8](key.stringValue.utf8)
            let size = characters.count
            
            for i in 0..<size {
                if characters[i] == .underscore, i &+ 1 < size {
                    let byte = characters[i &+ 1]
                    
                    if byte >= .a && byte <= .z {
                        characters[i] = byte &- 0x20
                        characters.remove(at: i &+ 1)
                    }
                }
            }
            
            // The string was guaranteed by us to still be valid UTF-8
            return String(bytes: characters, encoding: .utf8)!
        case .custom(let builder):
            return builder(codingPath + [key]).stringValue
        }
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        guard description.type == .object else {
            throw JSONError.missingKeyedContainer
        }
        
        let container = KeyedJSONDecodingContainer<Key>(decoder: self)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard description.type == .array else {
            throw JSONError.missingUnkeyedContainer
        }
        
        return UnkeyedJSONDecodingContainer(decoder: self)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SingleValueJSONDecodingContainer(decoder: self)
    }
    
    init(description: ReadOnlyJSONDescription, pointer: UnsafePointer<UInt8>, settings: JSONDecoderSettings) {
        self.description = description
        self.pointer = pointer
        self.settings = settings
    }
    
    func subDecoder(offsetBy offset: Int) -> _JSONDecoder {
        let subDescription = self.description.subDescription(offset: offset)
        return _JSONDecoder(description: subDescription, pointer: pointer, settings: settings)
    }
    
    func decode<D: Decodable>(_ type: D.Type) throws -> D {
//        switch type {
//        case is Date.Type:
//            switch self.settings.dateDecodingStrategy {
//            case .deferredToDate:
//                break
//            case .secondsSince1970:
//                if let seconds = value.makeInt(from: self.pointer) {
//                    return Date(timeIntervalSince1970: TimeInterval(seconds)) as! D
//                } else if let seconds = value.makeDouble(from: self.pointer) {
//                    return Date(timeIntervalSince1970: seconds) as! D
//                } else {
//                    throw JSONError.invalidDate(nil)
//                }
//            case .millisecondsSince1970:
//                if let seconds = value.makeInt(from: self.pointer) {
//                    return Date(timeIntervalSince1970: TimeInterval(seconds * 1000)) as! D
//                } else if let seconds = value.makeDouble(from: self.pointer) {
//                    return Date(timeIntervalSince1970: seconds * 1000) as! D
//                } else {
//                    throw JSONError.invalidDate(nil)
//                }
//            case .iso8601:
//                guard let string = value.makeString(from: self.pointer, unicode: self.settings.decodeUnicode) else {
//                    throw JSONError.invalidDate(nil)
//                }
//                
//                return try date(from: string) as! D
//            case .formatted(let formatter):
//                guard let string = value.makeString(from: self.pointer, unicode: self.settings.decodeUnicode) else {
//                    throw JSONError.invalidDate(nil)
//                }
//                
//                guard let date = formatter.date(from: string) else {
//                    throw JSONError.invalidDate(string)
//                }
//                
//                return date as! D
//            case .custom(let makeDate):
//                let decoder = _JSONDecoder(value: value, pointer: pointer, settings: self.settings)
//                return try makeDate(decoder) as! D
//            }
//        case is Data.Type:
//            switch self.settings.dataDecodingStrategy {
//            case .deferredToData:
//                break
//            case .base64:
//                guard let string = value.makeString(from: self.pointer, unicode: self.settings.decodeUnicode) else {
//                    throw JSONError.invalidData(nil)
//                }
//                
//                guard let data = Data(base64Encoded: string) else {
//                    throw JSONError.invalidData(string)
//                }
//                
//                return data as! D
//            case .custom(let makeData):
//                let decoder = _JSONDecoder(value: value, pointer: pointer, settings: self.settings)
//                return try makeData(decoder) as! D
//            }
//        default:
//            break
//        }
//
        let decoder = subDecoder(offsetBy: 0)
        return try D.init(from: decoder)
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
            unicode: decoder.settings.decodeUnicode
        )
    }
    
    var allKeys: [Key] {
        return allStringKeys.compactMap(Key.init)
    }
    
    func contains(_ key: Key) -> Bool {
        let key = decoder.string(forKey: key)
        return decoder.description.containsKey(key, inPointer: decoder.pointer, unicode: decoder.settings.decodeUnicode)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard let type = type(ofKey: key) else {
            return decoder.settings.decodeMissingKeyAsNil
        }
        
        return type == .null
    }
    
    func offset(forKey key: Key) -> Int? {
        // Object index
        var offset = 17
        
        let count = decoder.description.pointer.advanced(by: 1).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        let key = [UInt8](self.decoder.string(forKey: key).utf8)
        let keySize = key.count
        
        for _ in 0..<count {
            let bounds = decoder.description.pointer.advanced(by: offset &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            
            // Skip key
            decoder.description.skip(withOffset: &offset)
            if bounds.length == keySize, memcmp(key, self.decoder.pointer.advanced(by: bounds.offset), bounds.length) == 0 {
                return offset
            }
            
            // Skip value
            decoder.description.skip(withOffset: &offset)
        }
        
        return nil
    }
    
    func type(atOffset offset: Int) -> JSONType? {
        guard let type = JSONType(rawValue: decoder.description.pointer[offset]) else {
            assertionFailure("This type mnust be valid and known")
            return nil
        }
        
        return type
    }
    
    func type(ofKey key: Key) -> JSONType? {
        guard let offset = self.offset(forKey: key) else {
            return nil
        }
        
        return type(atOffset: offset)
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        guard let type = self.type(ofKey: key) else {
            throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath + [key])
        }
        
        switch type {
        case .boolTrue:
            return true
        case .boolFalse:
            return false
        default:
            throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath + [key])
        }
    }
    
    func floatingBounds(forKey key: Key) -> (Bounds, Bool)? {
        guard
            let offset = self.offset(forKey: key),
            let type = self.type(atOffset: offset),
            type == .integer || type == .floatingNumber
        else {
            return nil
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: offset &+ 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
        
        return (bounds, type == .floatingNumber)
    }
    
    func integerBounds(forKey key: Key) -> Bounds? {
        guard
            let offset = self.offset(forKey: key),
            let type = self.type(atOffset: offset),
            type == .integer
        else {
            return nil
        }
        
        return decoder.description.pointer
            .advanced(by: offset &+ 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
    }
    
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        guard
            let offset = self.offset(forKey: key),
            let type = self.type(atOffset: offset),
            type == .string || type == .stringWithEscaping
        else {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath + [key])
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: offset &+ 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
            }
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: type == .stringWithEscaping,
            unicode: decoder.settings.decodeUnicode
        ) else {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath + [key])
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
        guard let offset = self.offset(forKey: key) else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        let decoder = self.decoder.subDecoder(offsetBy: offset)
        return try decoder.decode(type)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let offset = self.offset(forKey: key) else {
            throw JSONError.missingKeyedContainer
        }
        
        var decoder = self.decoder.subDecoder(offsetBy: offset)
        decoder.codingPath.append(key)
        return try decoder.container(keyedBy: NestedKey.self)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        guard let offset = self.offset(forKey: key) else {
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
    var offset = 17
    var currentIndex = 0
    
    init(decoder: _JSONDecoder) {
        self.decoder = decoder
        self._count = decoder.description.arrayCount()
    }
    
    var _count: Int
    var count: Int? {
        return _count
    }
    
    var isAtEnd: Bool {
        return currentIndex >= _count
    }
    
    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd, let type = JSONType(rawValue: decoder.description.pointer[offset]) else {
            throw JSONError.internalStateError
        }
        
        skipValue()
        return type == .null
    }
    
    mutating func skipValue() {
        decoder.description.skip(withOffset: &offset)
        currentIndex = currentIndex &+ 1
    }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        guard let type = JSONType(rawValue: decoder.description.pointer[offset]) else {
            throw JSONError.internalStateError
        }
        
        decoder.description.skip(withOffset: &offset)
        skipValue()
        
        switch type {
        case .boolTrue: return true
        case .boolFalse: return false
        default:
            throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath)
        }
    }
    
    mutating func floatingBounds() -> (Bounds, Bool)? {
        guard
            let type = JSONType(rawValue: decoder.description.pointer[offset]),
            type == .integer || type == .floatingNumber
            else {
                return nil
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: offset &+ 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
        
        skipValue()
        return (bounds, type == .floatingNumber)
    }
    
    mutating func integerBounds() -> Bounds? {
        guard
            let type = JSONType(rawValue: decoder.description.pointer[offset]),
            type == .integer
            else {
                return nil
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: offset &+ 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
        
        skipValue()
        return bounds
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        guard
            let type = JSONType(rawValue: decoder.description.pointer[offset]),
            type == .string || type == .stringWithEscaping
        else {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: offset &+ 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
            }
        
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
        return decoder.description.type == .null
    }
    
    func floatingBounds() -> (Bounds, Bool)? {
        guard
            let type = JSONType(rawValue: decoder.description.pointer.pointee),
            type == .integer || type == .floatingNumber
        else {
            return nil
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
        
        return (bounds, type == .floatingNumber)
    }
    
    func integerBounds() -> Bounds? {
        guard
            let type = JSONType(rawValue: decoder.description.pointer.pointee),
            type == .integer
        else {
            return nil
        }
        
        return decoder.description.pointer
            .advanced(by: 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        switch decoder.description.type {
        case .boolTrue: return true
        case .boolFalse: return false
        default: throw JSONError.decodingError(expected: Bool.self, keyPath: codingPath)
        }
    }
    
    func decode(_ type: String.Type) throws -> String {
        let type = decoder.description.type
        
        guard type == .string || type == .stringWithEscaping else {
            throw JSONError.decodingError(expected: String.self, keyPath: codingPath)
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
        
        guard let string = bounds.makeString(
            from: decoder.pointer,
            escaping: type == .stringWithEscaping,
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
        guard decoder.description.pointer.pointee == JSONType.integer.rawValue else {
            throw JSONError.decodingError(expected: type, keyPath: codingPath)
        }
        
        let bounds = decoder.description.pointer
            .advanced(by: 1)
            .withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
        
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
