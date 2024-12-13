import Foundation
import NIOCore
import JSONCore

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
public struct JSONDescription: JSONTokenizerDestination {
    public struct ArrayStartContext: Sendable {
        fileprivate let indexOffset: Int
        fileprivate let firstChildIndexOffset: Int
    }
    public struct ObjectStartContext: Sendable {
        fileprivate let indexOffset: Int
        fileprivate let firstChildIndexOffset: Int
    }

    public mutating func booleanTrueFound(_ boolean: JSONToken.BooleanTrue) {
        describeTrue(atJSONOffset: Int32(boolean.start.byteOffset))
    }

    public mutating func booleanFalseFound(_ boolean: JSONToken.BooleanFalse) {
        describeFalse(atJSONOffset: Int32(boolean.start.byteOffset))
    }

    public mutating func nullFound(_ null: JSONToken.Null) {
        describeNull(atJSONOffset: Int32(null.start.byteOffset))
    }

    public mutating func stringFound(_ string: JSONToken.String) {
        describeString(string)
    }

    public mutating func numberFound(_ number: JSONToken.Number) {
        describeNumber(number)
    }

    public mutating func arrayStartFound(_ start: JSONToken.ArrayStart) -> ArrayStartContext {
        describeArray(atJSONOffset: Int32(start.start.byteOffset))
    }

    public mutating func arrayEndFound(
        _ end: JSONToken.ArrayEnd,
        context: consuming ArrayStartContext
    ) {
        complete(context, withResult: end)
    }

    public mutating func objectStartFound(_ start: JSONToken.ObjectStart) -> ObjectStartContext {
        describeObject(atJSONOffset: Int32(start.start.byteOffset))
    }

    public mutating func objectEndFound(
        _ end: JSONToken.ObjectEnd,
        context: consuming ObjectStartContext
    ) {
        complete(context, withResult: end)
    }

    internal var buffer: ByteBuffer

    func slice(from offset: Int, length: Int) -> JSONDescription {
        return JSONDescription(buffer: buffer.getSlice(at: offset, length: length)!)
    }
    
    private init(buffer: ByteBuffer) {
        self.buffer = buffer
    }
    
    /// Creates a new JSONDescription reserving 512 bytes by default.
    init(size: Int = 512) {
        self.buffer = ByteBufferAllocator().buffer(capacity: size)
    }
    
    /// Resets the used capacity which would enable reusing this description
    mutating func recycle() {
        self.buffer.moveWriterIndex(to: 0)
    }
}

extension ByteBuffer {
    mutating func removeBytes(atOffset offset: Int, oldSize: Int) {
        prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: 0)
    }
    
    mutating func prepareForRewrite(atOffset offset: Int, oldSize: Int, newSize: Int) {
        // `if newSize == 5 && oldSize == 3` then We need to write over 0..<5
        // Meaning we move the rest back by (5 - 3 = 2)
        
        // Or if `newSize == 3 && oldSize == 5` we write over 0..<3 and move forward by 2 (or -2 offset)
        let diff = newSize - oldSize
        
        if diff == 0 { return }
        let writerIndex = self.writerIndex
        reserveCapacity(writerIndex + diff)
        
        let endIndex = offset + oldSize
        let remainder = writerIndex - endIndex
        
        if remainder > 0 {
            self.withUnsafeMutableReadableBytes { buffer in
                let pointer = buffer.baseAddress!
                
                let source = pointer + endIndex
                let destination = source + diff
                
                memmove(destination, source, remainder)
            }
        }
        
        moveWriterIndex(to: writerIndex + diff)
    }
    
    mutating func advance(at offset: Int, by value: Int32) {
        guard let old: Int32 = getInteger(at: offset) else {
            assertionFailure("The JSON index is corrupt. There were not enough bytes to fetch a JSON value's location. Please file a bug report on Github")
            return
        }
        
        assert(!old.addingReportingOverflow(value).overflow)
        
        setInteger(old &+ value, at: offset)
    }
}

extension JSONDescription {
    /// Inserts an object or array's JSONDescription and it's children into this one
    /// The supplied Int is the location where the value will be stored in JSON
    /// This will be used to update all locations in JSON accordingly
    mutating func addNestedDescription(_ description: JSONDescription, at jsonOffset: Int32) {
        var description = description
        description.advanceAllJSONOffsets(by: jsonOffset)
        self.buffer.writeBuffer(&description.buffer)
    }
    
    /// Moves this index description and all it's child descriptions their JSON offsets forward
    mutating func advanceAllJSONOffsets(by jsonOffset: Int32) {
        self.buffer.advance(at: Constants.jsonLocationOffset, by: jsonOffset)
        
        var indexOffset = Constants.firstArrayObjectChildOffset
        
        while indexOffset < buffer.writerIndex {
            self.buffer.advance(at: indexOffset + Constants.jsonLocationOffset, by: jsonOffset)
            indexOffset = indexOffset &+ type(atOffset: indexOffset).indexLength
        }
    }
    
    var topLevelType: JSONType {
        return type(atOffset: 0)
    }
    
    func arrayObjectCount() -> Int {
        assert(self.topLevelType == .array || self.topLevelType == .object)
        
        guard let count: Int32 = buffer.getInteger(at: Constants.arrayObjectPairCountOffset) else {
            fatalError("Invalid Array or Object description. Missing header data. Please file an issue on Github.")
        }
        
        return Int(count)
    }
    
    func type(atOffset offset: Int) -> JSONType {
        assert(offset < buffer.writerIndex)
        
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
            
            assert(childrenLength <= Int32(buffer.writerIndex))
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
    
    /// Removes a key-value pair from object descriptions only.
    /// Removes both the key and the value from this description
    mutating func removeObjectDescription(atKeyIndex keyOffset: Int, jsonOffset: Int, removedJSONLength: Int) {
        assert(topLevelType == .object)

        // Remove key AND value
        // First include the key length
        let keyIndexLength = indexLength(atOffset: keyOffset)
        
        // Join the value's index length with the key's
        let valueIndexLength = indexLength(atOffset: keyOffset + keyIndexLength)
        
        let removedIndexLength = keyIndexLength + valueIndexLength

        // Remove the object index
        buffer.removeBytes(atOffset: keyOffset, oldSize: removedIndexLength)
        
        buffer.advance(at: Constants.arrayObjectTotalIndexLengthOffset, by: Int32(-removedIndexLength))
        buffer.advance(at: Constants.arrayObjectPairCountOffset, by: -1)
        buffer.advance(at: Constants.jsonLengthOffset, by: Int32(-removedJSONLength))

        var updateLocationOffset = Constants.firstArrayObjectChildOffset
        
        // Move back offsets >= the removed offset
        for _ in 0..<arrayObjectCount() {
            let successivePair = dataBounds(atIndexOffset: updateLocationOffset).offset >= jsonOffset

            // Key
            if successivePair {
                buffer.advance(at: updateLocationOffset + Constants.jsonLocationOffset, by: Int32(-removedJSONLength))
            }
            skipIndex(atOffset: &updateLocationOffset)

            // Value
            if successivePair {
                buffer.advance(at: updateLocationOffset + Constants.jsonLocationOffset, by: Int32(-removedJSONLength))
            }
            skipIndex(atOffset: &updateLocationOffset)
        }
    }

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

    /// Assumes `self` to be a description of a `JSONObject`
    mutating func incrementObjectCount(jsonSize: Int32, atValueIndexOffset valueOffset: Int) {
        assert(topLevelType == .object)

        let valueIndexLength = self.indexLength(atOffset: valueOffset)
        
        let addedIndexSize = Int32(Constants.stringNumberIndexLength + valueIndexLength)
        
        // Increment the index and json length accordingly
        buffer.advance(at: Constants.arrayObjectTotalIndexLengthOffset, by: addedIndexSize)
        buffer.advance(at: Constants.jsonLengthOffset, by: jsonSize)
        
        // Update the pair count by 1, since a value was added
        buffer.advance(at: Constants.arrayObjectPairCountOffset, by: 1)
    }

    /// Assumes `self` to be a description of a `JSONArray`
    mutating func incrementArrayCount(jsonSize: Int32, atIndexOffset indexOffset: Int) {
        assert(topLevelType == .array)
        
        // Fetches the indexLength of the newly added value
        let addedIndexLength = self.indexLength(atOffset: indexOffset)
        
        // Increment the index and json length accordingly
        buffer.advance(at: Constants.arrayObjectTotalIndexLengthOffset, by: Int32(addedIndexLength))
        buffer.advance(at: Constants.jsonLengthOffset, by: jsonSize)
        
        // Update the pair count by 1, since a value was added
        buffer.advance(at: Constants.arrayObjectPairCountOffset, by: 1)
    }

    mutating func rewrite(buffer: inout ByteBuffer, to value: JSONValue, at indexOffset: Int) {
        let jsonBounds = self.jsonBounds(at: indexOffset)

        let length: Int32

        defer {
            addJSONSize(of: length - jsonBounds.length)
        }

        switch value {
        case let string as String:
            let baseOffset = Int(jsonBounds.offset)
            let (escaped, characters) = string.escaped
            
            let characterCount = characters.count
            let _length = characterCount + 2
            length = Int32(_length)
            
            buffer.prepareForRewrite(atOffset: baseOffset, oldSize: Int(jsonBounds.length), newSize: _length)
            buffer.setInteger(UInt8.quote, at: baseOffset)
            buffer.setBytes(characters, at: baseOffset + 1)
            buffer.setInteger(UInt8.quote, at: baseOffset + 1 + characters.count)

            rewriteString(
                JSONToken.String(
                    start: JSONSourcePosition(byteIndex: baseOffset),
                    byteLength: _length,
                    usesEscaping: escaped
                ),
                atIndexOffset: indexOffset
            )
        case let double as Double:
            let textualDouble = String(double)
            let _length = textualDouble.utf8.count
            length = Int32(_length)
            let baseOffset = Int(jsonBounds.offset)

            buffer.prepareForRewrite(atOffset: baseOffset, oldSize: Int(jsonBounds.length), newSize: _length)
            // TODO: Serialize without using String
            buffer.setString(textualDouble, at: baseOffset)

            rewriteNumber(
                JSONToken.Number(
                    start: JSONSourcePosition(byteIndex: baseOffset),
                    byteLength: _length,
                    isInteger: false
                ),
                atIndexOffset: indexOffset
            )
        case let int as Int:
            let textualInt = String(int)
            let _length = textualInt.utf8.count
            length = Int32(_length)
            let baseOffset = Int(jsonBounds.offset)

            buffer.prepareForRewrite(atOffset: baseOffset, oldSize: Int(jsonBounds.length), newSize: _length)
            // TODO: Serialize without using String
            buffer.setString(textualInt, at: baseOffset)
            
            rewriteNumber(
                JSONToken.Number(
                    start: JSONSourcePosition(byteIndex: baseOffset),
                    byteLength: _length,
                    isInteger: true
                ),
                atIndexOffset: indexOffset
            )
        case let bool as Bool:
            if bool {
                length = 4
                buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 4)
                
                _ = buffer.setStaticString(boolTrue, at: Int(jsonBounds.offset))
                rewriteTrue(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
            } else {
                length = 5
                buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 5)
                
                _ = buffer.setStaticString(boolFalse, at: Int(jsonBounds.offset))
                rewriteFalse(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
            }
        case let object as JSONObject:
            let _length = object.jsonBuffer.writerIndex
            length = Int32(_length)
            
            buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: _length)
            buffer.setBuffer(object.jsonBuffer, at: Int(jsonBounds.offset))
            var newDescription = object.description
            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
            rewriteObjectArray(locallyAt: indexOffset, from: newDescription)
        case let array as JSONArray:
            let _length = array.jsonBuffer.writerIndex
            length = Int32(_length)
            
            buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: _length)
            buffer.setBuffer(array.jsonBuffer, at: Int(jsonBounds.offset))
            var newDescription = array.description
            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
            rewriteObjectArray(locallyAt: indexOffset, from: newDescription)
        default:
            length = 4
            buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 4)
            
            _ = buffer.setStaticString(nullBytes, at: Int(jsonBounds.offset))
            rewriteTrue(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
        }
    }

    mutating func addJSONSize(of size: Int32) {
        assert(topLevelType == .object || topLevelType == .object)

        buffer.advance(at: Constants.jsonLengthOffset, by: size)
    }

    mutating func rewriteNumber(
        _ number: JSONToken.Number,
        atIndexOffset offset: Int
    ) {
        let type: JSONType = number.isInteger ? .integer : .floatingNumber
        let oldSize = indexLength(atOffset: offset)

        buffer.prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: Constants.stringNumberIndexLength)

        buffer.setInteger(type.rawValue, at: offset)
        buffer.setInteger(Int32(number.start.byteOffset), at: offset + Constants.jsonLocationOffset)
        buffer.setInteger(Int32(number.byteLength), at: offset + Constants.jsonLengthOffset)
    }

    mutating func rewriteString(_ string: JSONToken.String, atIndexOffset offset: Int) {
        let type: JSONType = string.usesEscaping ? .stringWithEscaping : .string
        let oldSize = indexLength(atOffset: offset)

        buffer.prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: Constants.stringNumberIndexLength)

        buffer.setInteger(type.rawValue, at: offset)
        buffer.setInteger(Int32(string.start.byteOffset), at: offset + Constants.jsonLocationOffset)
        buffer.setInteger(Int32(string.byteLength), at: offset + Constants.jsonLengthOffset)
    }

    private mutating func rewriteShortType(to type: JSONType, indexOffset: Int, jsonOffset: Int32) {
        let oldSize = indexLength(atOffset: indexOffset)

        buffer.prepareForRewrite(atOffset: indexOffset, oldSize: oldSize, newSize: Constants.boolNullIndexLength)

        buffer.setInteger(type.rawValue, at: indexOffset)
        buffer.setInteger(jsonOffset, at: indexOffset + Constants.jsonLocationOffset)
    }

    mutating func rewriteNull(atIndexOffset indexOffset: Int, jsonOffset: Int32) {
        rewriteShortType(to: .null, indexOffset: indexOffset, jsonOffset: jsonOffset)
    }
    
    mutating func rewriteTrue(atIndexOffset offset: Int, jsonOffset: Int32) {
        rewriteShortType(to: .boolTrue, indexOffset: offset, jsonOffset: jsonOffset)
    }
    
    mutating func rewriteFalse(atIndexOffset offset: Int, jsonOffset: Int32) {
        rewriteShortType(to: .boolFalse, indexOffset: offset, jsonOffset: jsonOffset)
    }
    
    mutating func rewriteObjectArray(locallyAt localOffset: Int, from newDescription: JSONDescription) {
        let oldLength = self.indexLength(atOffset: localOffset)
        let newLength = newDescription.indexLength(atOffset: 0)
        
        buffer.prepareForRewrite(atOffset: localOffset, oldSize: oldLength, newSize: newLength)
        
        buffer.setBuffer(newDescription.buffer, at: localOffset)
    }
    
    mutating func describeString(_ string: JSONToken.String) {
        let type: JSONType = string.usesEscaping ? .stringWithEscaping : .string

        // TODO: Host endianness is faster
        buffer.writeInteger(type.rawValue)
        buffer.writeInteger(Int32(string.start.byteOffset))
        buffer.writeInteger(Int32(string.byteLength))
    }
    
    mutating func describeNumber(_ number: JSONToken.Number) {
        // Make a destinction between floating points and integers
        let type = number.isInteger ? JSONType.integer.rawValue : JSONType.floatingNumber.rawValue

        // Set the new type identifier
        self.buffer.writeInteger(type)
        
        self.buffer.writeInteger(Int32(number.start.byteOffset))
        self.buffer.writeInteger(Int32(number.byteLength))
    }
    
    mutating func describeTrue(atJSONOffset jsonOffset: Int32) {
        buffer.writeInteger(JSONType.boolTrue.rawValue)
        buffer.writeInteger(jsonOffset)
    }
    
    mutating func describeFalse(atJSONOffset jsonOffset: Int32) {
        buffer.writeInteger(JSONType.boolFalse.rawValue)
        buffer.writeInteger(jsonOffset)
    }
    
    mutating func describeNull(atJSONOffset jsonOffset: Int32) {
        buffer.writeInteger(JSONType.null.rawValue)
        buffer.writeInteger(jsonOffset)
    }
    
    mutating func describeArray(atJSONOffset jsonOffset: Int32) -> ArrayStartContext {
        let indexOffset = buffer.writerIndex
        buffer.writeInteger(JSONType.array.rawValue)
        buffer.writeInteger(jsonOffset)
        buffer.reserveCapacity(buffer.readableBytes + 12)
        buffer.moveWriterIndex(forwardBy: 12)
        
        return ArrayStartContext(
            indexOffset: indexOffset,
            firstChildIndexOffset: buffer.writerIndex
        )
    }
    
    mutating func describeObject(atJSONOffset jsonOffset: Int32) -> ObjectStartContext {
        let indexOffset = buffer.writerIndex
        buffer.writeInteger(JSONType.object.rawValue)
        buffer.writeInteger(jsonOffset)
        buffer.reserveCapacity(buffer.readableBytes + 12)
        buffer.moveWriterIndex(forwardBy: 12)
        
        return ObjectStartContext(
            indexOffset: indexOffset,
            firstChildIndexOffset: buffer.writerIndex
        )
    }

    mutating func complete(
        _ unfinished: ObjectStartContext,
        withResult result: JSONToken.ObjectEnd
    ) {
        buffer.setInteger(
            Int32(result.byteLength),
            at: unfinished.indexOffset &+ Constants.jsonLengthOffset
        )
        buffer.setInteger(
            Int32(result.memberCount),
            at: unfinished.indexOffset &+ Constants.arrayObjectPairCountOffset
        )

        let indexLength = buffer.writerIndex &- unfinished.firstChildIndexOffset
        buffer.setInteger(Int32(indexLength), at: unfinished.indexOffset &+ Constants.arrayObjectTotalIndexLengthOffset)
    }

    mutating func complete(_ unfinished: ArrayStartContext, withResult result: JSONToken.ArrayEnd) {
        buffer.setInteger(
            Int32(result.byteLength),
            at: unfinished.indexOffset &+ Constants.jsonLengthOffset
        )
        buffer.setInteger(
            Int32(result.memberCount),
            at: unfinished.indexOffset &+ Constants.arrayObjectPairCountOffset
        )

        let indexLength = buffer.writerIndex &- unfinished.firstChildIndexOffset
        buffer.setInteger(Int32(indexLength), at: unfinished.indexOffset &+ Constants.arrayObjectTotalIndexLengthOffset)
    }
}

extension String {
    internal func convertSnakeCasing() -> String {
        var utf8 = Array(self.utf8)
        let size = utf8.count
        var i = size
        
        while i > 0 {
            i &-= 1
            
            let byte = utf8[i]
            if byte >= .A && byte <= .Z {
                // make lowercased
                utf8[i] &+= 0x20
                utf8.insert(.underscore, at: i)
            }
        }
        
        return String(bytes: utf8, encoding: .utf8)!
    }
}

extension JSONDescription {
    func subDescription(offset: Int) -> JSONDescription {
        return JSONDescription(buffer: buffer.getSlice(at: offset, length: buffer.readableBytes - offset)!)
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
    
    private func snakeCasedEqual(key: UnsafeBufferPointer<UInt8>, pointer: UnsafePointer<UInt8>, length: Int) -> Bool {
        let keySize = key.count
        var characters = Data(bytes: pointer, count: length)
        // TODO: Compare without copy
        convertSnakeCasing(for: &characters)
        
        // The string was guaranteed by us to still be valid UTF-8
        let byteCount = characters.count
        if byteCount == keySize {
            return characters.withUnsafeBytes { buffer in
                return memcmp(key.baseAddress!, buffer.baseAddress!, keySize) == 0
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
        
        guard
            let count: Int32 = self.buffer.getInteger(at: Constants.arrayObjectPairCountOffset),
            count > 0
        else {
            return nil
        }

        var key = key
        return key.withUTF8 { key in
            let keySize = key.count

            for _ in 0..<count {
                // Fetch the bounds for the key in JSON
                let bounds = dataBounds(atIndexOffset: offset)

                // Does the key match our search?
                if !convertingSnakeCasing, bounds.length == keySize, memcmp(key.baseAddress!, json + Int(bounds.offset), Int(bounds.length)) == 0 {
                    return (index, offset)
                } else if convertingSnakeCasing, snakeCasedEqual(
                    key: key,
                    pointer: json + Int(bounds.offset),
                    length: Int(bounds.length)
                ) {
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

            let string = JSONToken.String(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                usesEscaping: self.type(atOffset: offset) == .stringWithEscaping
            )

            if var stringData = try? string.makeStringData(from: buffer, unicode: unicode) {
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

    /// While similar to `jsonBounds`, it denotes the data of _interest_. Specifically for a `String`, these are the contents between
    /// quotes
    func dataBounds(atIndexOffset indexOffset: Int) -> (offset: Int32, length: Int32) {
        let jsonOffset = self.jsonOffset(at: indexOffset)
        
        switch self.type(atOffset: indexOffset) {
        case .boolFalse:
            return (
                offset: jsonOffset,
                length: 5
            )
        case .boolTrue, .null:
            return (
                offset: jsonOffset,
                length: 4
            )
        case .string, .stringWithEscaping:
            return (
                offset: jsonOffset &+ 1,
                length: jsonLength(at: indexOffset) &- 2
            )
        case .object, .array, .integer, .floatingNumber:
            return (
                offset: jsonOffset,
                length: jsonLength(at: indexOffset)
            )
        }
    }

    /// The bounds of the entire JSON token, including quotes for a String
    func jsonBounds(at indexOffset: Int) -> (offset: Int32, length: Int32) {
        let jsonOffset = self.jsonOffset(at: indexOffset)
        
        switch self.type(atOffset: indexOffset) {
        case .boolFalse:
            return (
                offset: jsonOffset,
                length: 5
            )
        case .boolTrue, .null:
            return (
                offset: jsonOffset,
                length: 4
            )
        case .object, .array, .string, .stringWithEscaping, .integer, .floatingNumber:
            return (
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
    
    func stringBounds(
        forKey key: String,
        convertingSnakeCasing: Bool,
        in pointer: UnsafePointer<UInt8>
    ) -> JSONToken.String? {
        guard
            let (_, offset) = valueOffset(
                forKey: key,
                convertingSnakeCasing: convertingSnakeCasing,
                in: pointer
            )
        else {
            return nil
        }
        
        let type = self.type(atOffset: offset)
        guard type == .string || type == .stringWithEscaping else { return nil }
        
        let bounds = dataBounds(atIndexOffset: offset)
        return JSONToken.String(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            usesEscaping: type == .stringWithEscaping
        )
    }
    
    func integerBounds(
        forKey key: String,
        convertingSnakeCasing: Bool,
        in pointer: UnsafePointer<UInt8>
    ) -> JSONToken.Number? {
        guard
            let (_, offset) = valueOffset(
                forKey: key,
                convertingSnakeCasing: convertingSnakeCasing,
                in: pointer
            )
        else {
            return nil
        }
        
        let type = self.type(atOffset: offset)
        guard type == .integer else { return nil }

        let bounds = dataBounds(atIndexOffset: offset)
        return JSONToken.Number(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            end: JSONSourcePosition(byteIndex: Int(bounds.offset + bounds.length)),
            isInteger: true
        )
    }
    
    func floatingBounds(
        forKey key: String,
        convertingSnakeCasing: Bool,
        in pointer: UnsafePointer<UInt8>
    ) -> JSONToken.Number? {
        guard
            let (_, offset) = valueOffset(
                forKey: key,
                convertingSnakeCasing: convertingSnakeCasing,
                in: pointer
            )
        else {
            return nil
        }
        
        let type = self.type(atOffset: offset)
        guard type == .integer || type == .floatingNumber else { return nil }

        let bounds = dataBounds(atIndexOffset: offset)
        return JSONToken.Number(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            isInteger: type == .integer
        )
    }
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

    var indexLength: Int {
        switch self {
        case .object, .array:
            return Constants.arrayObjectIndexLength
        case .boolTrue, .boolFalse, .null:
            return Constants.boolNullIndexLength
        case .integer, .floatingNumber, .string, .stringWithEscaping:
            return Constants.stringNumberIndexLength
        }
    }
}
