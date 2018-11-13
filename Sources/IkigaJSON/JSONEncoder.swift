import Foundation

public struct JSONEncoderSettings {
    public init() {}
    
    public var userInfo = [CodingUserInfoKey : Any]()
    public var encodeNilAsNull = false
}

public struct IkigaJSONEncoder {
    public var userInfo = [CodingUserInfoKey : Any]()
    public var settings = JSONEncoderSettings()
    
    public init() {}
    
    public func encode<E: Encodable>(_ value: E) throws -> Data {
        let encoder = _JSONEncoder(userInfo: userInfo, settings: settings)
        try value.encode(to: encoder)
        encoder.writeEnd()
        return encoder.data
    }
}

fileprivate let null: [UInt8] = [.n, .u, .l, .l]
fileprivate let boolTrue: [UInt8] = [.t, .r, .u, .e]
fileprivate let boolFalse: [UInt8] = [.f, .a, .l, .s, .e]

fileprivate final class _JSONEncoder: Encoder {
    var codingPath: [CodingKey]
    var data = Data()
    var end: UInt8?
    var superEncoder: _JSONEncoder?
    var didWriteValue = false
    var userInfo: [CodingUserInfoKey : Any]
    var settings: JSONEncoderSettings
    
    func writeEnd() {
        if let end = end {
            data.append(end)
            self.end = nil
        }
    }
    
    init(codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey : Any], settings: JSONEncoderSettings) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.settings = settings
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        data.append(.curlyLeft)
        end = .curlyRight
        
        let container = KeyedJSONEncodingContainer<Key>(encoder: self)
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        data.append(.squareLeft)
        end = .squareRight
        
        return UnkeyedJSONEncodingContainer(encoder: self)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return SingleValueJSONEncodingContainer(encoder: self)
    }
    
    func writeValue(_ string: String) {
        data.append(.quote)
        data.append(string, count: string.utf8.count)
        data.append(.quote)
    }
    
    func writeNull() {
        data.append(contentsOf: null)
    }
    
    func writeValue(_ value: Bool) {
        data.append(contentsOf: value ? boolTrue : boolFalse)
    }
    
    func writeValue(_ value: Double) {
        // TODO: Optimize
        let number = String(value)
        data.append(number, count: number.count)
    }
    
    func writeValue(_ value: Float) {
        // TODO: Optimize
        let number = String(value)
        data.append(number, count: number.count)
    }
    
    func writeComma() {
        if didWriteValue {
            data.append(.comma)
        } else {
            didWriteValue = true
        }
    }
    
    func writeKey(_ key: String) {
        writeComma()
        writeValue(key)
        data.append(.colon)
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
        data.append(number, count: number.count)
    }
    
    deinit {
        if let end = end {
            data.append(end)
        }
        
        if let superEncoder = superEncoder {
            superEncoder.data.append(self.data)
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
