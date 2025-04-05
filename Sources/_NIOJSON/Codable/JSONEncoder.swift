import Foundation
import NIOCore
import _JSONCore

/// These settings influence the encoding process.
public struct JSONEncoderSettings: @unchecked Sendable {
    public init() {}
    
    /// The manner of expanding internal buffers for growing encoding demands
    public var bufferExpansionMode = ExpansionMode.normal
    
    public var expectedJSONSize = 16_384
    
    /// This userInfo is accessible by the Eecodable types that are being encoded
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// Defines how to act when a `nil` value is encountered during encoding.
    public var nilValueEncodingStrategy: NilValueEncodingStrategy = .default
    
    /// If a `nil` value is found, setting this to `true` will encode `null`. Otherwise the key is omitted.
    ///
    /// - Warning: This property is deprecated. Use `nilValueEncodingStrategy` instead. This property
    ///   will return true if the strategy is `.alwaysEncodeNil`, false otherwise. Setting this property
    ///   to true selects the `.alwaysEncodeNil` strategy. Setting this property to false selects the
    ///   `.neverEncodeNil` strategy, if and only if the property's setter is explicitly called. In
    ///   other words, if this property is never set, the strategy remains `.default`.
    @available(*, deprecated, message: "Use `nilValueEncodingStrategy` instead.")
    public var encodeNilAsNull: Bool {
        get {
            return self.nilValueEncodingStrategy == .alwaysEncodeNil
        }
        set {
            self.nilValueEncodingStrategy = newValue ? .alwaysEncodeNil : .neverEncodeNil
        }
    }
    
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

/// The manner of expanding internal buffers for growing encoding demands
public enum ExpansionMode: Sendable {
    /// For limited RAM environments
    case smallest
    
    /// For small datasets
    case small
    
    /// Normal use cases
    case normal
    
    /// For large datsets
    case eager
}

/// A type that automatically deallocated the pointer and can be expanded manually or automatically.
///
/// Has a few helpers for writing binary data. Mainly/only used for the JSONDescription.
final class SharedEncoderData {
    var pointer: UnsafeMutablePointer<UInt8>
    private(set) var totalSize: Int
    let expansionMode: ExpansionMode
    let settings: JSONEncoderSettings
    let expectedSize: Int
    var offset = 0
    
    init(expectedSize: Int, expansionMode: ExpansionMode, settings: JSONEncoderSettings) {
        self.pointer = .allocate(capacity: expectedSize)
        self.expansionMode = expansionMode
        self.totalSize = expectedSize
        self.expectedSize = expectedSize
        self.settings = settings
    }
    
    /// Expands the buffer to it's new absolute size and copies the usedCapacity to the new buffer.
    ///
    /// Any data after the userCapacity is lost
    func expand(to count: Int, usedCapacity size: Int) {
        let new = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        new.update(from: pointer, count: size)
        pointer.deallocate()
        totalSize = count
        self.pointer = new
    }
    
    /// Expects `offset + count` bytes in this buffer, if this buffer is too small it's expanded
    private func beforeWrite(offset: Int, count: Int) {
        let needed = (offset &+ count) &- totalSize
        
        if needed > 0 {
            let newSize: Int
            
            switch expansionMode {
            case .eager:
                newSize = max(totalSize &* 2, offset &+ count)
            case .normal:
                newSize = offset &+ max(count, expectedSize)
            case .small:
                newSize = offset &+ max(count, 4096)
            case .smallest:
                newSize = offset &+ count
            }
            
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
    func insert(contentsOf storage: SharedEncoderData, count: Int, at offset: inout Int) {
        beforeWrite(offset: offset, count: count)
        self.pointer.advanced(by: offset).update(from: storage.pointer, count: count)
        offset = offset &+ count
    }
    
    /// Inserts the other autdeallocated storage into this storage
    func insert(contentsOf data: [UInt8], at offset: inout Int) {
        beforeWrite(offset: offset, count: data.count)
        self.pointer.advanced(by: offset).update(from: data, count: data.count)
        offset = offset &+ data.count
    }
    
    /// Inserts the other autdeallocated storage into this storage
    func insert(contentsOf storage: StaticString, at offset: inout Int) {
        beforeWrite(offset: offset, count: storage.utf8CodeUnitCount)
        self.pointer.advanced(by: offset).update(from: storage.utf8Start, count: storage.utf8CodeUnitCount)
        offset = offset &+ storage.utf8CodeUnitCount
    }
    
    /// Inserts the bytes into this storage
    func insert(contentsOf string: String, at offset: inout Int) {
        let writeOffset = offset
        let utf8 = string.utf8
        let count = utf8.withContiguousStorageIfAvailable { utf8String -> Int in
            self.beforeWrite(offset: writeOffset, count: utf8String.count)
            self.pointer.advanced(by: writeOffset).update(
                from: utf8String.baseAddress!,
                count: utf8String.count
            )
            return utf8String.count
        }
        
        if let count = count {
            offset = offset &+ count
        } else {
            let count = utf8.count
            let buffer = Array(utf8)
            self.pointer.advanced(by: writeOffset).update(
                from: buffer,
                count: count
            )
            offset = offset &+ count
        }
    }
    
    func cleanUp() {
        /// The magic of this class, automatically deallocating thanks to ARC
        pointer.deallocate()
    }
}


/// A JSON Encoder that aims to be largely functionally equivalent to Foundation.JSONEncoder.
public struct IkigaJSONEncoder: @unchecked Sendable {
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// These settings influence the encoding process.
    public var settings = JSONEncoderSettings()
    
    public init() {}
    
    public func encode<E: Encodable>(_ value: E) throws -> Data {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = Data(bytes: encoder.data.pointer, count: encoder.offset)
        encoder.cleanUp()
        return data
    }
    
    /// Encodes the provided value as JSON into the given buffer.
    public func encodeAndWrite<E: Encodable>(_ value: E, into buffer: inout ByteBuffer) throws {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = UnsafeRawBufferPointer(start: encoder.data.pointer, count: encoder.offset)
        buffer.writeBytes(data)
        encoder.cleanUp()
    }
    
    /// Encodes the provided value as JSON and returns a JSON Object.
    /// If the value is not a JSON Object, an error is thrown.
    public func encodeJSONObject<E: Encodable>(from value: E) throws -> JSONObject {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = ByteBuffer(
            bytes: UnsafeBufferPointer(
                start: encoder.data.pointer,
                count: encoder.data.offset
            )
        )
        let object = try JSONObject(buffer: data)
        encoder.cleanUp()
        return object
    }
    
    /// Encodes the provided value as JSON and returns a JSON Array.
    /// If the value is not a JSON Array, an error is thrown.
    public func encodeJSONArray<E: Encodable>(from value: E) throws -> JSONArray {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        let data = Data(bytes: encoder.data.pointer, count: encoder.offset)
        let array = try JSONArray(data: data)
        encoder.cleanUp()
        return array
    }
}

internal let nullBytes: StaticString = "null"
internal let boolTrue: StaticString = "true"
internal let boolFalse: StaticString = "false"

fileprivate final class _JSONEncoder: Encoder {
    var codingPath: [CodingKey]
    let data: SharedEncoderData
    fileprivate(set) var offset: Int {
        get {
            return data.offset
        }
        set {
            data.offset = newValue
        }
    }
    var end: UInt8?
    var didWriteValue = false
    var didHaveContainers = false
    var userInfo: [CodingUserInfoKey : Any]
    var settings: JSONEncoderSettings { data.settings }
    
    func cleanUp() {
        data.cleanUp()
    }
    
    func writeEnd() {
        if let end = end {
            data.insert(end, at: &offset)
            self.end = nil
        }
    }
    
    init(codingPath: [CodingKey], userInfo: [CodingUserInfoKey : Any], data: SharedEncoderData) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.data = data
    }
    
    init(userInfo: [CodingUserInfoKey : Any], settings: JSONEncoderSettings) {
        self.codingPath = []
        self.userInfo = userInfo
        data = SharedEncoderData(expectedSize: settings.expectedJSONSize, expansionMode: settings.bufferExpansionMode, settings: settings)
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        if didWriteValue || didHaveContainers {
            data.insert(.comma, at: &offset)
        }
        
        data.insert(.curlyLeft, at: &offset)
        end = .curlyRight
        didHaveContainers = true
        
        let container = KeyedJSONEncodingContainer<Key>(encoder: self)
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        if didWriteValue || didHaveContainers {
            data.insert(.comma, at: &offset)
        }
        
        data.insert(.squareLeft, at: &offset)
        end = .squareRight
        didHaveContainers = true
        
        return UnkeyedJSONEncodingContainer(encoder: self)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return SingleValueJSONEncodingContainer(encoder: self)
    }
    
    func writeValue(_ string: String) {
        data.insert(.quote, at: &offset)
        data.insert(contentsOf: string.escaped.1, at: &offset)
        data.insert(.quote, at: &offset)
        didWriteValue = true
    }
    
    func writeNull() {
        data.insert(contentsOf: nullBytes, at: &offset)
        didWriteValue = true
    }
    
    func writeValue(_ value: Bool) {
        data.insert(contentsOf: value ? boolTrue : boolFalse, at: &offset)
        didWriteValue = true
    }
    
    func writeValue<I: BinaryInteger>(_ value: I) {
        // TODO: Optimize
        data.insert(contentsOf: String(value), at: &offset)
        didWriteValue = true
    }

    func writeValue<F: BinaryFloatingPoint & LosslessStringConvertible>(_ value: F) {
        // TODO: Optimize
        data.insert(contentsOf: String(value), at: &offset)
        didWriteValue = true
    }
    
    // Returns `true` if it was handled, false if it needs to be deferred
    // If key isn't nil and anything is to be written, the key is written first
    func writeOtherValue<T: Encodable>(_ value: T, forKey key: String? = nil) throws -> Bool {
        switch value {
        case let date as Date:
            switch settings.dateEncodingStrategy {
            case .deferredToDate:
                return false
            case .secondsSince1970:
                if let key = key {
                    writeKey(key)
                }
                writeValue(date.timeIntervalSince1970)
            case .millisecondsSince1970:
                if let key = key {
                    writeKey(key)
                }
                writeValue(date.timeIntervalSince1970 * 1000)
            case .iso8601:
                let string: String
                
                if #available(OSX 10.12, iOS 11, *) {
                    string = isoFormatter.string(from: date)
                } else {
                    string = isoDateFormatter.string(from: date)
                }
                
                key.map { writeKey($0) }
                writeValue(string)
            #if !canImport(FoundationEssentials) || swift(<5.10)
            case .formatted(let formatter):
                let string = formatter.string(from: date)
                if let key = key {
                    writeKey(key)
                }
                writeValue(string)
            #endif
            case .custom(let custom):
                let offsetBeforeKey = offset, hadWrittenValue = didWriteValue
                if let key = key {
                    writeKey(key)
                }
                let encoder = _JSONEncoder(codingPath: codingPath, userInfo: userInfo, data: self.data)
                try custom(date, encoder)
                if encoder.didWriteValue {
                    didWriteValue = true
                } else if !encoder.didWriteValue, !encoder.didHaveContainers, key != nil, offset - offsetBeforeKey > 0 {
                    // TODO: This is a pretty crummy hack
                    offset = offsetBeforeKey // pretend key write never happened
                    didWriteValue = hadWrittenValue
                }
            @unknown default:
                throw JSONDecoderError.unknownJSONStrategy
            }
            
            return true
        case let data as Data:
            switch settings.dataEncodingStrategy {
            case .deferredToData:
                return false
            case .base64:
                let string = data.base64EncodedString()
                if let key = key {
                    writeKey(key)
                }
                writeValue(string)
            case .custom(let custom):
                let offsetBeforeKey = offset, hadWrittenValue = didWriteValue
                if let key = key {
                    writeKey(key)
                }
                let encoder = _JSONEncoder(codingPath: codingPath, userInfo: userInfo, data: self.data)
                try custom(data, encoder)
                if encoder.didWriteValue {
                    didWriteValue = true
                } else if !encoder.didWriteValue, !encoder.didHaveContainers, key != nil, offset - offsetBeforeKey > 0 {
                    // TODO: This is a pretty crummy hack
                    offset = offsetBeforeKey // pretend key write never happened
                    didWriteValue = hadWrittenValue
                }
            @unknown default:
                throw JSONDecoderError.unknownJSONStrategy
            }
            
            return true
        case let url as URL:
            if let key = key {
                writeKey(key)
            }
            writeValue(url.absoluteString)
            return true
        case let decimal as Decimal:
            if let key = key {
                writeKey(key)
            }
            data.insert(contentsOf: decimal.description, at: &offset)
            didWriteValue = true
            return true
        default:
            return false
        }
    }
    
    func writeComma() {
        if didWriteValue {
            data.insert(.comma, at: &offset)
        }
    }
    
    func writeKey(_ key: String) {
        writeComma()
        writeValue(transformKey(key))
        data.insert(.colon, at: &offset)
    }
    
    func transformKey(_ key: String) -> String {
        struct CustomKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            
            init?(intValue: Int) {
                nil
            }
            
            init(stringValue: String) {
                self.stringValue = stringValue
            }
        }
        
        switch settings.keyEncodingStrategy {
        case .convertToSnakeCase:
            return key.convertSnakeCasing()
        case .custom(let mapper):
            return mapper(
                codingPath + [CustomKey(stringValue: key)]
            ).stringValue
        case .useDefaultKeys:
            return key
        @unknown default:
            return key
        }
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
    
    func writeValue<F: BinaryFloatingPoint & LosslessStringConvertible>(_ value: F, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }
    
    func writeValue<F: BinaryInteger>(_ value: F, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }

    func shouldEmit<T: Encodable>(_ value: T?, wantsEmit: Bool = false) -> Bool {
        if value != nil { return true }
        switch settings.nilValueEncodingStrategy {
        case .`default`: return wantsEmit
        case .alwaysEncodeNil: return true
        case .neverEncodeNil: return false
        }
    }
    
    deinit {
        if let end = end {
            data.insert(end, at: &offset)
        }
    }
}

fileprivate struct KeyedJSONEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] { encoder.codingPath }
    
    mutating func encodeNil(forKey key: Key) throws {
        if encoder.shouldEmit(Bool?.none, wantsEmit: true) {
            encoder.writeNull(forKey: key.stringValue)
        }
    }
    
    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws   { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws  { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws    { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws   { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws  { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws  { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws  { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws   { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws  { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { if encoder.shouldEmit(value) { try self.encode(value, forKey: key) } }
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if encoder.shouldEmit(value) {
            try self.encode(value, forKey: key)
        }
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws   { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: String, forKey key: Key) throws { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Double, forKey key: Key) throws { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Float, forKey key: Key) throws  { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Int, forKey key: Key) throws    { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Int8, forKey key: Key) throws   { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Int16, forKey key: Key) throws  { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Int32, forKey key: Key) throws  { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: Int64, forKey key: Key) throws  { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: UInt, forKey key: Key) throws   { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws  { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { encoder.writeValue(value, forKey: key.stringValue) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { encoder.writeValue(value, forKey: key.stringValue) }
    
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        if try self.encoder.writeOtherValue(value, forKey: key.stringValue) {
            return
        }
        
        let offsetBeforeKey = self.encoder.offset, hadWrittenValue = self.encoder.didWriteValue
        self.encoder.writeKey(key.stringValue)
        
        let encoder = _JSONEncoder(codingPath: codingPath + [key], userInfo: self.encoder.userInfo, data: self.encoder.data)
        try value.encode(to: encoder)
        if !encoder.didWriteValue, !encoder.didHaveContainers, self.encoder.offset - offsetBeforeKey > 0 {
            // No value was written, back out the key
            self.encoder.offset = offsetBeforeKey
            self.encoder.didWriteValue = hadWrittenValue
        }
        // No need to set didWriteValue, writing the key already did
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return self.superEncoder(forKey: key).container(keyedBy: NestedKey.self)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        return self.superEncoder(forKey: key).unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        self.encoder.writeKey(SuperCodingKey.super.stringValue)  // TODO: A way to back out the key for a super encoder that never writes
        return _JSONEncoder(codingPath: codingPath + [SuperCodingKey.super], userInfo: self.encoder.userInfo, data: self.encoder.data)
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        self.encoder.writeKey(key.stringValue) // TODO: A way to back out the key for a super encoder that never writes
        return _JSONEncoder(codingPath: codingPath + [key], userInfo: self.encoder.userInfo, data: self.encoder.data)
    }
}

fileprivate struct SingleValueJSONEncodingContainer: SingleValueEncodingContainer {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] { encoder.codingPath }
    
    mutating func encodeNil() throws {
        if encoder.shouldEmit(Bool?.none, wantsEmit: true) {
            encoder.writeNull()
        }
    }
    
    mutating func encode(_ value: Bool) throws   { encoder.writeValue(value) }
    mutating func encode(_ value: String) throws { encoder.writeValue(value) }
    mutating func encode(_ value: Double) throws { encoder.writeValue(value) }
    mutating func encode(_ value: Float) throws  { encoder.writeValue(value) }
    mutating func encode(_ value: Int) throws    { encoder.writeValue(value) }
    mutating func encode(_ value: Int8) throws   { encoder.writeValue(value) }
    mutating func encode(_ value: Int16) throws  { encoder.writeValue(value) }
    mutating func encode(_ value: Int32) throws  { encoder.writeValue(value) }
    mutating func encode(_ value: Int64) throws  { encoder.writeValue(value) }
    mutating func encode(_ value: UInt) throws   { encoder.writeValue(value) }
    mutating func encode(_ value: UInt8) throws  { encoder.writeValue(value) }
    mutating func encode(_ value: UInt16) throws { encoder.writeValue(value) }
    mutating func encode(_ value: UInt32) throws { encoder.writeValue(value) }
    mutating func encode(_ value: UInt64) throws { encoder.writeValue(value) }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        if try self.encoder.writeOtherValue(value) {
            return
        }
        
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, data: self.encoder.data)
        encoder.didWriteValue = self.encoder.didWriteValue
        encoder.didHaveContainers = self.encoder.didHaveContainers
        try value.encode(to: encoder)
        self.encoder.didWriteValue = encoder.didWriteValue
        self.encoder.didHaveContainers = encoder.didHaveContainers
    }
}

fileprivate struct UnkeyedJSONEncodingContainer: UnkeyedEncodingContainer {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] { encoder.codingPath }
    var count = 0
    
    mutating func encodeNil() throws {
        if encoder.shouldEmit(Bool?.none, wantsEmit: true) {
            encoder.writeComma()
            encoder.writeNull()
        }
    }
    
    mutating func encode(_ value: Bool) throws   { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: String) throws { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Double) throws { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Float) throws  { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Int) throws    { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Int8) throws   { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Int16) throws  { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Int32) throws  { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: Int64) throws  { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: UInt) throws   { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: UInt8) throws  { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: UInt16) throws { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: UInt32) throws { encoder.writeComma(); encoder.writeValue(value) }
    mutating func encode(_ value: UInt64) throws { encoder.writeComma(); encoder.writeValue(value) }

    mutating func encode<T>(_ value: T) throws where T : Encodable {
        let offsetBeforeComma = self.encoder.offset
        self.encoder.writeComma()
        if try self.encoder.writeOtherValue(value) {
            self.count += 1
            return
        }
        
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, data: self.encoder.data)
        try value.encode(to: encoder)
        if encoder.didWriteValue || encoder.didHaveContainers {
            self.count += 1
            self.encoder.didWriteValue = true
        } else if !encoder.didWriteValue, !encoder.didHaveContainers, self.encoder.offset - offsetBeforeComma > 0 {
            self.encoder.offset = offsetBeforeComma // undo comma
        }
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return self.superEncoder().container(keyedBy: NestedKey.self)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        return self.superEncoder().unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        self.encoder.writeComma() // TODO: A way to back out the comma for a super encoder that never writes
        return _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, data: self.encoder.data)
    }
}

#if swift(<5.8)
extension UnsafeMutablePointer {
    func update(from buffer: UnsafePointer<Pointee>, count: Int) {
        self.assign(from: buffer, count: count)
    }
}
#endif
