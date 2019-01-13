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
/// - Size is a Int32 only for objects and arrays. This amount of successive elements are children
/// - Offset is a Int32 with the offset from the start of the parsed buffer where this element starts
/// - Length is a Int32 with the length from the offset that this element takes, not for bool and null
/// - ChildrenLength is a Int32 with the length of all child indexes
///
/// Objects have 2 JSONElements per registered element. The first element must be a string for the key
struct JSONDescription {
    private let autoPointer: AutoDeallocatingPointer
    private var pointer: UnsafeMutablePointer<UInt8> {
        return autoPointer.pointer
    }
    private var size: Int {
        return autoPointer.totalSize
    }
    private(set) var used = 0
    
    func copy() -> JSONDescription {
        return slice(from: 0, length: used)
    }
    
    func slice(from index: Int, length: Int) -> JSONDescription {
        var description = JSONDescription(size: length)
        description.pointer.assign(from: self.pointer + index, count: length)
        description.used = length
        return description
    }
    
    /// Creates a new JSONDescription reserving 512 bytes by default.
    init(size: Int = 512) {
        self.autoPointer = AutoDeallocatingPointer(size: size)
    }
    
    /// Resets the used capacity which would enable reusing this description
    mutating func recycle() {
        self.used = 0
    }
    
    /// Sets the underlying buffer to this count specifically
    mutating func expand(to count: Int) {
        autoPointer.expand(to: count, usedCapacity: used)
    }
    
    /// A read only description is used for parsing the description
    var readOnly: ReadOnlyJSONDescription {
        return subDescription(offset: 0)
    }
    
    /// Slices the description into a read only buffer
    ///
    /// This is useful for nested data structures
    func subDescription(offset: Int) -> ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(pointer: pointer.advanced(by: offset), size: used &- offset, _super: self)
    }
    
    mutating func addNestedDescription(_ description: JSONDescription, at jsonOffset: Int) {
        var description = description.copy()
        requireCapacity(used &+ description.used)
        description.advanceAllJSONOffsets(by: jsonOffset)
        assert(used &+ description.used <= self.size)
        memcpy(pointer + used, description.pointer, description.used)
        self.used += description.used
    }
    
    mutating func advanceAllJSONOffsets(by jsonOffset: Int) {
        var indexOffset = 17
        let jsonOffset = Int32(jsonOffset)
        let reader = readOnly
        
        pointer.advanced(by: 5).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            pointer.pointee += jsonOffset
        }
        
        while indexOffset < used {
            guard let type = reader.type(atOffset: indexOffset) else { return }
            
            switch type {
            case .object, .array:
                pointer.advanced(by: indexOffset &+ 5).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
                    pointer.pointee += jsonOffset
                }
            case .boolTrue, .boolFalse, .null, .string, .stringWithEscaping, .integer,  .floatingNumber:
                pointer.advanced(by: indexOffset &+ 1).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
                    pointer.pointee += jsonOffset
                }
            }
            
            reader.skip(withOffset: &indexOffset)
        }
    }
    
    mutating func requireCapacity(_ n: Int) {
        if size &- used < n {
            // A fat fingered number that will usually be efficient
            let newSize = max(n, size &+ 4096)
            expand(to: newSize)
        }
    }
    
    mutating func removeObjectDescription(at offset: Int, jsonOffset: Int, removedJSONLength: Int) {
        let reader = self.readOnly
        assert(reader.type == .object)
        
        var removeOffset = offset
        
        // Remove key AND value
        var indexLength = reader.indexLength(atOffset: removeOffset)
        reader.skip(withOffset: &removeOffset)
        indexLength += reader.indexLength(atOffset: removeOffset)
        
        let destination = pointer + offset
        let source = destination + indexLength
        let moveCount = used - offset - indexLength
        
        assert(offset + moveCount <= size && offset >= 0)
        assert(indexLength + moveCount <= size && indexLength + moveCount >= 0)
        memmove(destination, source, moveCount)
        used -= indexLength
        
        (pointer + 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] -= 1 // count -= 1
            pointer[2] -= Int32(removedJSONLength)
        }
        
        var updateLocationOffset = offset
        // Move back offsets >= the removed offset
        for _ in 0..<reader.arrayObjectCount() {
            let successivePair = reader.dataBounds(at: offset).offset >= jsonOffset
            
            // Key
            if successivePair {
                updateLocation(at: updateLocationOffset, by: -removedJSONLength)
            }
            reader.skip(withOffset: &updateLocationOffset)
            
            // Value
            if successivePair {
                updateLocation(at: updateLocationOffset, by: -removedJSONLength)
            }
            reader.skip(withOffset: &updateLocationOffset)
        }
    }
    
    private mutating func updateLocation(at offset: Int, by change: Int) {
        (pointer + offset + 1).withMemoryRebound(to: Int32.self, capacity: 1) {
            $0.pointee += Int32(change)
        }
    }
    
    mutating func removeArrayDescription(at offset: Int, jsonOffset: Int, removedJSONLength: Int) {
        let reader = self.readOnly
        
        assert(reader.type == .array)
        
        let indexLength = reader.indexLength(atOffset: offset)
        let destination = pointer + offset
        let source = destination + indexLength
        let moveCount = used - offset - indexLength
        
        assert(pointer.distance(to: destination) + moveCount <= used)
        memmove(destination, source, moveCount)
        used -= indexLength
        
        (pointer + 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] -= 1 // count -= 1
            pointer[2] -= Int32(removedJSONLength)
        }
        
        var updateLocationOffset = offset
        // Move back offsets >= the removed offset
        for _ in 0..<reader.arrayObjectCount() {
            let successivePair = reader.dataBounds(at: offset).offset >= jsonOffset
            
            // Value
            if successivePair {
                updateLocation(at: updateLocationOffset, by: -removedJSONLength)
            }
            reader.skip(withOffset: &updateLocationOffset)
        }
    }
    
    mutating func describeNumber(_ number: Bounds, floatingPoint: Bool) {
        requireCapacity(9)
        pointer[used] = floatingPoint ? JSONType.floatingNumber.rawValue : JSONType.integer.rawValue
        pointer.advanced(by: used &+ 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] = Int32(number.offset)
            pointer[1] = Int32(number.length)
        }
        used = used &+ 9
    }
    
    mutating func incrementObjectCount(jsonSize: Int, atValueOffset offset: Int) {
        let length = readOnly.indexLength(atOffset: offset)
        
        (pointer + 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] += 1
            pointer[2] += Int32(jsonSize)
            
            // 9 for string key
            pointer[3] += Int32(9 &+ length)
        }
    }
    
    mutating func incrementArrayCount(jsonSize: Int, atValueOffset offset: Int) {
        let length = readOnly.indexLength(atOffset: offset)
        
        (pointer + 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] += 1
            pointer[2] += Int32(jsonSize)
            pointer[3] += Int32(length)
        }
    }
    
    mutating func rewrite(buffer: Buffer, to value: JSONValue, at offset: Int) {
        let jsonBounds = readOnly.jsonBounds(at: offset)
        
        var bytes = [UInt8]()
        let length: Int
        
        defer {
            addJSONSize(of: length - jsonBounds.length)
        }
        
        switch value {
        case let string as String:
            bytes.append(.quote)
            let needsEscaping = string.escapingAppend(to: &bytes)
            bytes.append(.quote)
            
            length = bytes.count
            // -2 for the `""`
            // +1 for the starting `"`
            let newBounds = Bounds(offset: jsonBounds.offset &+ 1, length: length &- 2)
            rewriteString(newBounds, escaped: needsEscaping, at: offset)
        case let double as Double:
            bytes.append(contentsOf: String(double).utf8)
            length = bytes.count
            
            let newBounds = Bounds(offset: jsonBounds.offset, length: length)
            rewriteNumber(newBounds, floatingPoint: true, at: offset)
        case let int as Int:
            bytes.append(contentsOf: String(int).utf8)
            length = bytes.count
            
            let newBounds = Bounds(offset: jsonBounds.offset, length: length)
            rewriteNumber(newBounds, floatingPoint: false, at: offset)
        case let bool as Bool:
            if bool {
                bytes = boolTrue
                length = 4
                rewriteTrue(at: offset, jsonOffset: jsonBounds.offset)
            } else {
                bytes = boolFalse
                length = 5
                rewriteFalse(at: offset, jsonOffset: jsonBounds.offset)
            }
        case let object as JSONObject:
            length = object.buffer.used
            let readPointer = object.buffer.pointer.assumingMemoryBound(to: UInt8.self)
            buffer.prepareRewrite(offset: jsonBounds.offset, oldSize: jsonBounds.length, newSize: length)
            buffer.initialize(atOffset: jsonBounds.offset, from: readPointer, length: length)
            var newDescription = object.description.copy()
            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
            rewriteObjectArray(locallyAt: offset, from: newDescription)
            return
        case let array as JSONArray:
            length = array.buffer.used
            let readPointer = array.buffer.pointer.assumingMemoryBound(to: UInt8.self)
            buffer.prepareRewrite(offset: jsonBounds.offset, oldSize: jsonBounds.length, newSize: length)
            buffer.initialize(atOffset: jsonBounds.offset, from: readPointer, length: length)
            var newDescription = array.description.copy()
            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
            rewriteObjectArray(locallyAt: offset, from: newDescription)
            return
        default:
            bytes = nullBytes
            length = 4
            rewriteNull(at: offset, jsonOffset: jsonBounds.offset)
        }
        
        buffer.prepareRewrite(offset: jsonBounds.offset, oldSize: jsonBounds.length, newSize: length)
        buffer.initialize(atOffset: jsonBounds.offset, from: bytes, length: length)
    }
    
    mutating func addJSONSize(of size: Int) {
        assert(readOnly.type == .object || readOnly.type == .object)
        
        self.pointer.advanced(by: 9).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            pointer.pointee += Int32(size)
        }
    }
    
    mutating func rewriteStringOrNumber(_ value: Bounds, type: JSONType, at offset: Int) {
        let oldSize = readOnly.indexLength(atOffset: offset)
        let diff = 9 - oldSize
        requireCapacity(used + diff)
        
        if diff != 0 {
            let endIndex = offset + oldSize
            let source = pointer + endIndex
            let destination = source + diff
            memmove(destination, source, used - endIndex)
        }
        
        pointer[offset] = type.rawValue
        pointer.advanced(by: offset &+ 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] = Int32(value.offset)
            pointer[1] = Int32(value.length)
        }
        used = used &+ diff
    }
    
    mutating func rewriteNumber(_ number: Bounds, floatingPoint: Bool, at offset: Int) {
        rewriteStringOrNumber(number, type: floatingPoint ? .floatingNumber : .integer, at: offset)
    }
    
    mutating func describeString(_ string: Bounds, escaped: Bool) {
        requireCapacity(9)
        pointer[used] = escaped ? JSONType.stringWithEscaping.rawValue : JSONType.string.rawValue
        pointer.advanced(by: used &+ 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
            pointer[0] = Int32(string.offset)
            pointer[1] = Int32(string.length)
        }
        used = used &+ 9
    }
    
    mutating func rewriteString(_ string: Bounds, escaped: Bool, at offset: Int) {
        rewriteStringOrNumber(string, type: escaped ? .stringWithEscaping : .string, at: offset)
    }
    
    mutating func describeNull(at offset: Int) {
        requireCapacity(5)
        pointer[used] = JSONType.null.rawValue
        pointer.advanced(by: used &+ 1).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            pointer.pointee = Int32(offset)
        }
        used = used &+ 5
    }
    
    mutating func rewriteNull(at indexOffset: Int, jsonOffset: Int) {
        rewriteShortType(to: .null, indexOffset: indexOffset, jsonOffset: jsonOffset)
    }
    
    private mutating func rewriteShortType(to type: JSONType, indexOffset: Int, jsonOffset: Int) {
        let oldSize = readOnly.indexLength(atOffset: indexOffset)
        let diff = 5 - oldSize
        
        requireCapacity(used + diff)
        
        if diff != 0 {
            let endIndex = indexOffset + oldSize
            let source = pointer + endIndex
            let destination = source + diff
            memmove(destination, source, used - endIndex)
        }
        
        pointer[indexOffset] = type.rawValue
        pointer.advanced(by: indexOffset &+ 1).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            pointer.pointee = Int32(jsonOffset)
        }
        used = used &+ diff
    }
    
    mutating func describeTrue(at offset: Int) {
        requireCapacity(5)
        pointer[used] = JSONType.boolTrue.rawValue
        pointer.advanced(by: used &+ 1).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            pointer.pointee = Int32(offset)
        }
        used = used &+ 5
    }
    
    mutating func rewriteTrue(at offset: Int, jsonOffset: Int) {
        rewriteShortType(to: .boolTrue, indexOffset: offset, jsonOffset: jsonOffset)
    }
    mutating func describeFalse(at offset: Int) {
        requireCapacity(5)
        pointer[used] =  JSONType.boolFalse.rawValue
        pointer.advanced(by: used &+ 1).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            pointer.pointee = Int32(offset)
        }
        used = used &+ 5
    }
    
    mutating func rewriteFalse(at offset: Int, jsonOffset: Int) {
        rewriteShortType(to: .boolFalse, indexOffset: offset, jsonOffset: jsonOffset)
    }
    
    mutating func rewriteObjectArray(locallyAt localOffset: Int, from description: JSONDescription, at remoteOffset: Int = 0) {
        let oldLength = self.readOnly.indexLength(atOffset: localOffset)
        let newLength = description.readOnly.indexLength(atOffset: remoteOffset)
        
        let diff = newLength - oldLength
        requireCapacity(used + diff)
        
        if diff != 0 {
            let endIndex = localOffset + oldLength
            let source = pointer + endIndex
            let destination = source + diff
            memmove(destination, source, used - endIndex)
        }
        
        assert(localOffset + newLength <= size)
        assert(remoteOffset + newLength <= description.used)
        memcpy(pointer + localOffset, description.pointer + remoteOffset, newLength)
        used = used &+ diff
    }
    
    /// Run returns the amount of elements written
    mutating func describeArray(atOffset offset: Int) -> UnfinishedDescription {
        requireCapacity(17)
        pointer[used] = JSONType.array.rawValue
        let indexStart = used
        
        // Write the rest later
        used = used &+ 17
        let arrayStart = used
        
        return UnfinishedDescription(dataOffset: offset, indexOffset: indexStart, firtChildIndexOffset: arrayStart)
    }
    
    /// Run returns the amount of elements written
    mutating func describeObject(atOffset offset: Int) -> UnfinishedDescription {
        requireCapacity(17)
        pointer[used] = JSONType.object.rawValue
        let indexStart = used
        
        // Write the rest later
        used = used &+ 17
        let objectStart = used
        
        return UnfinishedDescription(dataOffset: offset, indexOffset: indexStart, firtChildIndexOffset: objectStart)
    }
    
    func complete(_ unfinished: UnfinishedDescription, withResult result: _ArrayObjectDescription) {
        if result.count >= 16_777_216 {
            fatalError("Unsupported array count")
        }
        
        pointer.advanced(by: unfinished.indexOffset &+ 1).withMemoryRebound(to: Int32.self, capacity: 4) { pointer in
            pointer[0] = Int32(result.count)
            pointer[1] = numericCast(unfinished.dataOffset)
            pointer[2] = result.byteCount
            pointer[3] = Int32(used &- unfinished.firtChildIndexOffset)
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
    
    /// Here to keep a strong reference to the buffer
    private let _super: JSONDescription
    
    var byteCount: Int {
        switch type {
        case .boolTrue, .null:
            return 4
        case .boolFalse:
            return 5
        case .array, .object:
            return pointer.advanced(by: 9).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
                return Int(pointer.pointee)
            }
        default:
            return pointer.advanced(by: 5).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
                return Int(pointer.pointee)
            }
        }
    }
    
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
    
    private func convertSnakeCasing(for characters: inout Data) {
        var size = characters.count
        var i = 0
        
        while i < size {
            if characters[i] == .underscore, i &+ 1 < size {
                size = size &- 1
                let byte = characters[i &+ 1]
                
                if byte >= .a && byte <= .z {
                    characters[i] = byte &- 0x20
                    characters.remove(at: i &+ 1)
                }
            }
            
            i = i &+ 1
        }
    }
    
    private func snakeCasedEqual(key: [UInt8], pointer: UnsafePointer<UInt8>, length: Int) -> Bool {
        let keySize = key.count
        var characters = Data(bytes: pointer, count: length)
        convertSnakeCasing(for: &characters)
        
        // The string was guaranteed by us to still be valid UTF-8
        let byteCount = characters.count
        if byteCount == keySize {
            return characters.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
                return memcmp(key, pointer, keySize) == 0
            }
        }
        
        return false
    }
    
    func containsKey(
        _ key: String,
        convertingSnakeCasing: Bool,
        inPointer buffer: UnsafePointer<UInt8>,
        unicode: Bool,
        fromOffset offset: Int = 17
    ) -> Bool {
        assert(self.type == .object)
        // type(u8) + count(u32) + offset(u32) + length(u32)
        var offset = offset
        
        let count = self.pointer.advanced(by: 1).withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        
        let key = [UInt8](key.utf8)
        let keySize = key.count
        
        for _ in 0..<count {
            let bounds = self.pointer.advanced(by: offset &+ 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            
            if !convertingSnakeCasing, bounds.length == keySize, memcmp(key, buffer.advanced(by: bounds.offset), bounds.length) == 0 {
                return true
            } else if convertingSnakeCasing, snakeCasedEqual(key: key, pointer: buffer + bounds.offset, length: bounds.length) {
                return true
            }
            
            skip(withOffset: &offset)
            skip(withOffset: &offset)
        }
        
        return false
    }
    
    func keyOffset(
        forKey key: String,
        convertingSnakeCasing: Bool,
        in buffer: UnsafePointer<UInt8>
    ) -> (index: Int, offset: Int)? {
        // Object index
        var index = 0
        var offset = 17
        
        let count = pointer.advanced(by: 1).withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        let key = [UInt8](key.utf8)
        let keySize = key.count
        
        for _ in 0..<count {
            let bounds = pointer.advanced(by: offset &+ 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            
            if !convertingSnakeCasing, bounds.length == keySize, memcmp(key, buffer + bounds.offset, bounds.length) == 0 {
                return (index, offset)
            } else if convertingSnakeCasing, snakeCasedEqual(key: key, pointer: buffer + bounds.offset, length: bounds.length) {
                return (index, offset)
            }
            
            // Skip key
            skip(withOffset: &offset)
            
            // Skip value
            skip(withOffset: &offset)
            index = index &+ 1
        }
        
        return nil
    }
    
    func valueOffset(
        forKey key: String,
        convertingSnakeCasing: Bool,
        in buffer: UnsafePointer<UInt8>
    ) -> (index: Int, offset: Int)? {
        guard let data = keyOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: buffer) else {
            return nil
        }
        
        let index = data.index
        var offset = data.offset
        // Skip key
        skip(withOffset: &offset)
        
        return (index, offset)
    }
    
    func type(atOffset offset: Int) -> JSONType? {
        guard let type = JSONType(rawValue: pointer[offset]) else {
            assertionFailure("This type mnust be valid and known")
            return nil
        }
        
        return type
    }
    
    func offset(forIndex index: Int) -> Int {
        assert(self.type == .array)
        var offset = 17
        for _ in 0..<index {
            skip(withOffset: &offset)
        }
        
        return offset
    }
    
    func type(
        ofKey key: String,
        convertingSnakeCasing: Bool,
        in buffer: UnsafePointer<UInt8>
    ) -> JSONType? {
        guard let (_, offset) = self.valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: buffer) else {
            return nil
        }
        
        return self.type(atOffset: offset)
    }
    
    func keys(
        inPointer buffer: UnsafePointer<UInt8>,
        unicode: Bool,
        convertingSnakeCasing: Bool,
        atOffset offset: Int = 17
    ) -> [String] {
        assert(self.type == .object)
        // type(u8) + count(u32) + offset(u32) + length(u32)
        var offset = offset
        
        let count = self.pointer.advanced(by: 1).withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        
        var keys = [String]()
        keys.reserveCapacity(numericCast(count))
        
        for _ in 0..<count {
            let bounds = self.pointer.advanced(by: offset &+ 1).withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                return Bounds(offset: numericCast(pointer[0]), length: numericCast(pointer[1]))
            }
            let escaping = self.pointer[offset] == JSONType.stringWithEscaping.rawValue
            
            if var stringData = bounds.makeStringData(from: buffer, escaping: escaping, unicode: unicode) {
                if convertingSnakeCasing {
                    convertSnakeCasing(for: &stringData)
                }
                
                if let key = String(data: stringData, encoding: .utf8) {
                    keys.append(key)
                }
            }
            
            skip(withOffset: &offset)
            skip(withOffset: &offset)
        }
        
        return keys
    }
    
    func arrayObjectCount() -> Int {
        assert(self.type == .array || self.type == .object)
        let count = pointer.advanced(by: 1).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
            return Int(pointer.pointee)
        }
        
        return count
    }
    
    func skip(withOffset offset: inout Int) {
        offset = offset &+ indexLength(atOffset: offset)
    }
    
    func indexLength(atOffset offset: Int) -> Int {
        // Force unwrap because this is all internal code, if this crashes JSON is broken
        switch JSONType(rawValue: pointer[offset])! {
        case .object, .array:
            let size = pointer.advanced(by: offset &+ 13).withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
            
            return 17 &+ numericCast(size)
        case .boolTrue, .boolFalse, .null:
            // Type byte + location
            return 5
        case .string, .stringWithEscaping, .integer, .floatingNumber:
            // Type byte + location + length
            return 9
        }
    }
    
    func dataBounds(at offset: Int) -> Bounds {
        let type = self.type(atOffset: offset)!
        switch type {
        case .object, .array:
            return objectArrayBounds(at: offset)
        case .boolTrue, .boolFalse, .null:
            return Bounds(
                offset: constantOffset(at: offset),
                length: type == .boolFalse ? 5 : 4
            )
        case .string, .stringWithEscaping, .integer, .floatingNumber:
            return pointer
                .advanced(by: offset &+ 1)
                .withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                    return Bounds(
                        offset: numericCast(pointer[0]),
                        length: numericCast(pointer[1])
                    )
            }
        }
    }
    
    func jsonBounds(at offset: Int) -> Bounds {
        let type = self.type(atOffset: offset)!
        switch type {
        case .object, .array:
            return objectArrayBounds(at: offset)
        case .boolTrue, .boolFalse, .null:
            return Bounds(
                offset: constantOffset(at: offset),
                length: type == .boolFalse ? 5 : 4
            )
        case .string, .stringWithEscaping:
            // Strings are surrounded by `"`
            return pointer
                .advanced(by: offset &+ 1)
                .withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                    return Bounds(
                        offset: numericCast(pointer[0]) &- 1,
                        length: numericCast(pointer[1]) &+ 2
                    )
            }
        case .integer, .floatingNumber:
            return pointer
                .advanced(by: offset &+ 1)
                .withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                    return Bounds(
                        offset: numericCast(pointer[0]),
                        length: numericCast(pointer[1])
                    )
            }
        }
    }
    
    private func objectArrayBounds(at offset: Int) -> Bounds {
        return pointer
            .advanced(by: offset &+ 5)
            .withMemoryRebound(to: Int32.self, capacity: 2) { pointer in
                return Bounds(
                    offset: numericCast(pointer[0]),
                    length: numericCast(pointer[1])
                )
        }
    }
    
    /// The offset for the constants `true`, `false` and `null`
    private func constantOffset(at offset: Int) -> Int {
        return Int((pointer + offset + 1).withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee })
    }
    
    func stringBounds(forKey key: String, convertingSnakeCasing: Bool, in pointer: UnsafePointer<UInt8>) -> (Bounds, Bool)? {
        guard
            let (_, offset) = self.valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: pointer),
            let type = self.type(atOffset: offset),
            type == .string || type == .stringWithEscaping
            else {
                return nil
        }
        
        return (dataBounds(at: offset), type == .stringWithEscaping)
    }
    
    func integerBounds(forKey key: String, convertingSnakeCasing: Bool, in pointer: UnsafePointer<UInt8>) -> Bounds? {
        guard
            let (_, offset) = self.valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: pointer),
            let type = self.type(atOffset: offset),
            type == .integer
            else {
                return nil
        }
        
        return dataBounds(at: offset)
    }
    
    func floatingBounds(forKey key: String, convertingSnakeCasing: Bool, in pointer: UnsafePointer<UInt8>) -> (Bounds, Bool)? {
        guard
            let (_, offset) = self.valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: pointer),
            let type = self.type(atOffset: offset),
            type == .integer || type == .floatingNumber
            else {
                return nil
        }
        
        return (dataBounds(at: offset), type == .floatingNumber)
    }
}


struct _ArrayObjectDescription {
    let count: Int32
    let byteCount: Int32
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
