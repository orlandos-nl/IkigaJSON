import Foundation
import NIOCore
import _JSONCore

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
package final class JSONDescription: JSONTokenizerDestination {
    private var pointer: UnsafeMutableRawBufferPointer
    package private(set) var writtenBytes = 0
    private let readOnlyCopy: Bool

    init(
        unsafeReadOnlySubDescriptionOf description: JSONDescription,
        offset: Int
    ) {
        self.readOnlyCopy = true
        self.pointer = .init(
            start: description.pointer.baseAddress! + offset,
            count: description.writtenBytes - offset
        )
        self.writtenBytes = description.pointer.count - offset
    }

    @discardableResult
    @inlinable
    package func writeInteger<T: FixedWidthInteger>(
        _ integer: T,
        as: T.Type = T.self
    ) -> Int {
        ensureWritableRoom(for: MemoryLayout<T>.size)
        let bytesWritten = self.setInteger(integer, at: self.writtenBytes)
        writtenBytes += bytesWritten
        return Int(bytesWritten)
    }

    @discardableResult
    @inlinable
    package func setInteger<T: FixedWidthInteger>(_ integer: T, at index: Int) -> Int {
        let size = MemoryLayout<T>.size
        precondition(index >= 0 && index + size <= pointer.count, "Writing out of bounds")
        pointer.baseAddress!.storeBytes(of: integer, toByteOffset: index, as: T.self)
        return size
    }

    package func getInteger<T: FixedWidthInteger>(at index: Int, as type: T.Type = T.self) -> T? {
        precondition(index >= 0, "Reading out of bounds")
        let size = MemoryLayout<T>.size
        guard index + size <= writtenBytes else {
            return nil
        }

        return pointer.baseAddress!.loadUnaligned(fromByteOffset: index, as: T.self)
    }

    package func setBuffer(to jsonDescription: JSONDescription, at offset: Int) {
        precondition(offset >= 0, "Writing out of bounds")
        ensureWritableRoom(for: offset + jsonDescription.writtenBytes)
        memcpy(
            pointer.baseAddress! + offset,
            jsonDescription.pointer.baseAddress!,
            jsonDescription.writtenBytes
        )
    }

    package func writeBuffer(_ jsonDescription: JSONDescription) {
        ensureWritableRoom(for: jsonDescription.writtenBytes)
        memcpy(
            pointer.baseAddress! + writtenBytes,
            jsonDescription.pointer.baseAddress!,
            jsonDescription.writtenBytes
        )
        writtenBytes += jsonDescription.writtenBytes
    }

    private func ensureWritableRoom(for size: Int) {
        if writtenBytes + size >= pointer.count {
            expand(minimumCapacity: writtenBytes + size)
        }
    }

    private func expand(minimumCapacity: Int) {
        let newSize = max(pointer.count &* 2, minimumCapacity)
        let newPointer = realloc(pointer.baseAddress!, newSize)
        pointer = UnsafeMutableRawBufferPointer(start: newPointer, count: newSize)
    }

    package func moveWriterIndex(forwardBy offset: Int) {
        ensureWritableRoom(for: offset)
        writtenBytes += offset
    }

    deinit {
        if !readOnlyCopy {
            pointer.deallocate()
        }
    }

    public struct ArrayStartContext: Sendable {
        fileprivate let indexOffset: Int
        fileprivate let firstChildIndexOffset: Int
    }
    public struct ObjectStartContext: Sendable {
        fileprivate let indexOffset: Int
        fileprivate let firstChildIndexOffset: Int
    }

    public func booleanTrueFound(_ boolean: JSONToken.BooleanTrue) {
        describeTrue(atJSONOffset: Int32(boolean.start.byteOffset))
    }

    public func booleanFalseFound(_ boolean: JSONToken.BooleanFalse) {
        describeFalse(atJSONOffset: Int32(boolean.start.byteOffset))
    }

    public func nullFound(_ null: JSONToken.Null) {
        describeNull(atJSONOffset: Int32(null.start.byteOffset))
    }

    public func stringFound(_ string: JSONToken.String) {
        describeString(string)
    }

    public func numberFound(_ number: JSONToken.Number) {
        describeNumber(number)
    }

    public func arrayStartFound(_ start: JSONToken.ArrayStart) -> ArrayStartContext {
        describeArray(atJSONOffset: Int32(start.start.byteOffset))
    }

    public func arrayEndFound(
        _ end: JSONToken.ArrayEnd,
        context: consuming ArrayStartContext
    ) {
        complete(context, withResult: end)
    }

    public func objectStartFound(_ start: JSONToken.ObjectStart) -> ObjectStartContext {
        describeObject(atJSONOffset: Int32(start.start.byteOffset))
    }

    public func objectEndFound(
        _ end: JSONToken.ObjectEnd,
        context: consuming ObjectStartContext
    ) {
        complete(context, withResult: end)
    }

    func slice(from offset: Int, length: Int) -> JSONDescription {
        let copy = JSONDescription(size: length)
        copy.pointer.baseAddress!.copyMemory(
            from: pointer.baseAddress! + offset,
            byteCount: length
        )
        copy.writtenBytes = length
        return copy
    }
    
    /// Creates a new JSONDescription reserving 512 bytes by default.
    init(size: Int = 4096) {
        self.pointer = .allocate(byteCount: size, alignment: 1)
        self.readOnlyCopy = false
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
}

extension JSONDescription {
    func removeBytes(atOffset offset: Int, oldSize: Int) {
        prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: 0)
    }

    func prepareForRewrite(atOffset offset: Int, oldSize: Int, newSize: Int) {
        // `if newSize == 5 && oldSize == 3` then We need to write over 0..<5
        // Meaning we move the rest back by (5 - 3 = 2)

        // Or if `newSize == 3 && oldSize == 5` we write over 0..<3 and move forward by 2 (or -2 offset)
        let diff = newSize - oldSize

        if diff == 0 { return }
        if diff > 0 { ensureWritableRoom(for: self.writtenBytes + diff) }

        let endIndex = offset + oldSize
        let remainder = writtenBytes - endIndex

        if remainder > 0 {
            let source = pointer.baseAddress! + endIndex
            let destination = source + diff

            memmove(destination, source, remainder)
        }

        self.writtenBytes += diff
    }

    func advance(at offset: Int, by value: Int32) {
        guard let old: Int32 = getInteger(at: offset) else {
            assertionFailure("The JSON index is corrupt. There were not enough bytes to fetch a JSON value's location. Please file a bug report on Github")
            return
        }

        assert(!old.addingReportingOverflow(value).overflow)

        setInteger(old &+ value, at: offset)
    }

    /// Inserts an object or array's JSONDescription and it's children into this one
    /// The supplied Int is the location where the value will be stored in JSON
    /// This will be used to update all locations in JSON accordingly
    func addNestedDescription(_ description: JSONDescription, at jsonOffset: Int32) {
        let copy = description.slice(from: 0, length: description.writtenBytes)
        copy.advanceAllJSONOffsets(by: jsonOffset)
        self.writeBuffer(copy)
    }

    /// Moves this index description and all it's child descriptions their JSON offsets forward
    func advanceAllJSONOffsets(by jsonOffset: Int32) {
        self.advance(at: Constants.jsonLocationOffset, by: jsonOffset)
        
        var indexOffset = Constants.firstArrayObjectChildOffset
        
        while indexOffset < writtenBytes {
            self.advance(at: indexOffset + Constants.jsonLocationOffset, by: jsonOffset)
            indexOffset = indexOffset &+ type(atOffset: indexOffset).indexLength
        }
    }
    
    var topLevelType: JSONType {
        return type(atOffset: 0)
    }
    
    func arrayObjectCount() -> Int {
        assert(self.topLevelType == .array || self.topLevelType == .object)
        
        guard let count: Int32 = getInteger(
            at: Constants.arrayObjectPairCountOffset
        ) else {
            fatalError("Invalid Array or Object description. Missing header data. Please file an issue on Github.")
        }
        
        return Int(count)
    }
    
    func type(atOffset offset: Int) -> JSONType {
        assert(offset < writtenBytes)
        
        guard let typeByte: UInt8 = getInteger(at: offset), let type = JSONType(rawValue: typeByte) else {
            fatalError("The JSON index is corrupt. No JSON Type could be found at offset \(offset). Please file a bug report on Github.")
        }
        
        return type
    }

    func indexLength(atOffset offset: Int) -> Int {
        // Force unwrap because this is all internal code, if this crashes JSON is broken
        switch type(atOffset: offset) {
        case .object, .array:
            guard let childrenLength: Int32 = getInteger(
                at: offset + Constants.arrayObjectTotalIndexLengthOffset
            ) else {
                fatalError("The JSON index is corrupt. No IndexLength could be found for all children of an object or array. Please file a bug report on Github.")
            }
            
            assert(childrenLength <= Int32(writtenBytes))
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
    func removeObjectDescription(atKeyIndex keyOffset: Int, jsonOffset: Int, removedJSONLength: Int) {
        assert(topLevelType == .object)

        // Remove key AND value
        // First include the key length
        let keyIndexLength = indexLength(atOffset: keyOffset)
        
        // Join the value's index length with the key's
        let valueIndexLength = indexLength(atOffset: keyOffset + keyIndexLength)
        
        let removedIndexLength = keyIndexLength + valueIndexLength

        // Remove the object index
        removeBytes(atOffset: keyOffset, oldSize: removedIndexLength)
        
        advance(at: Constants.arrayObjectTotalIndexLengthOffset, by: Int32(-removedIndexLength))
        advance(at: Constants.arrayObjectPairCountOffset, by: -1)
        advance(at: Constants.jsonLengthOffset, by: Int32(-removedJSONLength))

        var updateLocationOffset = Constants.firstArrayObjectChildOffset
        
        // Move back offsets >= the removed offset
        for _ in 0..<arrayObjectCount() {
            let successivePair = dataBounds(atIndexOffset: updateLocationOffset).offset >= jsonOffset

            // Key
            if successivePair {
                advance(at: updateLocationOffset + Constants.jsonLocationOffset, by: Int32(-removedJSONLength))
            }
            skipIndex(atOffset: &updateLocationOffset)

            // Value
            if successivePair {
                advance(at: updateLocationOffset + Constants.jsonLocationOffset, by: Int32(-removedJSONLength))
            }
            skipIndex(atOffset: &updateLocationOffset)
        }
    }

//    func removeArrayDescription(atIndex indexOffset: Int, jsonOffset: Int, removedLength: JSONLength) {
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
    func incrementObjectCount(jsonSize: Int32, atValueIndexOffset valueOffset: Int) {
        assert(topLevelType == .object)

        let valueIndexLength = self.indexLength(atOffset: valueOffset)
        
        let addedIndexSize = Int32(Constants.stringNumberIndexLength + valueIndexLength)
        
        // Increment the index and json length accordingly
        advance(at: Constants.arrayObjectTotalIndexLengthOffset, by: addedIndexSize)
        advance(at: Constants.jsonLengthOffset, by: jsonSize)
        
        // Update the pair count by 1, since a value was added
        advance(at: Constants.arrayObjectPairCountOffset, by: 1)
    }

    /// Assumes `self` to be a description of a `JSONArray`
    func incrementArrayCount(jsonSize: Int32, atIndexOffset indexOffset: Int) {
        assert(topLevelType == .array)
        
        // Fetches the indexLength of the newly added value
        let addedIndexLength = self.indexLength(atOffset: indexOffset)
        
        // Increment the index and json length accordingly
        advance(at: Constants.arrayObjectTotalIndexLengthOffset, by: Int32(addedIndexLength))
        advance(at: Constants.jsonLengthOffset, by: jsonSize)
        
        // Update the pair count by 1, since a value was added
        advance(at: Constants.arrayObjectPairCountOffset, by: 1)
    }

    func rewrite(buffer: inout ByteBuffer, to value: JSONValue, at indexOffset: Int) {
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
            let newDescription = object.jsonDescription.slice(from: 0, length: object.jsonDescription.writtenBytes)
            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
            rewriteObjectArray(locallyAt: indexOffset, from: newDescription)
        case let array as JSONArray:
            let _length = array.jsonBuffer.writerIndex
            length = Int32(_length)
            
            buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: _length)
            buffer.setBuffer(array.jsonBuffer, at: Int(jsonBounds.offset))
            let newDescription = array.jsonDescription
            newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
            rewriteObjectArray(locallyAt: indexOffset, from: newDescription)
        default:
            length = 4
            buffer.prepareForRewrite(atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 4)

            _ = buffer.setStaticString(nullBytes, at: Int(jsonBounds.offset))
            rewriteTrue(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
        }
    }

    func addJSONSize(of size: Int32) {
        assert(topLevelType == .array || topLevelType == .object)

        advance(at: Constants.jsonLengthOffset, by: size)
    }

    func rewriteNumber(
        _ number: JSONToken.Number,
        atIndexOffset offset: Int
    ) {
        let type: JSONType = number.isInteger ? .integer : .floatingNumber
        let oldSize = indexLength(atOffset: offset)

        prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: Constants.stringNumberIndexLength)

        setInteger(type.rawValue, at: offset)
        setInteger(Int32(number.start.byteOffset), at: offset + Constants.jsonLocationOffset)
        setInteger(Int32(number.byteLength), at: offset + Constants.jsonLengthOffset)
    }

    func rewriteString(_ string: JSONToken.String, atIndexOffset offset: Int) {
        let type: JSONType = string.usesEscaping ? .stringWithEscaping : .string
        let oldSize = indexLength(atOffset: offset)

        prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: Constants.stringNumberIndexLength)

        setInteger(type.rawValue, at: offset)
        setInteger(Int32(string.start.byteOffset), at: offset + Constants.jsonLocationOffset)
        setInteger(Int32(string.byteLength), at: offset + Constants.jsonLengthOffset)
    }

    private func rewriteShortType(to type: JSONType, indexOffset: Int, jsonOffset: Int32) {
        let oldSize = indexLength(atOffset: indexOffset)

        prepareForRewrite(atOffset: indexOffset, oldSize: oldSize, newSize: Constants.boolNullIndexLength)

        setInteger(type.rawValue, at: indexOffset)
        setInteger(jsonOffset, at: indexOffset + Constants.jsonLocationOffset)
    }

    func rewriteNull(atIndexOffset indexOffset: Int, jsonOffset: Int32) {
        rewriteShortType(to: .null, indexOffset: indexOffset, jsonOffset: jsonOffset)
    }
    
    func rewriteTrue(atIndexOffset offset: Int, jsonOffset: Int32) {
        rewriteShortType(to: .boolTrue, indexOffset: offset, jsonOffset: jsonOffset)
    }
    
    func rewriteFalse(atIndexOffset offset: Int, jsonOffset: Int32) {
        rewriteShortType(to: .boolFalse, indexOffset: offset, jsonOffset: jsonOffset)
    }
    
    func rewriteObjectArray(locallyAt localOffset: Int, from newDescription: JSONDescription) {
        let oldLength = self.indexLength(atOffset: localOffset)
        let newLength = newDescription.indexLength(atOffset: 0)
        
        prepareForRewrite(atOffset: localOffset, oldSize: oldLength, newSize: newLength)
        
        setBuffer(to: newDescription, at: localOffset)
    }
    
    func describeString(_ string: JSONToken.String) {
        let type: JSONType = string.usesEscaping ? .stringWithEscaping : .string

        // TODO: Host endianness is faster
        writeInteger(type.rawValue)
        writeInteger(Int32(string.start.byteOffset))
        writeInteger(Int32(string.byteLength))
    }
    
    func describeNumber(_ number: JSONToken.Number) {
        // Make a destinction between floating points and integers
        let type = number.isInteger ? JSONType.integer.rawValue : JSONType.floatingNumber.rawValue

        // Set the new type identifier
        self.writeInteger(type)
        
        self.writeInteger(Int32(number.start.byteOffset))
        self.writeInteger(Int32(number.byteLength))
    }
    
    func describeTrue(atJSONOffset jsonOffset: Int32) {
        writeInteger(JSONType.boolTrue.rawValue)
        writeInteger(jsonOffset)
    }
    
    func describeFalse(atJSONOffset jsonOffset: Int32) {
        writeInteger(JSONType.boolFalse.rawValue)
        writeInteger(jsonOffset)
    }
    
    func describeNull(atJSONOffset jsonOffset: Int32) {
        writeInteger(JSONType.null.rawValue)
        writeInteger(jsonOffset)
    }
    
    func describeArray(atJSONOffset jsonOffset: Int32) -> ArrayStartContext {
        let indexOffset = writtenBytes
        writeInteger(JSONType.array.rawValue)
        writeInteger(jsonOffset)
        moveWriterIndex(forwardBy: 12)
        
        return ArrayStartContext(
            indexOffset: indexOffset,
            firstChildIndexOffset: writtenBytes
        )
    }
    
    func describeObject(atJSONOffset jsonOffset: Int32) -> ObjectStartContext {
        let indexOffset = writtenBytes
        writeInteger(JSONType.object.rawValue)
        writeInteger(jsonOffset)
        moveWriterIndex(forwardBy: 12)
        
        return ObjectStartContext(
            indexOffset: indexOffset,
            firstChildIndexOffset: writtenBytes
        )
    }

    func complete(
        _ unfinished: ObjectStartContext,
        withResult result: JSONToken.ObjectEnd
    ) {
        setInteger(
            Int32(result.byteLength),
            at: unfinished.indexOffset &+ Constants.jsonLengthOffset
        )
        setInteger(
            Int32(result.memberCount),
            at: unfinished.indexOffset &+ Constants.arrayObjectPairCountOffset
        )

        let indexLength = writtenBytes &- unfinished.firstChildIndexOffset
        setInteger(
            Int32(indexLength),
            at: unfinished.indexOffset &+ Constants.arrayObjectTotalIndexLengthOffset
        )
    }

    func complete(_ unfinished: ArrayStartContext, withResult result: JSONToken.ArrayEnd) {
        setInteger(
            Int32(result.byteLength),
            at: unfinished.indexOffset &+ Constants.jsonLengthOffset
        )
        setInteger(
            Int32(result.memberCount),
            at: unfinished.indexOffset &+ Constants.arrayObjectPairCountOffset
        )

        let indexLength = writtenBytes &- unfinished.firstChildIndexOffset
        setInteger(
            Int32(indexLength),
            at: unfinished.indexOffset &+ Constants.arrayObjectTotalIndexLengthOffset
        )
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
    func unsafeReadOnlySubDescription(offset: Int) -> JSONDescription {
        JSONDescription(
            unsafeReadOnlySubDescriptionOf: self,
            offset: offset
        )
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
            let count: Int32 = self.getInteger(
                at: Constants.arrayObjectPairCountOffset
            ),
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
        guard let length: Int32 = getInteger(
            at: indexOffset + Constants.jsonLengthOffset
        ) else {
            fatalError("Missing data to form a JSONLength. Please file an issue on Github")
        }
        
        return length
    }
    
    /// The offset where you can find this value in JSON
    private func jsonOffset(at indexOffset: Int) -> Int32 {
        guard let offset: Int32 = getInteger(
            at: indexOffset + Constants.jsonLocationOffset
        ) else {
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
