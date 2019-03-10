import Foundation
import NIO

#if os(Linux) && !swift(>=4.2.2)
extension JSONEncoder {
    public enum KeyEncodingStrategy {
        case useDefaultKeys
        case convertToSnakeCase
        case custom(([CodingKey]) -> CodingKey)
    }
}
#endif

/// These settings influence the encoding process.
public struct JSONEncoderSettings {
    public init() {}
    
    /// This userInfo is accessible by the Eecodable types that are being encoded
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// If a `nil` value is found, setting this to `true` will encode `null`. Otherwise the key is omitted.
    ///
    /// This is `false` by default
    public var encodeNilAsNull = false
    
    // TODO: Support
    
    /// Defines the method used when encode keys
    public var keyEncodingStrategy = JSONEncoder.KeyEncodingStrategy.useDefaultKeys
    
    @available(*, renamed: "keyEncodingStrategy")
    public var keyDecodingStrategy: JSONEncoder.KeyEncodingStrategy {
        get {
            return keyEncodingStrategy
        }
        set {
            keyEncodingStrategy = newValue
        }
    }
    
    /// The method used to encode Foundation `Date` types
    public var dateEncodingStrategy = JSONEncoder.DateEncodingStrategy.deferredToDate
    
    @available(*, renamed: "dateEncodingStrategy")
    public var dateDecodingStrategy: JSONEncoder.DateEncodingStrategy {
        get {
            return dateEncodingStrategy
        }
        set {
            dateEncodingStrategy = newValue
        }
    }
    
    public var dataEncodingStrategy = JSONEncoder.DataEncodingStrategy.base64
    
    /// The method used to encode Foundation `Data` types
    @available(*, renamed: "dataEncodingStrategy")
    public var dataDecodingStrategy: JSONEncoder.DataEncodingStrategy {
        get {
            return dataEncodingStrategy
        }
        set {
            dataEncodingStrategy = newValue
        }
    }
}

/// A type that automatically deallocated the pointer and can be expanded manually or automatically.
///
/// Has a few helpers for writing binary data. Mainly/only used for the JSONDescription.
final class AutoDeallocatingPointer {
    var pointer: UnsafeMutablePointer<UInt8>
    private(set) var totalSize: Int
    
    init(size: Int) {
        self.pointer = .allocate(capacity: size)
        totalSize = size
    }
    
    /// Expands the buffer to it's new absolute size and copies the usedCapacity to the new buffer.
    ///
    /// Any data after the userCapacity is lost
    func expand(to count: Int, usedCapacity size: Int) {
        let new = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        new.assign(from: pointer, count: size)
        pointer.deallocate()
        
        self.totalSize = count
        self.pointer = new
    }
    
    /// Expects `offset + count` bytes in this buffer, if this buffer is too small it's expanded
    private func beforeWrite(offset: Int, count: Int) {
        let needed = (offset &+ count) &- totalSize
        
        if needed > 0 {
            // A fat fingered number that will usually be efficient
            let newSize = offset &+ max(count, 4096)
            expand(to: newSize, usedCapacity: offset)
        }
    }
    
    /// Inserts the byte into this storage
    func insert(_ byte: UInt8, at offset: inout Int) {
        beforeWrite(offset: offset, count: 1)
        self.pointer.advanced(by: offset).pointee = byte
        offset = offset &+ 1
    }
    
    /// Inserts the other autdeallocated storage into this storage
    func insert(contentsOf storage: AutoDeallocatingPointer, count: Int, at offset: inout Int) {
        beforeWrite(offset: offset, count: count)
        self.pointer.advanced(by: offset).assign(from: storage.pointer, count: count)
        offset = offset &+ count
    }
    
    /// Inserts the other autdeallocated storage into this storage
    func insert(contentsOf storage: StaticString, at offset: inout Int) {
        beforeWrite(offset: offset, count: storage.utf8CodeUnitCount)
        self.pointer.advanced(by: offset).assign(from: storage.utf8Start, count: storage.utf8CodeUnitCount)
        offset = offset &+ storage.utf8CodeUnitCount
    }
    
    /// Inserts the bytes into this storage
    func insert(contentsOf storage: [UInt8], at offset: inout Int) {
        let count = storage.count
        beforeWrite(offset: offset, count: count)
        self.pointer.advanced(by: offset).assign(from: storage, count: count)
        offset = offset &+ count
    }
    
    deinit {
        /// The magic of this class, automatically deallocating thanks to ARC
        pointer.deallocate()
    }
}


/// A JSON Encoder that aims to be largely functionally equivalent to Foundation.JSONEncoder.
public struct IkigaJSONEncoder {
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// These settings influence the encoding process.
    public var settings = JSONEncoderSettings()
    
    public init() {}
    
    public func encode<E: Encodable>(_ value: E) throws -> Data {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        return Data(bytes: encoder.data.pointer, count: encoder.offset)
    }
    
    public func encodeAndWrite<E: Encodable>(_ value: E, into buffer: inout ByteBuffer) throws {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = UnsafeRawBufferPointer(start: encoder.data.pointer, count: encoder.offset)
        buffer.write(bytes: data)
    }
    
    public func encodeJSONObject<E: Encodable>(from value: E) throws -> JSONObject {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = Data(bytes: encoder.data.pointer, count: encoder.offset)
        return try JSONObject(data: data)
    }
    
    public func encodeJSONArray<E: Encodable>(from value: E) throws -> JSONArray {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = Data(bytes: encoder.data.pointer, count: encoder.offset)
        return try JSONArray(data: data)
    }
}

internal let nullBytes: StaticString = "null"
internal let boolTrue: StaticString = "true"
internal let boolFalse: StaticString = "false"

fileprivate final class _JSONEncoder: Encoder {
    var codingPath: [CodingKey]
    let data = AutoDeallocatingPointer(size: 512)
    private(set) var offset = 0
    var end: UInt8?
    var superEncoder: _JSONEncoder?
    var didWriteValue = false
    var userInfo: [CodingUserInfoKey : Any]
    var settings: JSONEncoderSettings
    
    func writeEnd() {
        if let end = end {
            data.insert(end, at: &offset)
            self.end = nil
        }
    }
    
    init(codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey : Any], settings: JSONEncoderSettings) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.settings = settings
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        data.insert(.curlyLeft, at: &offset)
        end = .curlyRight
        
        let container = KeyedJSONEncodingContainer<Key>(encoder: self)
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        data.insert(.squareLeft, at: &offset)
        end = .squareRight
        
        return UnkeyedJSONEncodingContainer(encoder: self)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return SingleValueJSONEncodingContainer(encoder: self)
    }
    
    func writeValue(_ string: String) {
        data.insert(.quote, at: &offset)
        data.insert(contentsOf: [UInt8](string.utf8), at: &offset)
        data.insert(.quote, at: &offset)
    }
    
    func writeNull() {
        data.insert(contentsOf: nullBytes, at: &offset)
    }
    
    func writeValue(_ value: Bool) {
        data.insert(contentsOf: value ? boolTrue : boolFalse, at: &offset)
    }
    
    func writeValue(_ value: Double) {
        // TODO: Optimize
        let number = String(value)
        data.insert(contentsOf: [UInt8](number.utf8), at: &offset)
    }
    
    func writeValue(_ value: Float) {
        // TODO: Optimize
        let number = String(value)
        data.insert(contentsOf: [UInt8](number.utf8), at: &offset)
    }
    
    func writeComma() {
        if didWriteValue {
            data.insert(.comma, at: &offset)
        } else {
            didWriteValue = true
        }
    }
    
    func writeKey(_ key: String) {
        writeComma()
        writeValue(key)
        data.insert(.colon, at: &offset)
    }
    
    func writeNull(forKey key: String) {
        writeKey(key)
        writeNull()
    }
    
    func writeValue(_ value: String, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }
    
    func writeValue(_ value: Bool, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }
    
    func writeValue(_ value: Double, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }
    
    func writeValue(_ value: Float, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }
    
    func writeValue<F: BinaryInteger>(_ value: F, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }
    
    func writeValue<F: BinaryInteger>(_ value: F) {
        // TODO: Optimize
        let number = String(value)
        data.insert(contentsOf: [UInt8](number.utf8), at: &offset)
    }
    
    deinit {
        if let end = end {
            data.insert(end, at: &offset)
        }
        
        if let superEncoder = superEncoder {
            superEncoder.data.insert(contentsOf: self.data, count: self.offset, at: &superEncoder.offset)
        }
    }
}

fileprivate struct KeyedJSONEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] {
        return encoder.codingPath
    }
    
    mutating func encodeNil(forKey key: Key) throws {
        encoder.writeNull(forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Bool, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: String, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Double, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Float, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Int, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Int8, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Int16, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Int32, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: Int64, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: UInt, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        self.encoder.writeKey(key.stringValue)
        let encoder = _JSONEncoder(codingPath: codingPath + [key], userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        try value.encode(to: encoder)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        self.encoder.writeKey(key.stringValue)
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        return encoder.container(keyedBy: keyType)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        self.encoder.writeKey(key.stringValue)
        let encoder = _JSONEncoder(codingPath: codingPath + [key], userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        return encoder.unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        return encoder
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        return encoder
    }
}

fileprivate struct SingleValueJSONEncodingContainer: SingleValueEncodingContainer {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] {
        return encoder.codingPath
    }
    
    mutating func encodeNil() throws {
        encoder.writeNull()
    }
    
    mutating func encode(_ value: Bool) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: String) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Double) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Float) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int8) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int16) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int32) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int64) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt8) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt16) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt32) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt64) throws {
        encoder.writeValue(value)
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        try value.encode(to: encoder)
    }
}

fileprivate struct UnkeyedJSONEncodingContainer: UnkeyedEncodingContainer {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] {
        return encoder.codingPath
    }
    var count = 0
    
    init(encoder: _JSONEncoder) {
        self.encoder = encoder
    }
    
    mutating func encodeNil() throws {
        self.encoder.writeComma()
        encoder.writeNull()
    }
    
    mutating func encode(_ value: Bool) throws {
        self.encoder.writeComma()
        self.encoder.writeNull()
    }
    
    mutating func encode(_ value: String) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Double) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Float) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int8) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int16) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int32) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int64) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt8) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt16) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt32) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt64) throws {
        self.encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        self.encoder.writeComma()
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        try value.encode(to: encoder)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        self.encoder.writeComma()
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        return encoder.container(keyedBy: keyType)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        self.encoder.writeComma()
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings)
        encoder.superEncoder = self.encoder
        return encoder.unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        return encoder
    }
}
