import Foundation

/// Stores data efficiently to describe JSON to be parsed lazily into a concrete type
/// from the original buffer
///
/// Element := Type Size Offset Length ChildrenLength
///
/// - Type is a UInt8 mapped in `JSONType`.
/// - Size is a UInt32 only for objects and arrays. This amount of successive elements are children
/// - Offset is a UInt32 with the offset from the start of the parsed buffer where this element starts, not for bool and null
/// - Length is a UInt32 with the length from the offset that this element takes, not for bool and null
/// - ChildrenLength is a UInt32 with the length of all child indexes
///
/// Objects have 2 JSONElements per registered element. The first element must be a string for the key
final class JSONDescription {
    private(set) var pointer: UnsafeMutablePointer<UInt8>
    private(set) var totalSize: Int
    private(set) var size = 0
    
    deinit {
        pointer.deallocate()
    }
    
    init(size: Int = 512) {
        self.pointer = .allocate(capacity: size)
        totalSize = size
    }
    
    func expand(to count: Int) {
        let new = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        new.assign(from: pointer, count: size)
        pointer.deallocate()
        
        self.totalSize = count
        self.pointer = new
    }
    
    var readOnly: ReadOnlyJSONDescription {
        return subDescription(offset: 0)
    }
    
    func subDescription(offset: Int) -> ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(pointer: pointer.advanced(by: offset), _super: self)
    }
    
    func requireCapacity(_ n: Int) {
        if totalSize &- size < n {
            expand(to: totalSize &* 4)
        }
    }
    
    func describeNumber(_ number: Bounds, floatingPoint: Bool) {
        requireCapacity(9)
        pointer[size] = floatingPoint ? JSONType.floatingNumber.rawValue : JSONType.integer.rawValue
        pointer.advanced(by: size &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
            pointer[0] = UInt32(number.offset)
            pointer[1] = UInt32(number.length)
        }
        size = size &+ 9
    }
    
    func describeString(_ string: Bounds, escaped: Bool) {
        requireCapacity(9)
        pointer[size] = escaped ? JSONType.stringWithEscaping.rawValue : JSONType.string.rawValue
        pointer.advanced(by: size &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
            pointer[0] = UInt32(string.offset)
            pointer[1] = UInt32(string.length)
        }
        size = size &+ 9
    }
    
    func describeNull() {
        requireCapacity(1)
        pointer[size] = JSONType.null.rawValue
        size = size &+ 1
    }
    
    func describeTrue() {
        requireCapacity(1)
        pointer[size] = JSONType.boolTrue.rawValue
        size = size &+ 1
    }
    
    func describeFalse() {
        requireCapacity(1)
        pointer[size] =  JSONType.boolFalse.rawValue
        size = size &+ 1
    }
    
    /// Run returns the amount of elements written
    func describeArray(atOffset offset: UInt32, _ run: () throws -> _ArrayObjectDescription) rethrows {
        requireCapacity(17)
        pointer[size] = JSONType.array.rawValue
        let indexStart = size
        
        // Write the rest later
        size = size &+ 17
        let arrayStart = size
        
        let result = try run()
        
        if result.count >= 16_777_216 {
            fatalError("Unsupported array count")
        }
        
        pointer.advanced(by: indexStart &+ 1).withMemoryRebound(to: UInt32.self, capacity: 4) { pointer in
            pointer[0] = UInt32(result.count) & 0x00ffffff
            pointer[1] = offset
            pointer[2] = result.byteCount
            pointer[3] = UInt32(size &- arrayStart)
        }
    }
    
    /// Run returns the amount of elements written
    func describeObject(atOffset offset: UInt32, _ run: () throws -> _ArrayObjectDescription) rethrows {
        requireCapacity(17)
        pointer[size] = JSONType.object.rawValue
        let indexStart = size
        
        // Write the rest later
        size = size &+ 17
        let objectStart = size
        
        let result = try run()
        
        if result.count >= 16_777_216 {
            fatalError("Unsupported array count")
        }
        
        pointer.advanced(by: indexStart &+ 1).withMemoryRebound(to: UInt32.self, capacity: 3) { pointer in
            pointer[0] = UInt32(result.count) & 0x00ffffff
            pointer[1] = offset
            pointer[2] = result.byteCount
            pointer[3] = UInt32(size &- objectStart)
        }
    }
}

struct ReadOnlyJSONDescription {
    internal let pointer: UnsafePointer<UInt8>
    private let _super: JSONDescription
    
    fileprivate init(pointer: UnsafePointer<UInt8>, _super: JSONDescription) {
        self.pointer = pointer
        self._super = _super
    }
    
    func subDescription(offset: Int) -> ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(pointer: pointer.advanced(by: offset), _super: _super)
    }
    
    var type: JSONType {
        return JSONType(rawValue: pointer[0])!
    }
    
    func containsKey(_ key: String, inPointer buffer: UnsafePointer<UInt8>, unicode: Bool, fromOffset offset: Int = 17) -> Bool {
        assert(self.type == .object)
        // type(u8) + count(u32) + offset(u32) + length(u32)
        var offset = offset
        
        let count = self.pointer.advanced(by: 1).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        let key = [UInt8](key.utf8)
        let keySize = key.count
        
        for _ in 0..<count {
            let bounds = self.pointer.advanced(by: offset &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            
            if bounds.length == keySize, memcmp(key, buffer.advanced(by: bounds.offset), bounds.length) == 0 {
                return true
            }
            
            skip(withOffset: &offset)
            skip(withOffset: &offset)
        }
        
        return false
    }
    
    func keys(inPointer buffer: UnsafePointer<UInt8>, unicode: Bool, atOffset offset: Int = 17) -> [String] {
        assert(self.type == .object)
        // type(u8) + count(u32) + offset(u32) + length(u32)
        var offset = offset
        
        let count = self.pointer.advanced(by: 1).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        
        var keys = [String]()
        keys.reserveCapacity(numericCast(count))
        
        for _ in 0..<count {
            let bounds = self.pointer.advanced(by: offset &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            let escaping = self.pointer[offset] == JSONType.stringWithEscaping.rawValue
            if let string = bounds.makeString(from: buffer, escaping: escaping, unicode: unicode) {
                keys.append(string)
            }
            skip(withOffset: &offset)
            skip(withOffset: &offset)
        }
        
        return keys
    }
    
    func arrayCount() -> Int {
        assert(self.type == .array)
        let count = pointer.advanced(by: 1).withMemoryRebound(to: UInt32.self, capacity: 1) { pointer in
            return Int(pointer.pointee)
        }
        
        return count
    }
    
    func skip(withOffset offset: inout Int) {
        offset = offset &+ valueLength(atOffset: offset)
    }
    
    func valueLength(atOffset offset: Int) -> Int {
        // Force unwrap because this is all internal code, if this crashes JSON is broken
        switch JSONType(rawValue: pointer[offset])! {
        case .object, .array:
            let size = pointer.advanced(by: offset &+ 13).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
            
            return 17 &+ numericCast(size)
        case .boolTrue, .boolFalse, .null:
            // Just the type byte
            return 1
        case .string, .stringWithEscaping, .integer, .floatingNumber:
            return 9
        }
    }
}

struct _ArrayObjectDescription {
    let count: UInt32
    let byteCount: UInt32
}

enum JSONType: UInt8 {
    case object = 0x00
    case array = 0x01
    case boolTrue = 0x02
    case boolFalse = 0x03
    case string = 0x04
    case stringWithEscaping = 0x05
    case integer = 0x06
    case floatingNumber = 0x07
    case null = 0x08
}
