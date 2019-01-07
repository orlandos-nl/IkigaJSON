import Foundation

public struct JSONObject: ExpressibleByDictionaryLiteral {
    let buffer: Buffer
    var slice: UnsafeRawBufferPointer {
        return UnsafeRawBufferPointer(start: buffer.pointer + offset, count: reader.byteCount)
    }
    var description: JSONDescription
    let offset: Int
    var reader: ReadOnlyJSONDescription { return description.subDescription(offset: offset) }

    public init(data: Data) throws {
        self.buffer = Buffer(copying: data)

        let size = data.count
        
        let description = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            return try JSONParser.scanValue(fromPointer: pointer, count: size)
        }
        self.description = description
        self.offset = 0

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
        self.offset = 0
        self.description = JSONDescription()
        
        let partialObject = description.describeObject(atOffset: 0)
        let result = _ArrayObjectDescription(count: 0, byteCount: 2)
        description.complete(partialObject, withResult: result)
        
        for (key, value) in elements {
            self[key] = value
        }
    }
    
    internal init(buffer: Buffer, description: JSONDescription, offset: Int) {
        self.buffer = buffer
        self.offset = offset
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
            case .object:
                return JSONObject(buffer: buffer.copy, description: description, offset: self.offset + offset)
            case .array:
                return JSONArray(buffer: buffer.copy, description: description, offset: self.offset + offset)
            case .boolTrue:
                return true
            case .boolFalse:
                return false
            case .string:
                return reader.bounds(at: offset).makeString(from: pointer, escaping: false, unicode: true)
            case .stringWithEscaping:
                return reader.bounds(at: offset).makeString(from: pointer, escaping: true, unicode: true)
            case .integer:
                return reader.bounds(at: offset).makeInt(from: pointer)
            case .floatingNumber:
                return reader.bounds(at: offset).makeDouble(from: pointer, floating: true)
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
                } else {
                    let firstElement = index == 0
                    let hasComma = reader.arrayObjectCount() > 1
                    
                    var valueBounds = reader.bounds(at: offset)
                    
                    // -1 offset for the key's leading `"`
                    valueBounds.offset = valueBounds.offset &- 1
                    
                    commaFinder: if hasComma {
                        let pointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
                        
                        if firstElement {
                            var valueEnd = valueBounds.offset &+ valueBounds.length
                            
                            for _ in valueEnd ..< buffer.size {
                                if pointer[valueEnd] == .comma {
                                    // Comma included in the length
                                    valueEnd = valueEnd &+ 1
                                    
                                    valueBounds.length = valueEnd &- valueBounds.offset
                                    break commaFinder
                                }
                                
                                valueEnd = valueEnd &+ 1
                            }
                            
                            fatalError("No comma found between elements, invalid JSON parsed/created")
                        } else {
                            while valueBounds.offset > 0 {
                                valueBounds.offset = valueBounds.offset &- 1
                                valueBounds.length = valueBounds.length &+ 1
                                
                                if pointer[valueBounds.offset] == .comma {
                                    break commaFinder
                                }
                            }
                            
                            fatalError("No comma found between elements, invalid JSON parsed/created")
                        }
                    }
                    
                    buffer.prepareRewrite(offset: valueBounds.offset, oldSize: valueBounds.length, newSize: 0)
                    buffer.used = buffer.used &- valueBounds.length
                    
                    description.removeObjectDescription(at: offset, jsonOffset: valueBounds.offset, removedJSONLength: valueBounds.length)
                }
            } else if let newValue = newValue {
                let reader = description.readOnly
                
                let insertOffset = reader.bounds(at: 0).length - 1
                var insertPointer: UnsafeMutableRawPointer
                
                var keyBytes = [UInt8]()
                let escapedKey = key.escapingAppend(to: &keyBytes)
                let keyLength = keyBytes.count
                
                let (valueBytes, type) = newValue.makeWritable()
                
                // 3 = `"` x2 and `:` x1
                var extra = keyLength + 3 + valueBytes.count
                let keyBounds: Bounds
                
                if reader.arrayObjectCount() > 0 {
                    // This is safe since we override `}`
                    extra += 1
                    buffer.expandBuffer(to: buffer.used + extra)
                    // 2 + for the `,"` start
                    keyBounds = Bounds(offset: 2 &+ insertOffset, length: keyLength)
                    // Make the pointer after possible reallocation reinitialized the pointer
                    insertPointer = buffer.pointer + insertOffset
                    insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .comma
                    insertPointer += 1
                } else {
                    buffer.expandBuffer(to: buffer.used + extra)
                    // 1 + for the `"` start
                    keyBounds = Bounds(offset: 1 &+ insertOffset, length: keyLength)
                    // Make the pointer after possible reallocation reinitialized the pointer
                    insertPointer = buffer.pointer + insertOffset
                }
                
                insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .quote
                insertPointer += 1
                
                memcpy(insertPointer, keyBytes, keyLength)
                description.describeString(keyBounds, escaped: escapedKey)
                
                insertPointer += keyLength

                insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .quote
                insertPointer += 1
                insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .colon
                insertPointer += 1
                
                memcpy(insertPointer, valueBytes, valueBytes.count)
                var valueBounds = Bounds(offset: insertOffset &+ extra &- valueBytes.count, length: valueBytes.count)
                let indexOffset = description.size
                
                switch type {
                case .object:
                    fatalError()
                case .array:
                    fatalError()
                case .boolTrue:
                    description.describeTrue(at: valueBounds.offset)
                case .boolFalse:
                    description.describeFalse(at: valueBounds.offset)
                case .string, .stringWithEscaping:
                    // Strings are compared and bounds start after the starting `"` and stop before the ending `"`
                    valueBounds.offset += 1
                    description.describeString(valueBounds, escaped: type == .stringWithEscaping)
                case .integer, .floatingNumber:
                    description.describeNumber(valueBounds, floatingPoint: type == .floatingNumber)
                case .null:
                    description.describeNull(at: valueBounds.offset)
                }
                
                insertPointer += valueBytes.count
                
                 // 3 = `"` x2 and `:` x1
                insertPointer.bindMemory(to: UInt8.self, capacity: 1).pointee = .curlyRight
                
                buffer.used += extra
                
                description.incrementObjectCount(jsonSize: extra, atValueOffset: indexOffset)
            }
        }
    }
}

extension JSONValue {
    func makeWritable() -> ([UInt8], JSONType) {
        switch self {
        case let string as String:
            var valueBytes = [UInt8]()
            valueBytes.append(.quote)
            let escaped = string.escapingAppend(to: &valueBytes)
            valueBytes.append(.quote)
            let type: JSONType = escaped ? .stringWithEscaping : .string
            return (valueBytes, type)
        case is NSNull:
            return (nullBytes, .null)
        case let bool as Bool:
            return bool ? (boolTrue, .boolTrue) : (boolFalse, .boolFalse)
        case let double as Double:
            return (Array(String(double).utf8), .floatingNumber)
        case let int as Int:
            return (Array(String(int).utf8), .integer)
        case let int as Int8:
            return (Array(String(int).utf8), .integer)
        case let int as Int16:
            return (Array(String(int).utf8), .integer)
        case let int as Int32:
            return (Array(String(int).utf8), .integer)
        case let int as Int64:
            return (Array(String(int).utf8), .integer)
        case let int as UInt:
            return (Array(String(int).utf8), .integer)
        case let int as UInt8:
            return (Array(String(int).utf8), .integer)
        case let int as UInt16:
            return (Array(String(int).utf8), .integer)
        case let int as Int32:
            return (Array(String(int).utf8), .integer)
        case let int as UInt64:
            return (Array(String(int).utf8), .integer)
        case let object as JSONObject:
            return (, .object)
        case let array as JSONArray:
            fatalError()
        default:
            fatalError("Unsupported value \(self) for JSON")
        }
    }
}
