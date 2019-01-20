//import Foundation
//
//public struct JSONObject: ExpressibleByDictionaryLiteral {
//    let buffer: Buffer
//    var slice: UnsafeRawBufferPointer {
//        return UnsafeRawBufferPointer(start: buffer.pointer, count: buffer.used)
//    }
//    var description: JSONDescription
//    var reader: ReadOnlyJSONDescription { return description }
//    
//    public var data: Data {
//        return Data(bytes: buffer.pointer, count: buffer.used)
//    }
//    
//    public var string: String! {
//        return String(data: data, encoding: .utf8)
//    }
//    
//    public init() {
//        self.buffer = Buffer.allocate(size: 4096)
//        let writePointer = self.buffer.pointer.assumingMemoryBound(to: UInt8.self)
//        writePointer[0] = .curlyLeft
//        writePointer[1] = .curlyRight
//        self.buffer.used = 2
//        self.description = JSONDescription()
//    }
//
//    public init(data: Data) throws {
//        self.buffer = Buffer(copying: data)
//
//        let size = data.count
//        
//        let description = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
//            return try JSONParser.scanValue(fromPointer: pointer, count: size)
//        }
//        self.description = description
//
//        guard reader.type == .object else {
//            throw JSONError.expectedObject
//        }
//    }
//    
//    public init(dictionaryLiteral elements: (String, JSONValue)...) {
//        self.init()
//        
//        let partialObject = description.describeObject(atOffset: 0)
//        let result = _ArrayObjectDescription(count: 0, byteCount: 2)
//        description.complete(partialObject, withResult: result)
//        
//        for (key, value) in elements {
//            self[key] = value
//        }
//    }
//    
//    internal init(buffer: Buffer, description: JSONDescription) {
//        self.buffer = buffer
//        self.description = description
//    }
//    
//    internal mutating func removeValue(index: Int, offset: Int) {
//        let firstElement = index == 0
//        let hasComma = reader.arrayObjectCount() > 1
//        
//        let keyBounds = reader.jsonBounds(at: offset)
//        var valueOffset = offset
//        reader.skip(withOffset: &valueOffset)
//        let valueBounds = reader.jsonBounds(at: valueOffset)
//        
//        let end = valueBounds.offset &+ valueBounds.length
//        var bounds = JSONBounds(offset: keyBounds.offset, length: Int(end &- keyBounds.length))
//        
//        commaFinder: if hasComma {
//            let pointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
//            
//            if firstElement {
//                var valueEnd = bounds.offset + bounds.length
//                
//                for _ in valueEnd ..< buffer.size {
//                    if pointer[valueEnd] == .comma {
//                        // Comma included in the length
//                        valueEnd = valueEnd &+ 1
//                        
//                        bounds.length = Int(valueEnd &- valueBounds.offset)
//                        break commaFinder
//                    }
//                    
//                    valueEnd = valueEnd &+ 1
//                }
//                
//                fatalError("No comma found between elements, invalid JSON parsed/created")
//            } else {
//                while valueBounds.offset > 0 {
//                    bounds.offset = bounds.offset - 1
//                    bounds.length = bounds.length + 1
//                    
//                    if pointer[valueBounds.offset] == .comma {
//                        break commaFinder
//                    }
//                }
//                
//                fatalError("No comma found between elements, invalid JSON parsed/created")
//            }
//        }
//        
//        
//        buffer.prepareRewrite(offset: bounds.offset, oldSize: bounds.length, newSize: 0)
//        
//        description.removeObjectDescription(atKeyIndex: offset, jsonOffset: keyBounds.offset, removedInt: bounds.length)
//    }
//
//    public subscript(key: String) -> JSONValue? {
//        get {
//            let pointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
//            guard
//                let (_, offset) = readerOffset(forKey: key, convertingSnakeCasing: false, in: pointer),
//                let type = reader.type(atOffset: offset)
//            else {
//                return nil
//            }
//
//            switch type {
//            case .object, .array:
//                let indexLength = reader.indexLength(atOffset: offset)
//                let jsonBounds = reader.dataBounds(atIndexOffset: offset)
//                
//                var subDescription = description.slice(from: offset, length: indexLength)
//                subDescription.advanceAllJSONOffsets(by: Int(-jsonBounds.offset))
//                let subBuffer = buffer.slice(bounds: jsonBounds)
//                
//                if type == .object {
//                    return JSONObject(buffer: subBuffer, description: subDescription)
//                } else {
//                    return JSONArray(buffer: subBuffer, description: subDescription)
//                }
//            case .boolTrue:
//                return true
//            case .boolFalse:
//                return false
//            case .string:
//                return reader.dataBounds(atIndexOffset: offset).makeString(from: pointer, escaping: false, unicode: true)
//            case .stringWithEscaping:
//                return reader.dataBounds(atIndexOffset: offset).makeString(from: pointer, escaping: true, unicode: true)
//            case .integer:
//                return reader.dataBounds(atIndexOffset: offset).makeInt(from: pointer)
//            case .floatingNumber:
//                return reader.dataBounds(atIndexOffset: offset).makeDouble(from: pointer, floating: true)
//            case .null:
//                return NSNull()
//            }
//        }
//        set {
//            let bytePointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
//            if let (index, offset) = reader.keyOffset(forKey: key, convertingSnakeCasing: false, in: bytePointer) {
//                if let newValue = newValue {
//                    var valueOffset = offset
//                    reader.skip(withOffset: &valueOffset)
//                    // rewrite value
//                    description.rewrite(buffer: buffer, to: newValue, at: valueOffset)
//                } else {
//                    self.removeValue(index: index, offset: offset)
//                }
//            } else if let newValue = newValue {
//                let reader = description
//                
//                let insertOffset = reader.dataBounds(atIndexOffset: 0).length - 1
//                
//                func writeKey(valueSize: Int) -> (UnsafeMutableRawPointer, Int) {
//                    var insertPointer: UnsafeMutableRawPointer
//                    
//                    var keyBytes = [UInt8]()
//                    let escapedKey = key.escapingAppend(to: &keyBytes)
//                    
//                    // 3 = `"` x2 and `:` x1
//                    var extra = keyBytes.count + 3 + valueSize
//                    
//                    let keyBounds: JSONBounds
//                    
//                    if reader.arrayObjectCount() > 0 {
//                        // This is safe since we override `}`
//                        extra += 1
//                        buffer.expandBuffer(to: buffer.used + extra)
//                        // 2 + for the `,"` start
//                        keyBounds = JSONBounds(offset: Int(2 &+ insertOffset), length: Int(keyBytes.count))
//                        // Make the pointer after possible reallocation reinitialized the pointer
//                        insertPointer = buffer.pointer + insertOffset
//                        insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .comma
//                        insertPointer += 1
//                    } else {
//                        buffer.expandBuffer(to: buffer.used + extra)
//                        // 1 + for the `"` start
//                        keyBounds = JSONBounds(offset: Int(1 &+ insertOffset), length: Int(keyBytes.count))
//                        // Make the pointer after possible reallocation reinitialized the pointer
//                        insertPointer = buffer.pointer + insertOffset
//                    }
//                    
//                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .quote
//                    insertPointer += 1
//                    
//                    assert(buffer.pointer.distance(to: insertPointer) + keyBytes.count <= buffer.size)
//                    memcpy(insertPointer, keyBytes, keyBytes.count)
//                    description.describeString(keyBounds, escaped: escapedKey)
//                    
//                    insertPointer += keyBytes.count
//                    
//                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .quote
//                    insertPointer += 1
//                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .colon
//                    insertPointer += 1
//                    
//                    let jsonValueOffset = Int(insertOffset &+ extra &- valueSize)
//                    assert(jsonValueOffset == buffer.pointer.distance(to: insertPointer))
//                    return (insertPointer, jsonValueOffset)
//                }
//                
//                let Int = Int(description.used)
//                
//                func write(_ string: String) -> JSONBounds {
//                    let (pointer, jsonOffset) = writeKey(valueSize: 4)
//                    
//                    let string = [UInt8](string.utf8)
//                    memcpy(pointer, string, string.count)
//                    
//                    pointer.advanced(by: string.count).uint8.pointee = .curlyRight
//                    
//                    // + 1 for the `}` and 2x `"`
//                    buffer.used = jsonOffset + string.count + 3
//                    return JSONBounds(offset: jsonOffset, length: Int(string.count))
//                }
//                
//                let oldSize = buffer.size
//                defer {
//                    let newSize = buffer.size
//                    let addedJSON = Int(newSize &- oldSize)
//                    description.incrementObjectCount(jsonSize: addedJSON, atValueOffset: Int)
//                }
//                
//                switch newValue {
//                case let object as JSONObject:
//                    let valueSize = Int(object.buffer.used)
//                    let (pointer, jsonOffset) = writeKey(valueSize: valueSize)
//                    self.description.addNestedDescription(object.description, at: jsonOffset)
//                    
//                    assert(buffer.pointer.distance(to: pointer) + valueSize <= buffer.size)
//                    
//                    memcpy(pointer, object.buffer.pointer, valueSize)
//                    pointer.advanced(by: valueSize).uint8.pointee = .curlyRight
//                    // + 1 for the `}` that will be added to the end of the new value
//                    buffer.used = jsonOffset &+ valueSize &+ 1
//                case let bool as Bool:
//                    if bool {
//                        // 4 represents the length of the characters in `true`
//                        let trueLength: Int = 4
//                        
//                        // Write the key, we receive a pointer from the key writer
//                        // The key writer returns the pointer because the pointer might need to be reallocated
//                        // This happens when the pointer's capacity is less than necessary to contain new data
//                        let (pointer, jsonOffset) = writeKey(valueSize: trueLength)
//                        let valueBounds = JSONBounds(offset: jsonOffset, length: trueLength)
//                        description.describeTrue(at: valueBounds.offset)
//                        memcpy(pointer, boolTrue, trueLength)
//                        pointer.advanced(by: trueLength).uint8.pointee = .curlyRight
//                        // + 1 for the `}` that will be added to the end of the new value
//                        // 4 represents the length of `true`
//                        buffer.used = jsonOffset &+ trueLength &+ 1
//                    } else {
//                        // 5 represents the length of the characters in `false`
//                        let falseLength = 4
//                        
//                        // Write the key, we receive a pointer from the key writer
//                        // The key writer returns the pointer because the pointer might need to be reallocated
//                        // This happens when the pointer's capacity is less than necessary to contain new data
//                        let (pointer, jsonOffset) = writeKey(valueSize: falseLength)
//                        let valueBounds = JSONBounds(offset: jsonOffset, length: falseLength)
//                        description.describeFalse(at: valueBounds.offset)
//                        memcpy(pointer, boolFalse, falseLength)
//                        pointer.advanced(by: falseLength).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
//                        
//                        // + 1 for the `}` that will be added to the end of the new value
//                        buffer.used = jsonOffset &+ falseLength &+ 1
//                    }
//                case let string as String:
//                    var valueBytes = [UInt8]()
//                    valueBytes.append(.quote)
//                    let escaped = string.escapingAppend(to: &valueBytes)
//                    valueBytes.append(.quote)
//                    
//                    // Write the key, we receive a pointer from the key writer
//                    // The key writer returns the pointer because the pointer might need to be reallocated
//                    // This happens when the pointer's capacity is less than necessary to contain new data
//                    let (pointer, jsonOffset) = writeKey(valueSize: valueBytes.count)
//                    memcpy(pointer, valueBytes, valueBytes.count)
//                    
//                    // Strings are compared and bounds start after the starting `"` and stop before the ending `"`
//                    // Therefore it's offset by 1 `"`
//                    let valueBounds = JSONBounds(offset: jsonOffset &+ 1, length: valueBytes.count &- 2)
//                    buffer.used = jsonOffset &+ valueBytes.count &+ 1 // + 1 for the `}`
//                    description.describeString(valueBounds, escaped: escaped)
//                    pointer.advanced(by: valueBytes.count).assumingMemoryBound(to: UInt8.self).pointee = .curlyRight
//                case let double as Double:
//                    let valueBounds = write(String(double))
//                    description.describeNumber(valueBounds, floatingPoint: true)
//                case let int as Int:
//                    let valueBounds = write(String(int))
//                    description.describeNumber(valueBounds, floatingPoint: false)
//                case is NSNull:
//                    // 4 represents the length of the characters in `null`
//                    let nullLength = 4
//                    
//                    // Write the key, we receive a pointer from the key writer
//                    // The key writer returns the pointer because the pointer might need to be reallocated
//                    // This happens when the pointer's capacity is less than necessary to contain new data
//                    let (pointer, jsonOffset) = writeKey(valueSize: nullLength)
//                    
//                    // Update the JSON description so the library knows that there's a null, and where it is
//                    let valueBounds = JSONBounds(offset: jsonOffset, length: nullLength)
//                    description.describeNull(at: valueBounds.offset)
//                    memcpy(pointer, nullBytes, nullLength)
//                    
//                    // At index 5 (position 
//                    (pointer + nullLength).uint8.pointee = .curlyRight
//                    
//                    // + 1 for the `}` that will be added to the end of the new value
//                    buffer.used = jsonOffset &+ nullLength &+ 1
//                default:
//                    fatalError("Unsupported value \(newValue)")
//                }
//            }
//        }
//    }
//}
