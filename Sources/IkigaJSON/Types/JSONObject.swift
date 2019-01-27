import Foundation
import NIO

public struct JSONObject: ExpressibleByDictionaryLiteral {
    public private(set) var jsonBuffer: ByteBuffer
    var description: JSONDescription
    
    public var data: Data {
        return jsonBuffer.withUnsafeReadableBytes { buffer in
            return Data(buffer: buffer.bindMemory(to: UInt8.self))
        }
    }
    
    public var string: String! {
        return String(data: data, encoding: .utf8)
    }
    
    public init() {
        self.jsonBuffer = allocator.buffer(capacity: 4_096)
        jsonBuffer.write(integer: UInt8.curlyLeft)
        jsonBuffer.write(integer: UInt8.curlyRight)
        
        var description = JSONDescription()
        let partialObject = description.describeObject(atJSONOffset: 0)
        let result = _ArrayObjectDescription(valueCount: 0, jsonByteCount: 2)
        description.complete(partialObject, withResult: result)
        
        self.description = description
    }

    public init(buffer: ByteBuffer) throws {
        self.jsonBuffer = buffer
        
        self.description = try buffer.withUnsafeReadableBytes { buffer in
            let buffer = buffer.bindMemory(to: UInt8.self)
            return try JSONParser.scanValue(fromPointer: buffer.baseAddress!, count: buffer.count)
        }

        guard description.topLevelType == .object else {
            throw JSONError.expectedObject
        }
    }
    
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init()
        
        for (key, value) in elements {
            self[key] = value
        }
    }
    
    internal init(buffer: ByteBuffer, description: JSONDescription) {
        self.jsonBuffer = buffer
        self.description = description
    }
    
    internal mutating func removeValue(index: Int, offset: Int) {
        let firstElement = index == 0
        let hasComma = description.arrayObjectCount() > 1
        
        // Find the key to be removed
        let keyBounds = description.jsonBounds(at: offset)
        var valueOffset = offset
        description.skipIndex(atOffset: &valueOffset)
        
        // Find the value to be removed
        let valueBounds = description.jsonBounds(at: valueOffset)
        
        // Join key and value to create a full-pair bounds
        let end = valueBounds.offset + valueBounds.length
        var bounds = Bounds(offset: keyBounds.offset, length: end - keyBounds.offset)
        
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
        
        description.removeObjectDescription(atKeyIndex: offset, jsonOffset: Int(keyBounds.offset), removedJSONLength: Int(bounds.length))
    }
    
    private func value(forKey key: String, in json: UnsafePointer<UInt8>) -> JSONValue? {
        guard let (_, offset) = description.valueOffset(forKey: key, convertingSnakeCasing: false, in: json) else {
            return nil
        }
        
        let type = description.type(atOffset: offset)
        switch type {
        case .object, .array:
            let indexLength = description.indexLength(atOffset: offset)
            let jsonBounds = description.dataBounds(atIndexOffset: offset)
            
            var subDescription = description.slice(from: offset, length: indexLength)
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
        case .string:
            return description.dataBounds(atIndexOffset: offset).makeString(from: json, escaping: false, unicode: true)
        case .stringWithEscaping:
            return description.dataBounds(atIndexOffset: offset).makeString(from: json, escaping: true, unicode: true)
        case .integer:
            return description.dataBounds(atIndexOffset: offset).makeDouble(from: json, floating: false)
        case .floatingNumber:
            return description.dataBounds(atIndexOffset: offset).makeDouble(from: json, floating: true)
        case .null:
            return NSNull()
        }
    }
    
    public mutating func updateValue(_ newValue: JSONValue?, forKey key: String) -> Bool {
        let keyResult = jsonBuffer.withBytePointer { pointer in
            return description.keyOffset(forKey: key, convertingSnakeCasing: false, in: pointer)
        }
        
        guard let (index, offset) = keyResult else {
            return false
        }
        
        if let newValue = newValue {
            var valueOffset = offset
            description.skipIndex(atOffset: &valueOffset)
            // rewrite value
            description.rewrite(buffer: &jsonBuffer, to: newValue, at: valueOffset)
        } else {
            removeValue(index: index, offset: offset)
        }
        
        return true
    }

    public subscript(key: String) -> JSONValue? {
        get {
            return jsonBuffer.withBytePointer { pointer in
                return value(forKey: key, in: pointer)
            }
        }
        set {
            if updateValue(newValue, forKey: key) { return }
            guard let newValue = newValue else { return }
            
            let reader = description
            
            // More to before the last `}`
            let objectJSONEnd = Int(description.jsonBounds(at: 0).length - 1)
            jsonBuffer.moveWriterIndex(to: objectJSONEnd)
            
            let oldSize = jsonBuffer.writerIndex
            
            // Note where the key is located
            let keyIndexOffset = description.buffer.writerIndex
            
            // If this is not the first entry, a comma has to preceed this pair
            if reader.arrayObjectCount() > 0 {
                jsonBuffer.write(integer: UInt8.comma)
            }
            
            let (keyEscaped, keyCharacters) = key.escaped
            
            // Describe the position and offset of the new string
            let bounds = Bounds(offset: Int32(jsonBuffer.writerIndex), length: Int32(keyCharacters.count) + 2)
            description.describeString(at: bounds, escaped: keyEscaped)
            
            // Write the JSON data of the string
            jsonBuffer.write(integer: UInt8.quote)
            jsonBuffer.write(bytes: keyCharacters)
            jsonBuffer.write(integer: UInt8.quote)
            
            // Write a colon after the key and before the value
            jsonBuffer.write(integer: UInt8.colon)

            let valueIndexOffset = description.buffer.writerIndex
            let valueJSONOffset = Int32(jsonBuffer.writerIndex)
            defer {
                let newSize = jsonBuffer.writerIndex
                let addedJSON = Int32(newSize &- oldSize)
                description.incrementObjectCount(jsonSize: addedJSON, atValueIndexOffset: valueIndexOffset)
                jsonBuffer.write(integer: UInt8.curlyRight)
            }

            switch newValue {
            case var object as JSONObject:
                self.description.addNestedDescription(object.description, at: valueJSONOffset)
                jsonBuffer.write(buffer: &object.jsonBuffer)
            case var array as JSONArray:
                self.description.addNestedDescription(array.description, at: valueJSONOffset)
                jsonBuffer.write(buffer: &array.jsonBuffer)
            case let bool as Bool:
                if bool {
                    self.description.describeTrue(atJSONOffset: valueJSONOffset)
                    jsonBuffer.write(staticString: boolTrue)
                } else {
                    self.description.describeFalse(atJSONOffset: valueJSONOffset)
                    jsonBuffer.write(staticString: boolFalse)
                }
            case let string as String:
                let (escaped, characters) = string.escaped
                
                // +2 for the quotes
                let valueBounds = Bounds(offset: valueJSONOffset, length: Int32(characters.count + 2))
                
                jsonBuffer.write(integer: UInt8.quote)
                jsonBuffer.write(bytes: characters)
                jsonBuffer.write(integer: UInt8.quote)
                
                description.describeString(at: valueBounds, escaped: escaped)
            case let double as Double:
                jsonBuffer.write(string: String(double))
                let jsonLength = Int32(jsonBuffer.writerIndex) - valueJSONOffset
                let valueBounds = Bounds(offset: valueJSONOffset, length: jsonLength)
                
                description.describeNumber(at: valueBounds, floatingPoint: true)
            case let int as Int:
                jsonBuffer.write(string: String(int))
                let jsonLength = Int32(jsonBuffer.writerIndex) - valueJSONOffset
                let valueBounds = Bounds(offset: valueJSONOffset, length: jsonLength)
                
                description.describeNumber(at: valueBounds, floatingPoint: false)
            case is NSNull:
                self.description.describeNull(atJSONOffset: valueJSONOffset)
                jsonBuffer.write(staticString: nullBytes)
            default:
                fatalError("Unsupported value \(newValue)")
            }
        }
    }
}
