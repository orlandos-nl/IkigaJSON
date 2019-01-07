import Foundation

public struct JSONArray {
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
        
        guard reader.type == .array else {
            throw JSONError.expectedObject
        }
    }
    
    public var count: Int {
        return reader.arrayObjectCount()
    }
    
    internal init(buffer: Buffer, description: JSONDescription, offset: Int) {
        self.buffer = buffer
        self.offset = offset
        self.description = description
    }
    
    public mutating func remove(at index: Int) {
        _checkBounds(index)
        
        let indexStart = reader.offset(forIndex: index)
        let bounds = reader.bounds(at: indexStart)
        description.removeArrayDescription(at: indexStart, jsonOffset: bounds.offset, removedJSONLength: bounds.length)
    }
    
    private func _checkBounds(_ index: Int) {
        if index >= reader.arrayObjectCount() {
            fatalError("Index out of bounds. \(index) > \(count)")
        } else if index < 0 {
            fatalError("Negative index requested for JSONArray.")
        }
    }
    
    public subscript(index: Int) -> JSONValue {
        get {
            _checkBounds(index)
            
            let pointer = buffer.pointer.bindMemory(to: UInt8.self, capacity: buffer.size)
            // Array descriptions are 17 bytes
            var offset = 17
            
            for _ in 0..<index {
                reader.skip(withOffset: &offset)
            }
            
            let type = reader.type(atOffset: offset)!

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
                return reader.bounds(at: offset).makeString(from: pointer, escaping: false, unicode: true)!
            case .stringWithEscaping:
                return reader.bounds(at: offset).makeString(from: pointer, escaping: true, unicode: true)!
            case .integer:
                return reader.bounds(at: offset).makeInt(from: pointer)!
            case .floatingNumber:
                return reader.bounds(at: offset).makeDouble(from: pointer, floating: true)!
            case .null:
                return NSNull()
            }
        }
        set {
            _checkBounds(index)
            
            let offset = reader.offset(forIndex: index)
            description.rewrite(buffer: buffer, to: newValue, at: offset)
        }
    }
}

extension String {
    public func escapingAppend(to bytes: inout [UInt8]) -> Bool {
        var escaped = false
        
        var characters = [UInt8](self.utf8)
        
        var i = characters.count
        nextByte: while i > 0 {
            i = i &- 1
            
            switch characters[i] {
            case .newLine:
                escaped = true
                characters[i] = .backslash
                characters.insert(.n, at: i &+ 1)
            case .carriageReturn:
                escaped = true
                characters[i] = .backslash
                characters.insert(.r, at: i &+ 1)
            case .quote:
                escaped = true
                characters.insert(.backslash, at: i)
            case .tab:
                escaped = true
                characters[i] = .backslash
                characters.insert(.t, at: i &+ 1)
            case .backslash:
                escaped = true
                characters.insert(.backslash, at: i &+ 1)
            default:
                continue
            }
        }
        
        bytes.append(contentsOf: characters)
        
        return escaped
    }
}
