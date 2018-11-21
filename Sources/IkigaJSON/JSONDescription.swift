import Foundation

/// A type that automatically deallocated the pointer and can be expanded manually or automatically.
///
/// Has a few helpers for writing binary data. Mainly/only used for the JSONDescription.
final class AutoDeallocatingPointer {
    var pointer: UnsafeMutablePointer<UInt8>
    private(set) var totalSize: Int
    
    init(size: Int) {
        self.pointer = .allocate(capacity: size)
        totalSize = size
    }
    
    /// Expands the buffer to it's new absolute size and copies the usedCapacity to the new buffer.
    ///
    /// Any data after the userCapacity is lost
    func expand(to count: Int, usedCapacity size: Int) {
        let new = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        new.assign(from: pointer, count: size)
        pointer.deallocate()
        
        self.totalSize = count
        self.pointer = new
    }
    
    /// Expects `offset + count` bytes in this buffer, if this buffer is too small it's expanded
    private func beforeWrite(offset: Int, count: Int) {
        let needed = (offset &+ count) &- totalSize
        
        if needed > 0 {
            // A fat fingered number that will usually be efficient
            let newSize = offset &+ max(count, 4096)
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
struct JSONDescription {
    private let autoPointer: AutoDeallocatingPointer
    private(set) var pointer: UnsafeMutablePointer<UInt8>
    private(set) var totalSize: Int
    private(set) var size = 0
    
    /// Creates a new JSONDescription reserving 512 bytes by default.
    init(size: Int = 512) {
        self.autoPointer = AutoDeallocatingPointer(size: size)
        self.pointer = autoPointer.pointer
        self.totalSize = autoPointer.totalSize
    }
    
    /// Resets the used capacity which would enable reusing this description
    mutating func recycle() {
        self.size = 0
    }
    
    /// Sets the underlying buffer to this count specifically
    mutating func expand(to count: Int) {
        autoPointer.expand(to: count, usedCapacity: size)
        self.pointer = autoPointer.pointer
        self.totalSize = autoPointer.totalSize
    }
    
    /// A read only description is used for parsing the description
    var readOnly: ReadOnlyJSONDescription {
        return subDescription(offset: 0)
    }
    
    /// Slices the description into a read only buffer
    ///
    /// This is useful for nested data structures
    func subDescription(offset: Int) -> ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(pointer: pointer.advanced(by: offset), size: size &- offset, _super: self)
    }
    
    mutating func requireCapacity(_ n: Int) {
        if totalSize &- size < n {
            // A fat fingered number that will usually be efficient
            let newSize = max(n, totalSize &+ 4096)
            expand(to: newSize)
        }
    }
    
    mutating func describeNumber(_ number: Bounds, floatingPoint: Bool) {
        requireCapacity(9)
        pointer[size] = floatingPoint ? JSONType.floatingNumber.rawValue : JSONType.integer.rawValue
        pointer.advanced(by: size &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
            pointer[0] = UInt32(number.offset)
            pointer[1] = UInt32(number.length)
        }
        size = size &+ 9
    }
    
    mutating func describeString(_ string: Bounds, escaped: Bool) {
        requireCapacity(9)
        pointer[size] = escaped ? JSONType.stringWithEscaping.rawValue : JSONType.string.rawValue
        pointer.advanced(by: size &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
            pointer[0] = UInt32(string.offset)
            pointer[1] = UInt32(string.length)
        }
        size = size &+ 9
    }
    
    mutating func describeNull() {
        requireCapacity(1)
        pointer[size] = JSONType.null.rawValue
        size = size &+ 1
    }
    
    mutating func describeTrue() {
        requireCapacity(1)
        pointer[size] = JSONType.boolTrue.rawValue
        size = size &+ 1
    }
    
    mutating func describeFalse() {
        requireCapacity(1)
        pointer[size] =  JSONType.boolFalse.rawValue
        size = size &+ 1
    }
    
    /// Run returns the amount of elements written
    mutating func describeArray(atOffset offset: Int) -> UnfinishedDescription {
        requireCapacity(17)
        pointer[size] = JSONType.array.rawValue
        let indexStart = size
        
        // Write the rest later
        size = size &+ 17
        let arrayStart = size
        
        return UnfinishedDescription(dataOffset: offset, indexOffset: indexStart, firtChildIndexOffset: arrayStart)
    }
    
    /// Run returns the amount of elements written
    mutating func describeObject(atOffset offset: Int) -> UnfinishedDescription {
        requireCapacity(17)
        pointer[size] = JSONType.object.rawValue
        let indexStart = size
        
        // Write the rest later
        size = size &+ 17
        let objectStart = size
        
        return UnfinishedDescription(dataOffset: offset, indexOffset: indexStart, firtChildIndexOffset: objectStart)
    }
    
    func complete(_ unfinished: UnfinishedDescription , withResult result: _ArrayObjectDescription) {
        if result.count >= 16_777_216 {
            fatalError("Unsupported array count")
        }
        
        pointer.advanced(by: unfinished.indexOffset &+ 1).withMemoryRebound(to: UInt32.self, capacity: 4) { pointer in
            pointer[0] = UInt32(result.count) & 0x00ffffff
            pointer[1] = numericCast(unfinished.dataOffset)
            pointer[2] = result.byteCount
            pointer[3] = UInt32(size &- unfinished.firtChildIndexOffset)
        }
    }
}

struct UnfinishedDescription {
    fileprivate let dataOffset: Int
    fileprivate let indexOffset: Int
    fileprivate let firtChildIndexOffset: Int
}

struct ReadOnlyJSONDescription {
    internal let pointer: UnsafePointer<UInt8>
    internal let size: Int
    private let _super: JSONDescription
    
    fileprivate init(pointer: UnsafePointer<UInt8>, size: Int, _super: JSONDescription) {
        self.pointer = pointer
        self.size = size
        self._super = _super
    }
    
    func subDescription(offset: Int) -> ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(pointer: pointer.advanced(by: offset), size: self.size &- offset, _super: _super)
    }
    
    var type: JSONType {
        return JSONType(rawValue: pointer[0])!
    }
    
    func containsKey(_ key: String, inPointer buffer: UnsafePointer<UInt8>, unicode: Bool, fromOffset offset: Int = 17) -> Bool {
        assert(self.type == .object)
        // type(u8) + count(u32) + offset(u32) + length(u32)
        var offset = offset
        
        let count = self.pointer.advanced(by: 1).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        let keySize = key.utf8.count
        
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
    
    func offset(forKey key: String, in buffer: UnsafePointer<UInt8>) -> Int? {
        // Object index
        var offset = 17
        
        let count = pointer.advanced(by: 1).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        let key = [UInt8](key.utf8)
        let keySize = key.count
        
        for _ in 0..<count {
            let bounds = pointer.advanced(by: offset &+ 1).withMemoryRebound(to: UInt32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            
            // Skip key
            skip(withOffset: &offset)
            if bounds.length == keySize, memcmp(key, buffer.advanced(by: bounds.offset), bounds.length) == 0 {
                return offset
            }
            
            // Skip value
            skip(withOffset: &offset)
        }
        
        return nil
    }
    
    func type(atOffset offset: Int) -> JSONType? {
        guard let type = JSONType(rawValue: pointer[offset]) else {
            assertionFailure("This type mnust be valid and known")
            return nil
        }
        
        return type
    }
    
    func type(ofKey key: String, in buffer: UnsafePointer<UInt8>) -> JSONType? {
        guard let offset = self.offset(forKey: key, in: buffer) else {
            return nil
        }
        
        return self.type(atOffset: offset)
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
