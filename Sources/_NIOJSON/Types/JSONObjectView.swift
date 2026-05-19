import Foundation
import NIOCore
import NIOFoundationCompat
import _JSONCore

public struct JSONObjectView: ~Copyable, ~Escapable {
    /// The raw textual (JSON formatted) representation of this JSONObject
    private let span: Span<UInt8>
    
    /// An internal index that keeps track of all values within this JSONObject
    var jsonDescription: JSONDescription
    
    /// A list of all top-level keys within this JSONObject
    public var keys: [String] {
        return self.jsonDescription.keys(
            in: span, unicode: true, convertingSnakeCasing: false)
    }
    
    @safe
    public var data: Data {
        unsafe span.withUnsafeBytes { buffer in
            unsafe Data(buffer)
        }
    }
    
    /// A JSON formatted String with the contents of this JSONObject
    
    @available(macOS 26.0, *)
    public var string: String {
        get throws {
            let span = try UTF8Span(validating: span)
            return String(copying: span)
        }
    }
    
    /// Parses the buffer as a JSON Object and configures this JSONObject to index and represent the JSON data
    @_lifetime(borrow span)
    public init(span: Span<UInt8>) throws(JSONObjectError) {
        let jsonDescription: JSONDescription
        do {
            jsonDescription = try Result<JSONDescription, JSONParserError> { () throws(JSONParserError) -> JSONDescription in
                var tokenizer = JSONTokenizer(
                    span: span,
                    destination: JSONDescription()
                )
                try tokenizer.scanValue()
                return tokenizer.destination
            }.get()
        } catch {
            throw JSONObjectError.parsingError(error)
        }
        
        guard jsonDescription.topLevelType == .object else {
            throw JSONObjectError.expectedObject
        }
        
        self.span = span
        self.jsonDescription = jsonDescription
    }
    
    @_lifetime(borrow span)
    internal init(span: Span<UInt8>, jsonDescription: JSONDescription) throws(JSONObjectError) {
        guard jsonDescription.topLevelType == .object else {
            throw JSONObjectError.expectedObject
        }
        
        self.span = span
        self.jsonDescription = jsonDescription
    }
    
    public func string(forKey key: String) throws -> String? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span)
        else {
            return nil
        }
        
        let type = jsonDescription.type(atOffset: offset)
        guard type == .string else {
            return nil
        }
        
        let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
        let string = JSONToken.String(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            usesEscaping: type == .stringWithEscaping
        )
        return string.makeString(from: span, unicode: true)
    }
    
    public func integer(forKey key: String) throws -> Int? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span)
        else {
            return nil
        }
        
        let type = jsonDescription.type(atOffset: offset)
        guard type == .integer else {
            return nil
        }
        
        let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
        let number = JSONToken.Number(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            isInteger: type == .integer
        )
        return number.makeInt(from: span)
    }
    
    public func double(forKey key: String) throws -> Double? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span)
        else {
            return nil
        }
        
        let type = jsonDescription.type(atOffset: offset)
        guard type == .floatingNumber else {
            return nil
        }
        let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
        let number = JSONToken.Number(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            isInteger: type == .integer
        )
        return number.makeDouble(from: span)
    }
    
    public func boolean(forKey key: String) throws -> Bool? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span)
        else {
            return nil
        }
        
        switch jsonDescription.type(atOffset: offset) {
        case .object, .array, .string, .stringWithEscaping, .integer, .floatingNumber, .null:
            return nil
        case .boolTrue:
            return true
        case .boolFalse:
            return false
        }
    }
    
    public func isNull(forKey key: String) throws -> Bool {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span)
        else {
            return false
        }
        
        return jsonDescription.type(atOffset: offset) == .null
    }
    
    public func withObjectView<T, E: Error>(
        forKey key: String,
        perform: (borrowing JSONObjectView) throws(E) -> T
    ) throws -> T? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span),
            jsonDescription.type(atOffset: offset) == .object
        else {
            return nil
        }
        
        let indexLength = jsonDescription.indexLength(atOffset: offset)
        let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)
        
        let subDescription = jsonDescription.slice(from: offset, length: indexLength)
        subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
        
        let subSpan = span.extracting(Int(jsonBounds.offset) ..< Int(jsonBounds.offset + jsonBounds.length))
        let view = try JSONObjectView(span: subSpan, jsonDescription: subDescription)
        return try perform(view)
    }
    
    public func withArrayView<T, E: Error>(
        forKey key: String,
        perform: (borrowing JSONArrayView) throws(E) -> T
    ) throws -> T? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span),
            jsonDescription.type(atOffset: offset) == .array
        else {
            return nil
        }
        
        let indexLength = jsonDescription.indexLength(atOffset: offset)
        let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)
        
        let subDescription = jsonDescription.slice(from: offset, length: indexLength)
        subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
        
        let subSpan = span.extracting(Int(jsonBounds.offset) ..< Int(jsonBounds.offset + jsonBounds.length))
        let view = try JSONArrayView(span: subSpan, jsonDescription: subDescription)
        return try perform(view)
    }
    
    /// Reads the JSONValue associated with the specified key
    fileprivate func value(forKey key: String, in span: Span<UInt8>) -> JSONValue? {
        guard
            let (_, offset) = jsonDescription.valueOffset(
                forKey: key, convertingSnakeCasing: false, in: span)
        else {
            return nil
        }
        
        let type = jsonDescription.type(atOffset: offset)
        switch type {
        case .object, .array:
            let indexLength = jsonDescription.indexLength(atOffset: offset)
            let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)
            
            let subDescription = jsonDescription.slice(from: offset, length: indexLength)
            subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
            let subSpan = span.extracting(Int(jsonBounds.offset) ..< Int(jsonBounds.offset + jsonBounds.length))
            var subBuffer = ByteBuffer()
            unsafe subBuffer.writeBytes(subSpan.bytes)
            
            if type == .object {
                return JSONObject(buffer: subBuffer, description: subDescription)
            } else {
                return JSONArray(buffer: subBuffer, description: subDescription)
            }
        case .boolTrue:
            return true
        case .boolFalse:
            return false
        case .string, .stringWithEscaping:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let string = JSONToken.String(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                usesEscaping: type == .stringWithEscaping
            )
            return string.makeString(from: span, unicode: true)
        case .integer:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let number = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                isInteger: type == .integer
            )
            return number.makeInt(from: span)
        case .floatingNumber:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let number = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                isInteger: type == .integer
            )
            return number.makeDouble(from: span)
        case .null:
            return NSNull()
        }
    }
    
    /// Reads and writes the properties of this JSONObject by key.
    ///
    ///     var user = JSONObject()
    ///     print(user["username"]) // `nil`
    ///     user["username"] = "Joannis"
    ///     print(user["username"]) // "Joannis"
    public subscript(key: String) -> JSONValue? {
        return value(forKey: key, in: span)
    }
}
