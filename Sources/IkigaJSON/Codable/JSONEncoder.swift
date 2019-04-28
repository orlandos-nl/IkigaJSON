import Foundation
import NIO

#if os(Linux) && !swift(>=4.2.2) && !compiler(>=5.0)
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

    /// The manner of expanding internal buffers for growing encoding demands
    public var bufferExpansionMode = ExpansionMode.normal

    public var expectedJSONSize = 16_384
    
    /// This userInfo is accessible by the Eecodable types that are being encoded
    public var userInfo = [CodingUserInfoKey : Any]()
    
    /// If a `nil` value is found, setting this to `true` will encode `null`. Otherwise the key is omitted.
    ///
    /// This is `false` by default
    public var encodeNilAsNull = false

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
public enum ExpansionMode {
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
final class AutoDeallocatingPointer {
    var pointer: UnsafeMutablePointer<UInt8>
    private(set) var totalSize: Int
    let expansionMode: ExpansionMode
    let expectedSize: Int
    var offset = 0
    
    init(expectedSize: Int, expansionMode: ExpansionMode) {
        self.pointer = .allocate(capacity: expectedSize)
        self.expansionMode = expansionMode
        self.totalSize = expectedSize
        self.expectedSize = expectedSize
    }
    
    /// Expands the buffer to it's new absolute size and copies the usedCapacity to the new buffer.
    ///
    /// Any data after the userCapacity is lost
    func expand(to count: Int, usedCapacity size: Int) {
        let new = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        new.assign(from: pointer, count: size)
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
    let data: AutoDeallocatingPointer
    private(set) var offset: Int {
        get {
            return data.offset
        }
        set {
            data.offset = newValue
        }
    }
    var end: UInt8?
    var didWriteValue = false
    var userInfo: [CodingUserInfoKey : Any]
    var settings: JSONEncoderSettings
    
    func writeEnd() {
        if let end = end {
            data.insert(end, at: &offset)
            self.end = nil
        }
    }

    init(codingPath: [CodingKey], userInfo: [CodingUserInfoKey : Any], settings: JSONEncoderSettings, data: AutoDeallocatingPointer) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.settings = settings
        self.data = data
    }
    
    init(userInfo: [CodingUserInfoKey : Any], settings: JSONEncoderSettings) {
        self.codingPath = []
        self.userInfo = userInfo
        self.settings = settings
        data = AutoDeallocatingPointer(expectedSize: settings.expectedJSONSize, expansionMode: settings.bufferExpansionMode)
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

    // Returns `true` if it was handled, false if it needs to be deferred
    func writeOtherValue<T: Encodable>(_ value: T) throws -> Bool {
        switch value {
        case let date as Date:
            switch settings.dateEncodingStrategy {
            case .deferredToDate:
                return false
            case .secondsSince1970:
                writeValue(date.timeIntervalSince1970)
            case .millisecondsSince1970:
                writeValue(date.timeIntervalSince1970 * 1000)
            case .iso8601:
                let string: String

                if #available(OSX 10.12, iOS 11, *) {
                    string = isoFormatter.string(from: date)
                } else {
                    string = isoDateFormatter.string(from: date)
                }

                writeValue(string)
            case .formatted(let formatter):
                let string = formatter.string(from: date)
                writeValue(string)
            case .custom(let custom):
                let encoder = _JSONEncoder(codingPath: codingPath, userInfo: userInfo, settings: settings, data: self.data)
                try custom(date, encoder)
            }

            return true
        case let data as Data:
            switch settings.dataEncodingStrategy {
            case .deferredToData:
                return false
            case .base64:
                let string = data.base64EncodedString()
                writeValue(string)
            case .custom(let custom):
                let encoder = _JSONEncoder(codingPath: codingPath, userInfo: userInfo, settings: settings, data: self.data)
                try custom(data, encoder)
            }

            return true
        default:
            return false
        }
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

    func writeValue(_ value: String?) {
        if let value = value {
            writeValue(value)
        } else {
            writeNull()
        }
    }

    func writeValue(_ value: String?, forKey key: String) {
        if let value = value {
            writeValue(value, forKey: key)
        } else {
            writeNull(forKey: key)
        }
    }
    
    func writeValue(_ value: Bool, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }

    func writeValue(_ value: Bool?) {
        if let value = value {
            writeValue(value)
        } else {
            writeNull()
        }
    }

    func writeValue(_ value: Bool?, forKey key: String) {
        if let value = value {
            writeValue(value, forKey: key)
        } else {
            writeNull(forKey: key)
        }
    }
    
    func writeValue(_ value: Double, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }

    func writeValue(_ value: Double?) {
        if let value = value {
            writeValue(value)
        } else {
            writeNull()
        }
    }

    func writeValue(_ value: Double?, forKey key: String) {
        if let value = value {
            writeValue(value, forKey: key)
        } else {
            writeNull(forKey: key)
        }
    }
    
    func writeValue(_ value: Float, forKey key: String) {
        writeKey(key)
        writeValue(value)
    }

    func writeValue(_ value: Float?) {
        if let value = value {
            writeValue(value)
        } else {
            writeNull()
        }
    }

    func writeValue(_ value: Float?, forKey key: String) {
        if let value = value {
            writeValue(value, forKey: key)
        } else {
            writeNull(forKey: key)
        }
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

    func writeValue<F: BinaryInteger>(_ value: F?, forKey key: String) {
        if let value = value {
            writeKey(key)
            writeValue(value)
        } else if settings.encodeNilAsNull {
            writeNull(forKey: key)
        }
    }

    func writeValue<F: BinaryInteger>(_ value: F?) {
        if let value = value {
            writeValue(value)
        } else if settings.encodeNilAsNull {
            writeNull()
        }
    }
    
    deinit {
        if let end = end {
            data.insert(end, at: &offset)
        }
//
//        if let superEncoder = superEncoder {
//            superEncoder.data.insert(contentsOf: self.data, count: self.offset, at: &superEncoder.offset)
//        }
    }
}

fileprivate struct KeyedJSONEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: _JSONEncoder
    var codingPath: [CodingKey] {
        return encoder.codingPath
    }
    
    mutating func encodeNil(forKey key: Key) throws {
        if encoder.settings.encodeNilAsNull {
            encoder.writeNull(forKey: key.stringValue)
        }
    }

    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
    }

    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws {
        encoder.writeValue(value, forKey: key.stringValue)
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

        if try self.encoder.writeOtherValue(value) {
            return
        }

        let encoder = _JSONEncoder(codingPath: codingPath + [key], userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
        try value.encode(to: encoder)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        self.encoder.writeKey(key.stringValue)
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
        return encoder.container(keyedBy: keyType)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        self.encoder.writeKey(key.stringValue)
        let encoder = _JSONEncoder(codingPath: codingPath + [key], userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
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
        if encoder.settings.encodeNilAsNull {
            encoder.writeNull()
        }
    }

    mutating func encodeIfPresent(_ value: Bool?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: String?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Double?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Float?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int8?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int16?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int32?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int64?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt8?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt16?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt32?) throws {encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt64?) throws {encoder.writeComma()
        encoder.writeValue(value)
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
        if try self.encoder.writeOtherValue(value) {
            return
        }
        
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
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
        if encoder.settings.encodeNilAsNull {
            encoder.writeComma()
            encoder.writeNull()
        }
    }

    mutating func encodeIfPresent(_ value: Bool?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: String?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Double?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Float?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int8?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int16?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int32?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: Int64?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt8?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt16?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt32?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }

    mutating func encodeIfPresent(_ value: UInt64?) throws {
        encoder.writeComma()
        encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Bool) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: String) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Double) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Float) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int8) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int16) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int32) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: Int64) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt8) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt16) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt32) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode(_ value: UInt64) throws {
        encoder.writeComma()
        self.encoder.writeValue(value)
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        self.encoder.writeComma()

        if try self.encoder.writeOtherValue(value) {
            return
        }

        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
        try value.encode(to: encoder)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        self.encoder.writeComma()
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
        return encoder.container(keyedBy: keyType)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        self.encoder.writeComma()
        let encoder = _JSONEncoder(codingPath: codingPath, userInfo: self.encoder.userInfo, settings: self.encoder.settings, data: self.encoder.data)
        return encoder.unkeyedContainer()
    }
    
    mutating func superEncoder() -> Encoder {
        return encoder
    }
}
