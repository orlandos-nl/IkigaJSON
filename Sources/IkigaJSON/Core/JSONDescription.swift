import NIO
import Foundation

/// Stores data efficiently to describe JSON to be parsed lazily into a concrete type
/// from the original buffer
///
/// Element := Type Size Offset Length ChildrenLength
///
/// - Type is a UInt8 mapped in `JSONType`.
/// - Offset is a Int32 with the offset from the start of the parsed buffer where this element starts
/// - Length is a Int32 with the length from the offset that this element takes, not for bool and null
/// - ChildCount is a Int32 only for objects and arrays. This amount of successive elements are children Objects have 2 JSONElements per registered element. The first element must be a string for the key
/// - ChildrenLength is a Int32 with the length of all child indexes
internal struct JSONDescription {
    internal var buffer: ByteBuffer
    
    func slice(from offset: Int, length: Int) -> JSONDescription {
        return JSONDescription(buffer: buffer.getSlice(at: offset, length: length)!)
    }
    
    private init(buffer: ByteBuffer) {
        self.buffer = buffer
    }
    
    /// Creates a new JSONDescription reserving 512 bytes by default.
    init(size: Int = 512) {
        self.buffer = allocator.buffer(capacity: size)
    }
    
    /// Resets the used capacity which would enable reusing this description
    mutating func recycle() {
        self.buffer.moveWriterIndex(to: 0)
    }
}

fileprivate extension ByteBuffer {
    mutating func prepareRewrite(offset: Int, oldSize: Int, newSize: Int) {
        // `if newSize == 5 && oldSize == 3` then We need to write over 0..<5
        // Meaning we move the rest back by (5 - 3 = 2)
        
        // Or if `newSize == 3 && oldSize == 5` we write over 0..<3 and move forward by 2 (or -2 offset)
        let diff = newSize - oldSize
        
        if diff == 0 { return }
        let writerIndex = self.writerIndex
        reserveCapacity(writerIndex + diff)
        
        let endIndex = offset + oldSize
        
        withUnsafeMutableWritableBytes { buffer in
            let pointer = buffer.baseAddress!
            let source = pointer + endIndex
            let destination = source + diff
            
            memmove(destination, source, writerIndex - endIndex)
        }
        
        moveWriterIndex(forwardBy: diff)
    }
    
    mutating func advance<F: FixedWidthInteger>(at offset: Int, by value: F) {
        guard let old: F = getInteger(at: offset) else {
            assertionFailure("The JSON index is corrupt. There were not enough bytes to fetch a JSON value's location. Please file a bug report on Github")
            return
        }
        
        assert(!old.addingReportingOverflow(value).overflow)
        
        set(integer: old &+ value, at: offset)
    }
}

extension JSONDescription {
    /// Inserts an object or array's JSONDescription and it's children into this one
    /// The supplied Int is the location where the value will be stored in JSON
    /// This will be used to update all locations in JSON accordingly
    mutating func addNestedDescription(_ description: JSONDescription, at jsonOffset: Int32) {
        var description = description
        description.advanceAllJSONOffsets(by: jsonOffset)
    }
    
    /// Moves this index description and all it's child descriptions their JSON offsets forward
    mutating func advanceAllJSONOffsets(by jsonOffset: Int32) {
        self.buffer.advance(at: Constants.jsonLocationOffset, by: jsonOffset)
        
        var indexOffset = Constants.firstArrayObjectChildOffset
        
        while indexOffset < buffer.writerIndex {
            self.buffer.advance(at: indexOffset, by: jsonOffset)
            skipIndex(atOffset: &indexOffset)
        }
    }
    
    var readOnly: ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(buffer: buffer)
    }
    
    func type(atOffset offset: Int) -> JSONType {
        guard let typeByte: UInt8 = buffer.getInteger(at: offset), let type = JSONType(rawValue: typeByte) else {
            fatalError("The JSON index is corrupt. No JSON Type could be found at offset \(offset). Please file a bug report on Github.")
        }
        
        return type
    }
    
    func indexLength(atOffset offset: Int) -> Int {
        // Force unwrap because this is all internal code, if this crashes JSON is broken
        switch type(atOffset: offset) {
        case .object, .array:
            guard let childrenLength: Int32 = buffer.getInteger(at: offset + Constants.arrayObjectTotalIndexLengthOffset) else {
                fatalError("The JSON index is corrupt. No IndexLength could be found for all children of an object or array. Please file a bug report on Github.")
            }
            
            assert(childrenLength <= Int32(buffer.readableBytes))
            return Constants.arrayObjectIndexLength + Int(childrenLength)
        case .boolTrue, .boolFalse, .null:
            // Type byte + location
            return Constants.boolNullIndexLength
        case .string, .stringWithEscaping, .integer, .floatingNumber:
            return Constants.stringNumberIndexLength
        }
    }
    
    func skipIndex(atOffset offset: inout Int) {
        offset = offset &+ indexLength(atOffset: offset)
    }
    
    /// Removes a key-value pair from object descriptions only
    /// Removes both the key and the value from this description
//    mutating func removeObjectDescription(atKeyIndex keyOffset: Int, jsonOffset: Int, removedJSONLength: JSONLength) {
//        let reader = self
//        assert(reader.type == .object)
//
//        // Remove key AND value
//        var removedLength = reader.indexLength(atOffset: keyOffset)
//
//        var valueOffset = keyOffset
//        reader.skip(withOffset: &valueOffset)
//        removedLength += reader.indexLength(atOffset: valueOffset)
//
//        let destination = pointer + keyOffset
//        let source = destination + removedLength
//        let moveCount = used - keyOffset - removedLength
//
//        memmove(destination, source, moveCount)
//        used -= removedLength
//
//        let objectPairCount = pointer.advanced(by: Constants.arrayObjectPairCountOffset).int32
//        objectPairCount.pointee -= 1
//
//        let objectJsonLength = pointer.advanced(by: Constants.jsonLengthOffset).int32
//        objectJsonLength.pointee -= Int32(removedJSONLength)
//
//        var updateLocationOffset = keyOffset
//        // Move back offsets >= the removed offset
//        for _ in 0..<reader.arrayObjectCount() {
//            let successivePair = reader.dataBounds(atIndexOffset: keyOffset).offset >= jsonOffset
//
//            // Key
//            if successivePair {
//                updateLocation(at: updateLocationOffset, by: -removedJSONLength)
//            }
//            reader.skip(withOffset: &updateLocationOffset)
//
//            // Value
//            if successivePair {
//                updateLocation(at: updateLocationOffset, by: -removedJSONLength)
//            }
//            reader.skip(withOffset: &updateLocationOffset)
//        }
//    }
//
//    private mutating func updateLocation(at offset: Int, by change: Int) {
//        let location = (pointer + offset + Constants.jsonLocationOffset).int32
//        location.pointee += Int32(change)
//    }
//
//    mutating func removeArrayDescription(atIndex indexOffset: Int, jsonOffset: Int, removedLength: JSONLength) {
//        let reader = self
//
//        assert(reader.type == .array)
//
//        let indexLength = reader.indexLength(atOffset: indexOffset)
//        let destination = pointer + indexOffset
//        let source = destination + indexLength
//        let moveCount = used - indexOffset - indexLength
//
//        assert(pointer.distance(to: destination) + moveCount <= used)
//        memmove(destination, source, moveCount)
//        used -= indexLength
//
//        let count = (pointer + Constants.arrayObjectPairCountOffset).int32
//        let length = (pointer + Constants.jsonLocationOffset).int32
//        count.pointee -= 1 // count -= 1
//        length.pointee -= Int32(removedLength)
//
//        var updateLocationOffset = indexOffset
//        // Move back offsets >= the removed offset
//        for _ in 0..<reader.arrayObjectCount() {
//            let successivePair = reader.dataBounds(atIndexOffset: indexOffset).offset >= jsonOffset
//
//            // Value
//            if successivePair {
//                updateLocation(at: updateLocationOffset, by: -removedLength)
//            }
//            reader.skip(withOffset: &updateLocationOffset)
//        }
//    }
//
    /// Adds a description for a JSON number
    mutating func describeNumber(at number: Bounds, floatingPoint: Bool) {
        // Make a destinction between floating points and integers
        let type = floatingPoint ? JSONType.floatingNumber.rawValue : JSONType.integer.rawValue

        // Set the new type identifier
        self.buffer.write(integer: type)
        
        self.buffer.write(integer: number.offset)
        self.buffer.write(integer: number.length)
    }
//
//    /// Assumes `self` to be a description of a `JSONObject`
//    mutating func incrementObjectCount(jsonSize: JSONLength, atValueOffset offset: Int) {
//        assert(readOnly.type == .object)
//
//        // Fetches the indexLength of the newly added value
//        let addedIndexLength = readOnly.indexLength(atOffset: offset)
//
//        let count = (pointer + Constants.arrayObjectPairCountOffset).int32
//        let jsonLength = (pointer + Constants.arrayObjectPairCountOffset).int32
//        let indexLength = (pointer + Constants.arrayObjectPairCountOffset).int32
//
//        // Update the pair count by 1, since a value was added
//        count.pointee += 1
//
//        // Increment the index and json length accordingly
//        jsonLength.pointee += Int32(jsonSize)
//        indexLength.pointee += Int32(Constants.stringNumberIndexLength &+ addedIndexLength)
//    }
//
//    /// Assumes `self` to be a description of a `JSONArray`
//    mutating func incrementArrayCount(jsonSize: JSONLength, atValueOffset offset: Int) {
//        assert(readOnly.type == .array)
//
//        // Fetches the indexLength of the newly added value
//        let addedIndexLength = readOnly.indexLength(atOffset: offset)
//
//        let count = (pointer + Constants.arrayObjectPairCountOffset).int32
//        let jsonLength = (pointer + Constants.arrayObjectPairCountOffset).int32
//        let indexLength = (pointer + Constants.arrayObjectPairCountOffset).int32
//
//        // Update the pair count by 1, since a value was added
//        count.pointee += 1
//
//        // Increment the index and json length accordingly
//        jsonLength.pointee += Int32(jsonSize)
//        indexLength.pointee += Int32(Constants.stringNumberIndexLength &+ addedIndexLength)
//    }
//
//    mutating func rewrite(buffer: Buffer, to value: JSONValue, at offset: Int) {
//        let jsonBounds = readOnly.jsonBounds(at: offset)
//
//        var bytes = [UInt8]()
//        let length: Int
//
//        defer {
//            addJSONSize(of: length - jsonBounds.length)
//        }
//
//        switch value {
//        case let string as String:
//            bytes.append(.quote)
//            let needsEscaping = string.escapingAppend(to: &bytes)
//            bytes.append(.quote)
//
//            length = bytes.count
//            // -2 for the `""`
//            // +1 for the starting `"`
//            let newBounds = JSONBounds(offset: jsonBounds, length: length)
//            rewriteString(newBounds, escaped: needsEscaping, at: offset)
//        case let double as Double:
//            bytes.append(contentsOf: String(double).utf8)
//            length = bytes.count
//
//            let newBounds = JSONBounds(offset: jsonBounds.offset, length: length)
//            rewriteNumber(newBounds, floatingPoint: true, at: offset)
//        case let int as Int:
//            bytes.append(contentsOf: String(int).utf8)
//            length = bytes.count
//
//            let newBounds = JSONBounds(offset: jsonBounds.offset, length: length)
//            rewriteNumber(newBounds, floatingPoint: false, at: offset)
//        case let bool as Bool:
//            if bool {
//                bytes = boolTrue
//                length = 4
//                rewriteTrue(at: offset, jsonOffset: jsonBounds.offset)
//            } else {
//                bytes = boolFalse
//                length = 5
//                rewriteFalse(at: offset, jsonOffset: jsonBounds.offset)
//            }
//        case let object as JSONObject:
//            length = object.buffer.used
//            let readPointer = object.buffer.pointer.uint8
//            buffer.prepareRewrite(offset: jsonBounds.offset, oldSize: jsonBounds.length, newSize: length)
//            buffer.initialize(atOffset: jsonBounds.offset, from: readPointer, length: length)
//            var newDescription = object.description.copy()
//            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
//            rewriteObjectArray(locallyAt: offset, from: newDescription)
//            return
//        case let array as JSONArray:
//            length = array.buffer.used
//            let readPointer = array.buffer.pointer.uint8
//            buffer.prepareRewrite(offset: jsonBounds.offset, oldSize: jsonBounds.length, newSize: length)
//            buffer.initialize(atOffset: jsonBounds.offset, from: readPointer, length: length)
//            var newDescription = array.description.copy()
//            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
//            rewriteObjectArray(locallyAt: offset, from: newDescription)
//            return
//        default:
//            bytes = nullBytes
//            length = 4
//            rewriteNull(at: offset, jsonOffset: jsonBounds.offset)
//        }
//
//        buffer.prepareRewrite(offset: jsonBounds.offset, oldSize: jsonBounds.length, newSize: length)
//        buffer.initialize(atOffset: jsonBounds.offset, from: bytes, length: length)
//    }
//
//    mutating func addJSONSize(of size: Int) {
//        assert(readOnly.type == .object || readOnly.type == .object)
//
//        self.pointer.advanced(by: 9).withMemoryRebound(to: Int32.self, capacity: 1) { pointer in
//            pointer.pointee += Int32(size)
//        }
//    }
//
//    mutating func rewriteStringOrNumber(_ value: JSONBounds, type: JSONType, at offset: Int) {
//        let oldSize = readOnly.indexLength(atOffset: offset)
//        let diff = 9 - oldSize
//        requireCapacity(used + diff)
//
//        if diff != 0 {
//            let endIndex = offset + oldSize
//            let source = pointer + endIndex
//            let destination = source + diff
//            memmove(destination, source, used - endIndex)
//        }
//
//        pointer.uint8[offset] = type.rawValue
//        (pointer + offset + Constants.jsonLocationOffset).int32.pointee = Int32(value.offset)
//        (pointer + offset + Constants.jsonLengthOffset).int32.pointee = Int32(value.length)
//        used = used &+ diff
//    }
//
//    mutating func rewriteNumber(_ number: JSONBounds, floatingPoint: Bool, at offset: Int) {
//        rewriteStringOrNumber(number, type: floatingPoint ? .floatingNumber : .integer, at: offset)
//    }
//
    mutating func describeString(at stringBounds: Bounds, escaped: Bool) {
        let type: JSONType = escaped ? .stringWithEscaping : .string
        
        buffer.write(integer: type.rawValue)
        buffer.write(integer: stringBounds.offset)
        buffer.write(integer: stringBounds.length)
    }
//
//    mutating func rewriteString(_ string: JSONBounds, escaped: Bool, at offset: Int) {
//        rewriteStringOrNumber(string, type: escaped ? .stringWithEscaping : .string, at: offset)
//    }
//
//    mutating func rewriteNull(at indexOffset: Int, jsonOffset: Int) {
//        rewriteShortType(to: .null, indexOffset: indexOffset, jsonOffset: jsonOffset)
//    }
//
//    private mutating func rewriteShortType(to type: JSONType, indexOffset: Int, jsonOffset: Int) {
//        let oldSize = readOnly.indexLength(atOffset: indexOffset)
//        let diff = Constants.boolNullIndexLength - oldSize
//
//        requireCapacity(used + diff)
//
//        if diff != 0 {
//            let endIndex = indexOffset + oldSize
//            let source = pointer + endIndex
//            let destination = source + diff
//            memmove(destination, source, used - endIndex)
//        }
//
//        pointer.uint8[indexOffset] = type.rawValue
//        (pointer + indexOffset + Constants.jsonLocationOffset).int32.pointee += Int32(jsonOffset)
//        used = used &+ diff
//    }
//
//    mutating func rewriteObjectArray(locallyAt localOffset: Int, from description: JSONDescription, at remoteOffset: Int = 0) {
//        let oldLength = self.indexLength(atOffset: localOffset)
//        let newLength = description.indexLength(atOffset: remoteOffset)
//
//        let diff = newLength - oldLength
//        requireCapacity(used + diff)
//
//        if diff != 0 {
//            let endIndex = localOffset + oldLength
//            let source = pointer + endIndex
//            let destination = source + diff
//            memmove(destination, source, used - endIndex)
//        }
//
//        assert(localOffset + newLength <= size)
//        assert(remoteOffset + newLength <= description.used)
//        memcpy(pointer + localOffset, description.pointer + remoteOffset, newLength)
//        used = used &+ diff
//    }
//
//    mutating func rewriteTrue(at offset: Int, jsonOffset: Int) {
//        rewriteShortType(to: .boolTrue, indexOffset: offset, jsonOffset: jsonOffset)
//    }
//
//    mutating func rewriteFalse(at offset: Int, jsonOffset: Int) {
//        rewriteShortType(to: .boolFalse, indexOffset: offset, jsonOffset: jsonOffset)
//    }
    
    mutating func describeTrue(atJSONOffset jsonOffset: Int32) {
        buffer.write(integer: JSONType.boolTrue.rawValue)
        buffer.write(integer: jsonOffset)
    }
    
    mutating func describeFalse(atJSONOffset jsonOffset: Int32) {
        buffer.write(integer: JSONType.boolFalse.rawValue)
        buffer.write(integer: jsonOffset)
    }
    
    mutating func describeNull(atJSONOffset jsonOffset: Int32) {
        buffer.write(integer: JSONType.null.rawValue)
        buffer.write(integer: jsonOffset)
    }
    
    mutating func describeArray(atJSONOffset jsonOffset: Int32) -> UnfinishedDescription {
        let indexOffset = buffer.writerIndex
        buffer.write(integer: JSONType.array.rawValue)
        buffer.write(integer: jsonOffset)
        buffer.moveWriterIndex(forwardBy: 12)
        
        return UnfinishedDescription(
            indexOffset: indexOffset,
            firstChildIndexOffset: buffer.writerIndex
        )
    }
    
    mutating func describeObject(atJSONOffset jsonOffset: Int32) -> UnfinishedDescription {
        let indexOffset = buffer.writerIndex
        buffer.write(integer: JSONType.object.rawValue)
        buffer.write(integer: jsonOffset)
        buffer.moveWriterIndex(forwardBy: 12)
        
        return UnfinishedDescription(
            indexOffset: indexOffset,
            firstChildIndexOffset: buffer.writerIndex
        )
    }
    
    mutating func complete(_ unfinished: UnfinishedDescription, withResult result: _ArrayObjectDescription) {
        buffer.set(integer: result.jsonByteCount, at: unfinished.indexOffset &+ Constants.jsonLengthOffset)
        buffer.set(integer: result.valueCount, at: unfinished.indexOffset &+ Constants.arrayObjectPairCountOffset)
        
        let indexLength = Int32(buffer.writerIndex &- unfinished.firstChildIndexOffset)
        buffer.set(integer: indexLength, at: unfinished.indexOffset &+ Constants.arrayObjectTotalIndexLengthOffset)
    }
}

struct UnfinishedDescription {
    fileprivate let indexOffset: Int
    fileprivate let firstChildIndexOffset: Int
}

struct ReadOnlyJSONDescription {
    internal let buffer: ByteBuffer
    
    var jsonLength: Int {
        switch topLevelType {
        case .boolTrue, .null:
            return 4
        case .boolFalse:
            return 5
        default:
            return Int(dataBounds(atIndexOffset: 0).length)
        }
    }
    
    fileprivate init(buffer: ByteBuffer) {
        self.buffer = buffer
    }
    
    func subDescription(offset: Int) -> ReadOnlyJSONDescription {
        return ReadOnlyJSONDescription(buffer: buffer.getSlice(at: offset, length: buffer.readableBytes - offset)!)
    }
    
    var topLevelType: JSONType {
        return type(atOffset: 0)
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
        inPointer json: UnsafePointer<UInt8>,
        unicode: Bool,
        fromOffset offset: Int = Constants.firstArrayObjectChildOffset
    ) -> Bool {
        return valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: json) != nil
    }
    
    func keyOffset(
        forKey key: String,
        convertingSnakeCasing: Bool,
        in json: UnsafePointer<UInt8>
    ) -> (index: Int, offset: Int)? {
        // Object index
        var index = 0
        var offset = Constants.firstArrayObjectChildOffset
        
        guard let count: Int32 = self.buffer.getInteger(at: Constants.arrayObjectPairCountOffset) else {
            return nil
        }
        
        let key = [UInt8](key.utf8)
        let keySize = key.count
        
        for _ in 0..<count {
            // Fetch the bounds for the key in JSON
            let bounds = dataBounds(atIndexOffset: offset)
            
            // Does the key match our search?
            if !convertingSnakeCasing, bounds.length == keySize, memcmp(key, json + Int(bounds.offset), Int(bounds.length)) == 0 {
                return (index, offset)
            } else if convertingSnakeCasing, snakeCasedEqual(key: key, pointer: json + Int(bounds.offset), length: Int(bounds.length)) {
                return (index, offset)
            }
            
            // Skip key
            skipIndex(atOffset: &offset)
            
            // Skip value
            skipIndex(atOffset: &offset)
            index = index &+ 1
        }
        
        return nil
    }
    
    func type(atOffset offset: Int) -> JSONType {
        guard let typeByte: UInt8 = buffer.getInteger(at: offset), let type = JSONType(rawValue: typeByte) else {
            fatalError("The JSON index is corrupt. No JSON Type could be found at offset \(offset). Please file a bug report on Github.")
        }
        
        return type
    }
    
    func skipIndex(atOffset offset: inout Int) {
        assert(offset <= buffer.readableBytes)
        offset = offset &+ indexLength(atOffset: offset)
    }
    
    func indexLength(atOffset offset: Int) -> Int {
        // Force unwrap because this is all internal code, if this crashes JSON is broken
        switch type(atOffset: offset) {
        case .object, .array:
            guard let childrenLength: Int32 = buffer.getInteger(at: offset + Constants.arrayObjectTotalIndexLengthOffset) else {
                fatalError("The JSON index is corrupt. No IndexLength could be found for all children of an object or array. Please file a bug report on Github.")
            }
            
            assert(childrenLength <= Int32(buffer.readableBytes))
            return Constants.arrayObjectIndexLength + Int(childrenLength)
        case .boolTrue, .boolFalse, .null:
            // Type byte + location
            return Constants.boolNullIndexLength
        case .string, .stringWithEscaping, .integer, .floatingNumber:
            return Constants.stringNumberIndexLength
        }
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
        skipIndex(atOffset: &offset)
        
        return (index, offset)
    }
    
    func offset(forIndex index: Int) -> Int {
        assert(self.topLevelType == .array)
        var offset = Constants.firstArrayObjectChildOffset
        for _ in 0..<index {
            skipIndex(atOffset: &offset)
        }
        
        return offset
    }
    
    func type(
        ofKey key: String,
        convertingSnakeCasing: Bool,
        in buffer: UnsafePointer<UInt8>
    ) -> JSONType? {
        guard let (_, offset) = valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: buffer) else {
            return nil
        }
        
        return self.type(atOffset: offset)
    }
    
    func keys(
        inPointer buffer: UnsafePointer<UInt8>,
        unicode: Bool,
        convertingSnakeCasing: Bool,
        atIndex offset: Int = Constants.firstArrayObjectChildOffset
    ) -> [String] {
        assert(self.topLevelType == .object)
        
        let count = arrayObjectCount()
        var offset = offset
        
        var keys = [String]()
        keys.reserveCapacity(numericCast(count))
        
        for _ in 0..<count {
            let bounds = dataBounds(atIndexOffset: offset)
            let escaping = self.type(atOffset: offset) == .stringWithEscaping
            
            if var stringData = bounds.makeStringData(from: buffer, escaping: escaping, unicode: unicode) {
                if convertingSnakeCasing {
                    convertSnakeCasing(for: &stringData)
                }
                
                if let key = String(data: stringData, encoding: .utf8) {
                    keys.append(key)
                }
            }
            
            skipIndex(atOffset: &offset)
            skipIndex(atOffset: &offset)
        }
        
        return keys
    }
    
    func arrayObjectCount() -> Int {
        assert(self.topLevelType == .array || self.topLevelType == .object)
        
        guard let count: Int32 = buffer.getInteger(at: Constants.arrayObjectPairCountOffset) else {
            fatalError("Invalid Array or Object description. Missing header data. Please file an issue on Github.")
        }
        
        return Int(count)
    }
    
    func dataBounds(atIndexOffset indexOffset: Int) -> Bounds {
        let jsonOffset = self.jsonOffset(at: indexOffset)
        
        switch self.type(atOffset: indexOffset) {
        case .boolFalse:
            return Bounds(
                offset: jsonOffset,
                length: 5
            )
        case .boolTrue, .null:
            return Bounds(
                offset: jsonOffset,
                length: 4
            )
        case .string, .stringWithEscaping:
            return Bounds(
                offset: jsonOffset &+ 1,
                length: jsonLength(at: indexOffset) &- 2
            )
        case .object, .array, .integer, .floatingNumber:
            return Bounds(
                offset: jsonOffset,
                length: jsonLength(at: indexOffset)
            )
        }
    }
    
    func jsonBounds(at indexOffset: Int) -> Bounds {
        let jsonOffset = self.jsonOffset(at: indexOffset)
        
        switch self.type(atOffset: indexOffset) {
        case .boolFalse:
            return Bounds(
                offset: jsonOffset,
                length: 5
            )
        case .boolTrue, .null:
            return Bounds(
                offset: jsonOffset,
                length: 4
            )
        case .object, .array, .string, .stringWithEscaping, .integer, .floatingNumber:
            return Bounds(
                offset: jsonOffset,
                length: jsonLength(at: indexOffset)
            )
        }
    }
    
    private func jsonLength(at indexOffset: Int) -> Int32 {
        guard let length: Int32 = buffer.getInteger(at: indexOffset + Constants.jsonLengthOffset) else {
            fatalError("Missing data to form a JSONLength. Please file an issue on Github")
        }
        
        return length
    }
    
    /// The offset where you can find this value in JSON
    private func jsonOffset(at indexOffset: Int) -> Int32 {
        guard let offset: Int32 = buffer.getInteger(at: indexOffset + Constants.jsonLocationOffset) else {
            fatalError("Invalid Array or Object description. Missing header data. Please file an issue on Github.")
        }
        
        return offset
    }
    
    func stringBounds(forKey key: String, convertingSnakeCasing: Bool, in pointer: UnsafePointer<UInt8>) -> (Bounds, Bool)? {
        guard
            let (_, offset) = valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: pointer)
        else {
            return nil
        }
        
        let type = self.type(atOffset: offset)
        guard type == .string || type == .stringWithEscaping else { return nil }
        
        let bounds = dataBounds(atIndexOffset: offset)
        
        return (bounds, type == .stringWithEscaping)
    }
    
    func integerBounds(forKey key: String, convertingSnakeCasing: Bool, in pointer: UnsafePointer<UInt8>) -> Bounds? {
        guard
            let (_, offset) = valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: pointer)
        else {
            return nil
        }
        
        let type = self.type(atOffset: offset)
        guard type == .integer else { return nil }
        
        return dataBounds(atIndexOffset: offset)
    }
    
    func floatingBounds(forKey key: String, convertingSnakeCasing: Bool, in pointer: UnsafePointer<UInt8>) -> (Bounds, Bool)? {
        guard
            let (_, offset) = valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: pointer)
        else {
            return nil
        }
        
        let type = self.type(atOffset: offset)
        guard type == .integer || type == .floatingNumber else { return nil }
        
        return (dataBounds(atIndexOffset: offset), type == .floatingNumber)
    }
}


struct _ArrayObjectDescription {
    let valueCount: Int32
    let jsonByteCount: Int32
}

enum JSONType: UInt8 {
    /// 0x00 is skipped so that uninitialized memory doesn't cause confusion
    case object = 0x01
    case array = 0x02
    case boolTrue = 0x03
    case boolFalse = 0x04
    case string = 0x05
    case stringWithEscaping = 0x06
    case integer = 0x07
    case floatingNumber = 0x08
    case null = 0x09
}
