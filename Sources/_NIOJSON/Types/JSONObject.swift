import Foundation
import NIOCore
import NIOFoundationCompat
import _JSONCore

public enum JSONObjectError: Error {
    case expectedObject
    case parsingError(JSONParserError)
}

internal func equateJSON(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
    switch (lhs, rhs) {
    case let (lhs as String, rhs as String):
        return lhs == rhs
    case let (lhs as Double, rhs as Double):
        return lhs == rhs
    case let (lhs as Int, rhs as Int):
        return lhs == rhs
    case let (lhs as Double, rhs as Int):
        return lhs == Double(rhs)
    case let (lhs as Int, rhs as Double):
        return Double(lhs) == rhs
    case let (lhs as Bool, rhs as Bool):
        return lhs == rhs
    case let (lhs as JSONObject, rhs as JSONObject):
        return lhs == rhs
    case let (lhs as JSONArray, rhs as JSONArray):
        return lhs == rhs
    case (.none, .none):
        return true
    default:
        return false
    }
}

/// A JSON Dictionary, or collection whose elements are key-value pairs.
///
/// A JSONObject is always keyed by a String and only supports a predefined set of JSON Primitives for values.
///
/// Create a new dictionary by using a dictionary literal:
///
///     var user: JSONObject = [
///         "username": "Joannis",
///         "github": "https://github.com/Joannis",
///         "creator": true
///     ]
///
/// To create a JSONObject with no key-value pairs, use an empty dictionary literal (`[:]`)
/// or use the empty initializer (`JSONObject()`)
public struct JSONObject: ExpressibleByDictionaryLiteral, Sequence, Equatable, CustomStringConvertible {
    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        let lhsKeys = lhs.keys
        let rhsKeys = rhs.keys
        
        guard lhsKeys == rhsKeys else {
            return false
        }
        
        for key in lhsKeys where !equateJSON(lhs[key], rhs[key]) {
            return false
        }
        
        return true
    }
    
    /// The raw textual (JSON formatted) representation of this JSONObject
    public internal(set) var jsonBuffer: ByteBuffer
    
    /// An internal index that keeps track of all values within this JSONObject
    var jsonDescription: JSONDescription
    
    /// A list of all top-level keys within this JSONObject
    public var keys: [String] {
        return jsonBuffer.withBytePointer { pointer in
            return self.jsonDescription.keys(inPointer: pointer, unicode: true, convertingSnakeCasing: false)
        }
    }

    public var data: Data {
        Data(buffer: jsonBuffer)
    }

    public var description: String {
        string
    }

    /// A JSON formatted String with the contents of this JSONObject
    public var string: String! {
        String(buffer: jsonBuffer)
    }
    
    /// Creates a new, empty JSONObject
    public init() {
        self.init(descriptionSize: 4_096)
    }

    /// Parses the buffer as a JSON Object and configures this JSONObject to index and represent the JSON data
    public init(data: Data) throws(JSONObjectError) {
        try self.init(buffer: ByteBuffer(data: data))
    }

    /// Parses the buffer as a JSON Object and configures this JSONObject to index and represent the JSON data
    public init(buffer: ByteBuffer) throws(JSONObjectError) {
        self.jsonBuffer = buffer
        
        do {
            self.jsonDescription = try buffer.withUnsafeReadableBytes { buffer in
                Result<JSONDescription, JSONParserError> { () throws(JSONParserError) -> JSONDescription in
                    let buffer = buffer.bindMemory(to: UInt8.self)
                    var tokenizer = JSONTokenizer(
                        bytes: buffer,
                        destination: JSONDescription()
                    )
                    try tokenizer.scanValue()
                    return tokenizer.destination
                }
            }.get()
        } catch {
            throw JSONObjectError.parsingError(error)
        }

        guard jsonDescription.topLevelType == .object else {
            throw JSONObjectError.expectedObject
        }
    }
    
    /// An internal type that creates an empty JSONObject with a predefined expected description size
    private init(descriptionSize: Int) {
        self.jsonBuffer = ByteBufferAllocator().buffer(capacity: 4_096)
        jsonBuffer.writeInteger(UInt8.curlyLeft)
        jsonBuffer.writeInteger(UInt8.curlyRight)
        
        let description = JSONDescription(size: descriptionSize)
        let context = description.describeObject(atJSONOffset: 0)
        description.complete(context, withResult: JSONToken.ObjectEnd(
            start: .init(byteIndex: 0),
            end: .init(byteIndex: 2),
            memberCount: 0
        ))

        self.jsonDescription = description
    }
    
    /// Creates a new JSONObject from a dictionary literal.
    ///
    ///     var user: JSONObject = [
    ///         "username": "Joannis",
    ///         "github": "https://github.com/Joannis",
    ///         "creator": true
    ///     ]
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init(descriptionSize: Swift.max(4096, elements.count * 128))
        
        for (key, value) in elements {
            self[key] = value
        }
    }
    
    /// Creates a new JSONObject from an already indexes JSON blob as an optimization for nested objects
    internal init(buffer: ByteBuffer, description: JSONDescription) {
        self.jsonBuffer = buffer
        self.jsonDescription = description
    }
    
    /// Removed a value at a specified index and json offset
    internal mutating func removeValue(index: Int, offset: Int) {
        let firstElement = index == 0
        let hasComma = jsonDescription.arrayObjectCount() > 1
        
        // Find the key to be removed
        let keyBounds = jsonDescription.jsonBounds(at: offset)
        var valueOffset = offset
        jsonDescription.skipIndex(atOffset: &valueOffset)
        
        // Find the value to be removed
        let valueBounds = jsonDescription.jsonBounds(at: valueOffset)
        
        // Join key and value to create a full-pair bounds
        let end = valueBounds.offset + valueBounds.length
        var bounds = (offset: keyBounds.offset, length: end - keyBounds.offset)
        
        // If there are > 1 pairs, a comma separates these pairs. This implies we need to remove one surrounding comma
        commaFinder: if hasComma {
            // The first element only has the comma after the pair
            if firstElement {
                var valueEnd = Int(bounds.offset + bounds.length)
                
                for _ in valueEnd ..< jsonBuffer.readableBytes {
                    if jsonBuffer.getInteger(at: valueEnd) == UInt8.comma {
                        // Comma included in the length
                        valueEnd = valueEnd &+ 1
                        
                        bounds.length = Int32(valueEnd) - bounds.offset
                        break commaFinder
                    }
                    
                    valueEnd = valueEnd &+ 1
                }
                
                // FatalErrors like these are justified because this is a bug in the library
                // If this was really not our fault in JSON, we still should've thrown an error
                fatalError("No comma found between elements, invalid JSON parsed/created")
            } else {
                // The last element only has a comma before the pair
                // But for simplicity, all pairs except the first have a comma before the pair
                // So we'll include that comma
                while bounds.offset > 0 {
                    bounds.offset = bounds.offset - 1
                    bounds.length = bounds.length + 1
                    
                    if jsonBuffer.getInteger(at: Int(bounds.offset)) == UInt8.comma {
                        break commaFinder
                    }
                }
                
                // FatalErrors like these are justified because this is a bug in the library
                // If this was really not our fault in JSON, we still should've thrown an error
                fatalError("No comma found between elements, invalid JSON parsed/created")
            }
        }
        
        jsonBuffer.removeBytes(atOffset: Int(bounds.offset), oldSize: Int(bounds.length))
        
        jsonDescription.removeObjectDescription(atKeyIndex: offset, jsonOffset: Int(keyBounds.offset), removedJSONLength: Int(bounds.length))
    }
    
    /// Reads the JSONValue associated with the specified key
    fileprivate func value(forKey key: String, in json: UnsafePointer<UInt8>) -> JSONValue? {
        guard let (_, offset) = jsonDescription.valueOffset(forKey: key, convertingSnakeCasing: false, in: json) else {
            return nil
        }
        
        let type = jsonDescription.type(atOffset: offset)
        switch type {
        case .object, .array:
            let indexLength = jsonDescription.indexLength(atOffset: offset)
            let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)
            
            let subDescription = jsonDescription.slice(from: offset, length: indexLength)
            subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
            let subBuffer = jsonBuffer.getSlice(at: Int(jsonBounds.offset), length: Int(jsonBounds.length))!
            
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
            return string.makeString(from: json, unicode: true)
        case .integer:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let number = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                isInteger: type == .integer
            )
            return number.makeInt(from: json)
        case .floatingNumber:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let number = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                isInteger: type == .integer
            )
            return number.makeDouble(from: json)
        case .null:
            return NSNull()
        }
    }
    
    /// Updates a key to a new value. If `nil` is provided, the value will be removed.
    ///
    /// If the key does not exist, `false` is returned. Otherwise `true` will be returned
    @discardableResult
    public mutating func updateValue(_ newValue: JSONValue?, forKey key: String) -> Bool {
        let keyResult = jsonBuffer.withBytePointer { pointer in
            return jsonDescription.keyOffset(forKey: key, convertingSnakeCasing: false, in: pointer)
        }
        
        guard let (index, offset) = keyResult else {
            return false
        }
        
        if let newValue = newValue {
            var valueOffset = offset
            jsonDescription.skipIndex(atOffset: &valueOffset)
            // rewrite value
            jsonDescription.rewrite(buffer: &jsonBuffer, to: newValue, at: valueOffset)
        } else {
            removeValue(index: index, offset: offset)
        }
        
        return true
    }

    /// Reads and writes the properties of this JSONObject by key.
    ///
    ///     var user = JSONObject()
    ///     print(user["username"]) // `nil`
    ///     user["username"] = "Joannis"
    ///     print(user["username"]) // "Joannis"
    public subscript(key: String) -> JSONValue? {
        get {
            return jsonBuffer.withBytePointer { pointer in
                return value(forKey: key, in: pointer)
            }
        }
        set {
            if updateValue(newValue, forKey: key) { return }
            guard let newValue = newValue else { return }
            
            let reader = jsonDescription
            
            // More to before the last `}`
            let objectJSONEnd = Int(jsonDescription.jsonBounds(at: 0).length - 1)
            jsonBuffer.moveWriterIndex(to: objectJSONEnd)
            
            let oldSize = jsonBuffer.writerIndex
            
            // If this is not the first entry, a comma has to preceed this pair
            if reader.arrayObjectCount() > 0 {
                jsonBuffer.writeInteger(UInt8.comma)
            }
            
            let (keyEscaped, keyCharacters) = key.escaped
            
            // Describe the position and offset of the new string
            jsonDescription.describeString(
                JSONToken.String(
                    start: JSONSourcePosition(byteIndex: jsonBuffer.writerIndex),
                    byteLength: keyCharacters.count &+ 2,
                    usesEscaping: keyEscaped
                )
            )

            // Write the JSON data of the string
            jsonBuffer.writeInteger(UInt8.quote)
            jsonBuffer.writeBytes(keyCharacters)
            jsonBuffer.writeInteger(UInt8.quote)
            
            // Write a colon after the key and before the value
            jsonBuffer.writeInteger(UInt8.colon)

            let valueIndexOffset = jsonDescription.writtenBytes
            let valueJSONOffset = jsonBuffer.writerIndex
            defer {
                let newSize = jsonBuffer.writerIndex
                let addedJSON = Int32(newSize &- oldSize)
                jsonDescription.incrementObjectCount(jsonSize: addedJSON, atValueIndexOffset: valueIndexOffset)
                jsonBuffer.writeInteger(UInt8.curlyRight)
            }

            switch newValue {
            case var object as JSONObject:
                self.jsonDescription.addNestedDescription(object.jsonDescription, at: Int32(valueJSONOffset))
                jsonBuffer.writeBuffer(&object.jsonBuffer)
            case var array as JSONArray:
                self.jsonDescription.addNestedDescription(array.jsonDescription, at: Int32(valueJSONOffset))
                jsonBuffer.writeBuffer(&array.jsonBuffer)
            case let bool as Bool:
                if bool {
                    self.jsonDescription.describeTrue(atJSONOffset: Int32(valueJSONOffset))
                    jsonBuffer.writeStaticString(boolTrue)
                } else {
                    self.jsonDescription.describeFalse(atJSONOffset: Int32(valueJSONOffset))
                    jsonBuffer.writeStaticString(boolFalse)
                }
            case let string as String:
                let (escaped, characters) = string.escaped
                
                // +2 for the quotes
                let token = JSONToken.String(
                    start: JSONSourcePosition(byteIndex: valueJSONOffset),
                    byteLength: characters.count &+ 2,
                    usesEscaping: escaped
                )

                jsonBuffer.writeInteger(UInt8.quote)
                jsonBuffer.writeBytes(characters)
                jsonBuffer.writeInteger(UInt8.quote)
                
                jsonDescription.stringFound(token)
            case let double as Double:
                jsonBuffer.writeString(String(double))
                let jsonLength = jsonBuffer.writerIndex - valueJSONOffset
                let token = JSONToken.Number(
                    start: JSONSourcePosition(byteIndex: valueJSONOffset),
                    byteLength: jsonLength,
                    isInteger: false
                )
                jsonDescription.numberFound(token)
            case let int as Int:
                jsonBuffer.writeString(String(int))
                let jsonLength = jsonBuffer.writerIndex - valueJSONOffset
                let token = JSONToken.Number(
                    start: JSONSourcePosition(byteIndex: valueJSONOffset),
                    byteLength: jsonLength,
                    isInteger: true
                )
                
                jsonDescription.numberFound(token)
            case is NSNull:
                self.jsonDescription.nullFound(
                    JSONToken.Null(
                        start: JSONSourcePosition(
                            byteIndex: jsonBuffer.writerIndex
                        )
                    )
                )
                jsonBuffer.writeStaticString(nullBytes)
            default:
                fatalError("Unsupported value \(newValue)")
            }
        }
    }
    
    public func makeIterator() -> JSONObjectIterator {
        return JSONObjectIterator(object: self)
    }
}

public struct JSONObjectIterator: IteratorProtocol {
    private let object: JSONObject
    private let keys: [String]
    private var index: Int
    
    init(object: JSONObject) {
        self.object = object
        self.keys = object.keys
        self.index = 0
    }
    
    public mutating func next() -> (String, JSONValue)? {
        guard index < keys.count else { return nil }
        defer { index += 1 }
        let key = keys[index]
        let value = object.jsonBuffer.withBytePointer { pointer in
            return object.value(forKey: key, in: pointer)
        }
        
        if let value = value {
            return (key, value)
        }
        
        return nil
    }
}
