import Foundation

public struct JSONObject: ExpressibleByDictionaryLiteral {
    let buffer: Buffer
    var slice: UnsafeRawBufferPointer {
        return UnsafeRawBufferPointer(start: buffer.pointer, count: buffer.used)
    }
    var description: JSONDescription
    var reader: ReadOnlyJSONDescription { return description.readOnly }
    
    public var data: Data {
        return Data(bytes: buffer.pointer, count: buffer.used)
    }
    
    public var string: String! {
        return String(data: data, encoding: .utf8)
    }

    public init(data: Data) throws {
        self.buffer = Buffer(copying: data)

        let size = data.count
        
        let description = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            return try JSONParser.scanValue(fromPointer: pointer, count: size)
        }
        self.description = description

        guard reader.type == .object else {
            throw JSONError.expectedObject
        }
    }
    
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.buffer = Buffer.allocate(size: 2)
        
        let writePointer = self.buffer.pointer.bindMemory(to: UInt8.self, capacity: 2)
        writePointer[0] = .curlyLeft
        writePointer[1] = .curlyRight
        self.buffer.used = 2
        self.description = JSONDescription()
        
        let partialObject = description.describeObject(atOffset: 0)
        let result = _ArrayObjectDescription(count: 0, byteCount: 2)
        description.complete(partialObject, withResult: result)
        
        for (key, value) in elements {
            self[key] = value
        }
    }
    
    internal init(buffer: Buffer, description: JSONDescription) {
        self.buffer = buffer
        self.description = description
    }

    public subscript(key: String) -> JSONValue? {
        get {
            let pointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
            guard
                let (_, offset) = reader.valueOffset(forKey: key, convertingSnakeCasing: false, in: pointer),
                let type = reader.type(atOffset: offset)
            else {
                return nil
            }

            switch type {
            case .object, .array:
                let indexLength = reader.indexLength(atOffset: offset)
                let jsonBounds = reader.dataBounds(at: offset)
                
                var subDescription = description.slice(from: offset, length: indexLength)
                subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
                let subBuffer = buffer.slice(bounds: jsonBounds)
                
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
                return reader.dataBounds(at: offset).makeString(from: pointer, escaping: false, unicode: true)
            case .stringWithEscaping:
                return reader.dataBounds(at: offset).makeString(from: pointer, escaping: true, unicode: true)
            case .integer:
                return reader.dataBounds(at: offset).makeInt(from: pointer)
            case .floatingNumber:
                return reader.dataBounds(at: offset).makeDouble(from: pointer, floating: true)
            case .null:
                return NSNull()
            }
        }
        set {
            let bytePointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
            if let (index, offset) = reader.keyOffset(forKey: key, convertingSnakeCasing: false, in: bytePointer) {
                if let newValue = newValue {
                    var valueOffset = offset
                    reader.skip(withOffset: &valueOffset)
                    // rewrite value
                    description.rewrite(buffer: buffer, to: newValue, at: valueOffset)
                    if let string = self["profile"]["username"] as? String, string  != "Henk" && string != "Joannis" {
                        print("WTF")
                    }
                } else {
                    let firstElement = index == 0
                    let hasComma = reader.arrayObjectCount() > 1
                    
                    let keyBounds = reader.jsonBounds(at: offset)
                    var valueOffset = offset
                    reader.skip(withOffset: &valueOffset)
                    let valueBounds = reader.jsonBounds(at: valueOffset)
                    
                    let end = valueBounds.offset &+ valueBounds.length
                    var bounds = Bounds(offset: keyBounds.offset, length: end &- keyBounds.offset)
                    
                    commaFinder: if hasComma {
                        let pointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
                        
                        if firstElement {
                            var valueEnd = bounds.offset &+ bounds.length
                            
                            for _ in valueEnd ..< buffer.size {
                                if pointer[valueEnd] == .comma {
                                    // Comma included in the length
                                    valueEnd = valueEnd &+ 1
                                    
                                    bounds.length = valueEnd &- valueBounds.offset
                                    break commaFinder
                                }
                                
                                valueEnd = valueEnd &+ 1
                            }
                            
                            fatalError("No comma found between elements, invalid JSON parsed/created")
                        } else {
                            while valueBounds.offset > 0 {
                                bounds.offset = bounds.offset &- 1
                                bounds.length = bounds.length &+ 1
                                
                                if pointer[valueBounds.offset] == .comma {
                                    break commaFinder
                                }
                            }
                            
                            fatalError("No comma found between elements, invalid JSON parsed/created")
                        }
                    }
                    
                    
                    buffer.prepareRewrite(offset: bounds.offset, oldSize: bounds.length, newSize: 0)
                    
                    description.removeObjectDescription(at: offset, jsonOffset: keyBounds.offset, removedJSONLength: bounds.length)
                }
            } else if let newValue = newValue {
                let reader = description.readOnly
                
                let insertOffset = reader.dataBounds(at: 0).length - 1
                
                func writeKey(valueSize: Int) -> (UnsafeMutableRawPointer, Int) {
                    var insertPointer: UnsafeMutableRawPointer
                    
                    var keyBytes = [UInt8]()
                    let escapedKey = key.escapingAppend(to: &keyBytes)
                    
                    // 3 = `"` x2 and `:` x1
                    var extra = keyBytes.count + 3 + valueSize
                    
                    let keyBounds: Bounds
                    
                    if reader.arrayObjectCount() > 0 {
                        // This is safe since we override `}`
                        extra += 1
                        buffer.expandBuffer(to: buffer.used + extra)
                        // 2 + for the `,"` start
                        keyBounds = Bounds(offset: 2 &+ insertOffset, length: keyBytes.count)
                        // Make the pointer after possible reallocation reinitialized the pointer
                        insertPointer = buffer.pointer + insertOffset
                        insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .comma
                        insertPointer += 1
                    } else {
                        buffer.expandBuffer(to: buffer.used + extra)
                        // 1 + for the `"` start
                        keyBounds = Bounds(offset: 1 &+ insertOffset, length: keyBytes.count)
                        // Make the pointer after possible reallocation reinitialized the pointer
                        insertPointer = buffer.pointer + insertOffset
                    }
                    
                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .quote
                    insertPointer += 1
                    
                    assert(buffer.pointer.distance(to: insertPointer) + keyBytes.count <= buffer.size)
                    memcpy(insertPointer, keyBytes, keyBytes.count)
                    description.describeString(keyBounds, escaped: escapedKey)
                    
                    insertPointer += keyBytes.count
                    
                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .quote
                    insertPointer += 1
                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .colon
                    insertPointer += 1
                    
                    let jsonValueOffset = insertOffset &+ extra &- valueSize
                    assert(jsonValueOffset == buffer.pointer.distance(to: insertPointer))
                    return (insertPointer, jsonValueOffset)
                }
                
                let indexOffset = description.used
                
                func write(_ string: String) -> Bounds {
                    let (pointer, jsonOffset) = writeKey(valueSize: 4)
                    
                    let string = [UInt8](string.utf8)
                    memcpy(pointer, string, string.count)
                    pointer.advanced(by: string.count).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
                    buffer.used = jsonOffset &+ string.count &+ 3 // + 1 for the `}` and 2x `"`
                    return Bounds(offset: jsonOffset, length: string.count)
                }
                
                let oldSize = buffer.size
                defer {
                    let newSize = buffer.size
                    let addedJSON = newSize &- oldSize
                    description.incrementObjectCount(jsonSize: addedJSON, atValueOffset: indexOffset)
                }
                
                switch newValue {
                case let object as JSONObject:
                    let valueSize = object.buffer.used
                    let (pointer, jsonOffset) = writeKey(valueSize: valueSize)
                    self.description.addNestedDescription(object.description, at: jsonOffset)
                    
                    assert(buffer.pointer.distance(to: pointer) + valueSize <= buffer.size)
                    memcpy(pointer, object.buffer.pointer, valueSize)
                    pointer.advanced(by: valueSize).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
                    buffer.used = jsonOffset &+ valueSize &+ 1 // + 1 for the `}`
                    
//                    valueBounds = Bounds(offset: jsonOffset, length: valueBytes.count)
//                    fatalError()
//                case .array:
//                    valueBounds = Bounds(offset: jsonOffset, length: valueBytes.count)
//                    fatalError()
                case let bool as Bool:
                    if bool {
                        let (pointer, jsonOffset) = writeKey(valueSize: 4)
                        let valueBounds = Bounds(offset: jsonOffset, length: 4)
                        description.describeTrue(at: valueBounds.offset)
                        memcpy(pointer, boolTrue, 4)
                        pointer.advanced(by: 4).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
                        buffer.used = jsonOffset &+ 4 &+ 1 // + 1 for the `}`
                    } else {
                        let (pointer, jsonOffset) = writeKey(valueSize: 5)
                        let valueBounds = Bounds(offset: jsonOffset, length: 5)
                        description.describeFalse(at: valueBounds.offset)
                        memcpy(pointer, boolFalse, 5)
                        pointer.advanced(by: 5).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
                        buffer.used = jsonOffset &+ 5 &+ 1 // + 1 for the `}`
                    }
                case let string as String:
                    var valueBytes = [UInt8]()
                    valueBytes.append(.quote)
                    let escaped = string.escapingAppend(to: &valueBytes)
                    valueBytes.append(.quote)
                    
                    let (pointer, jsonOffset) = writeKey(valueSize: valueBytes.count)
                    memcpy(pointer, valueBytes, valueBytes.count)
                    
                    // Strings are compared and bounds start after the starting `"` and stop before the ending `"`
                    // Therefore it's offset by 1 `"`
                    let valueBounds = Bounds(offset: jsonOffset &+ 1, length: valueBytes.count &- 2)
                    buffer.used = jsonOffset &+ valueBytes.count &+ 1 // + 1 for the `}`
                    description.describeString(valueBounds, escaped: escaped)
                    pointer.advanced(by: valueBytes.count).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
                case let double as Double:
                    let valueBounds = write(String(double))
                    description.describeNumber(valueBounds, floatingPoint: true)
                case let int as Int8:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as Int16:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as Int32:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as Int64:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as UInt:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as UInt8:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as UInt16:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as UInt32:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case let int as UInt64:
                    let valueBounds = write(String(int))
                    description.describeNumber(valueBounds, floatingPoint: false)
                case is NSNull:
                    let (pointer, jsonOffset) = writeKey(valueSize: 4)
                    let valueBounds = Bounds(offset: jsonOffset, length: 4)
                    description.describeNull(at: valueBounds.offset)
                    memcpy(pointer, nullBytes, 5)
                    pointer.advanced(by: 5).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
                    buffer.used = jsonOffset &+ 5
                default:
                    fatalError("Unsupported value \(newValue)")
                }
            }
        }
    }
}
