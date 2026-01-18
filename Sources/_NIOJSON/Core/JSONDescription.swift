import Foundation
import NIOCore
import _JSONCore

package protocol JSONDescriptionProtocol {
  var storage: [UInt8] { get }
  var writtenBytes: Int { get }
}

extension JSONDescriptionProtocol {
  @inlinable
  package func getInteger<T: FixedWidthInteger>(at index: Int, as type: T.Type = T.self) -> T? {
    precondition(index >= 0, "Reading out of bounds")
    let size = MemoryLayout<T>.size
    guard index + size <= writtenBytes else {
      return nil
    }

    // Read bytes in little-endian order and construct the integer
    var result: T = 0
    for i in 0..<size {
      result |= T(storage[index + i]) << (i * 8)
    }
    return result
  }
}

@usableFromInline
package struct JSONDescriptionView: JSONDescriptionProtocol {
  let description: JSONDescription
  @usableFromInline
  let _offset: UInt32
  @inlinable
  var offset: Int { return Int(self._offset) }
  package var storage: [UInt8] {
    Array(description.storage[offset...])
  }
  package var writtenBytes: Int {
    description.writtenBytes - offset
  }

  package init(description: JSONDescription, offset: Int) {
    self.description = description
    self._offset = UInt32(offset)
  }
}

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
@usableFromInline
package final class JSONDescription: JSONTokenizerDestination, JSONDescriptionProtocol {
  @usableFromInline package var storage: [UInt8]

  @usableFromInline
  package private(set) var writtenBytes: Int = 0

  @discardableResult
  @inlinable
  package func writeInteger<T: FixedWidthInteger>(
    _ integer: T,
    as: T.Type = T.self
  ) -> Int {
    let size = MemoryLayout<T>.size
    ensureWritableRoom(for: size)
    let bytesWritten = self.setInteger(integer, at: self.writtenBytes)
    writtenBytes += bytesWritten
    return Int(bytesWritten)
  }

  @discardableResult
  @inlinable
  package func setInteger<T: FixedWidthInteger>(_ integer: T, at index: Int) -> Int {
    let size = MemoryLayout<T>.size
    precondition(index >= 0 && index + size <= storage.count, "Writing out of bounds")

    // Write bytes in little-endian order
    for i in 0..<size {
      storage[index + i] = UInt8(truncatingIfNeeded: integer >> (i * 8))
    }
    return size
  }

  @inlinable
  package func setBuffer(to jsonDescription: JSONDescription, at offset: Int) {
    precondition(offset >= 0, "Writing out of bounds")
    ensureWritableRoom(for: offset + jsonDescription.writtenBytes)

    // Copy bytes from source to destination
    for i in 0..<jsonDescription.writtenBytes {
      storage[offset + i] = jsonDescription.storage[i]
    }
  }

  @inlinable
  package func writeBuffer(_ jsonDescription: JSONDescription) {
    ensureWritableRoom(for: jsonDescription.writtenBytes)

    // Append bytes from source
    for i in 0..<jsonDescription.writtenBytes {
      storage[writtenBytes + i] = jsonDescription.storage[i]
    }
    writtenBytes += jsonDescription.writtenBytes
  }

  @usableFromInline
  func ensureWritableRoom(for size: Int) {
    let requiredCapacity = writtenBytes + size
    if requiredCapacity > storage.count {
      expand(minimumCapacity: requiredCapacity)
    }
  }

  @inlinable
  func expand(minimumCapacity: Int) {
    let newSize = max(storage.count * 2, minimumCapacity)
    storage.reserveCapacity(newSize)
    // Extend storage with zeros to match new capacity
    while storage.count < newSize {
      storage.append(0)
    }
  }

  func reset() {
    writtenBytes = 0
  }

  @inlinable
  package func moveWriterIndex(forwardBy offset: Int) {
    ensureWritableRoom(for: offset)
    writtenBytes += offset
  }

  public struct ArrayStartContext: Sendable {
    @usableFromInline let indexOffset: Int
    @usableFromInline let firstChildIndexOffset: Int
  }

  public struct ObjectStartContext: Sendable {
    @usableFromInline let indexOffset: Int
    @usableFromInline let firstChildIndexOffset: Int
  }

  @inlinable
  public func booleanTrueFound(_ boolean: JSONToken.BooleanTrue) {
    describeTrue(atJSONOffset: Int32(boolean.start.byteOffset))
  }

  @inlinable
  public func booleanFalseFound(_ boolean: JSONToken.BooleanFalse) {
    describeFalse(atJSONOffset: Int32(boolean.start.byteOffset))
  }

  @inlinable
  public func nullFound(_ null: JSONToken.Null) {
    describeNull(atJSONOffset: Int32(null.start.byteOffset))
  }

  @inlinable
  public func stringFound(_ string: JSONToken.String) {
    describeString(string)
  }

  @inlinable
  public func numberFound(_ number: JSONToken.Number) {
    describeNumber(number)
  }

  @inlinable
  public func arrayStartFound(_ start: JSONToken.ArrayStart) -> ArrayStartContext {
    describeArray(atJSONOffset: Int32(start.start.byteOffset))
  }

  @inlinable
  public func arrayEndFound(
    _ end: JSONToken.ArrayEnd,
    context: consuming ArrayStartContext
  ) {
    complete(context, withResult: end)
  }

  @inlinable
  public func objectStartFound(_ start: JSONToken.ObjectStart) -> ObjectStartContext {
    describeObject(atJSONOffset: Int32(start.start.byteOffset))
  }

  @inlinable
  public func objectEndFound(
    _ end: JSONToken.ObjectEnd,
    context: consuming ObjectStartContext
  ) {
    complete(context, withResult: end)
  }

  @inlinable
  func slice(from offset: Int, length: Int) -> JSONDescription {
    let copy = JSONDescription(size: length)

    // Copy bytes from source to destination
    for i in 0..<length {
      copy.storage[i] = storage[offset + i]
    }
    copy.writtenBytes = length
    return copy
  }

  /// Creates a new JSONDescription
  @inlinable
  init(size: Int = 4096) {
    self.storage = [UInt8](repeating: 0, count: size)
  }
}

extension ByteBuffer {
  @inlinable
  mutating func removeBytes(atOffset offset: Int, oldSize: Int) {
    prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: 0)
  }

  @inlinable
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
      // Use safe ByteBuffer operations instead of memmove
      // Read the trailing bytes, then write them at the new position
      if diff > 0 {
        // Moving forward: work backwards to avoid overwriting
        for i in stride(from: remainder - 1, through: 0, by: -1) {
          if let byte: UInt8 = self.getInteger(at: endIndex + i) {
            self.setInteger(byte, at: endIndex + diff + i)
          }
        }
      } else {
        // Moving backward: work forwards
        for i in 0..<remainder {
          if let byte: UInt8 = self.getInteger(at: endIndex + i) {
            self.setInteger(byte, at: endIndex + diff + i)
          }
        }
      }
    }

    moveWriterIndex(to: writerIndex + diff)
  }
}

extension JSONDescription {
  @inlinable
  func removeBytes(atOffset offset: Int, oldSize: Int) {
    prepareForRewrite(atOffset: offset, oldSize: oldSize, newSize: 0)
  }

  @inlinable
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
      if diff > 0 {
        // Moving forward: work backwards to avoid overwriting
        for i in stride(from: remainder - 1, through: 0, by: -1) {
          storage[endIndex + diff + i] = storage[endIndex + i]
        }
      } else {
        // Moving backward: work forwards
        for i in 0..<remainder {
          storage[endIndex + diff + i] = storage[endIndex + i]
        }
      }
    }

    self.writtenBytes += diff
  }

  @usableFromInline
  func advance(at offset: Int, by value: Int32) {
    guard let old: Int32 = getInteger(at: offset) else {
      assertionFailure(
        "The JSON index is corrupt. There were not enough bytes to fetch a JSON value's location. Please file a bug report on Github"
      )
      return
    }

    assert(!old.addingReportingOverflow(value).overflow)

    setInteger(old &+ value, at: offset)
  }

  /// Inserts an object or array's JSONDescription and it's children into this one
  /// The supplied Int is the location where the value will be stored in JSON
  /// This will be used to update all locations in JSON accordingly
  @inlinable
  func addNestedDescription(_ description: JSONDescription, at jsonOffset: Int32) {
    let copy = description.slice(from: 0, length: description.writtenBytes)
    copy.advanceAllJSONOffsets(by: jsonOffset)
    self.writeBuffer(copy)
  }

  /// Moves this index description and all it's child descriptions their JSON offsets forward
  @usableFromInline
  func advanceAllJSONOffsets(by jsonOffset: Int32) {
    self.advance(at: Constants.jsonLocationOffset, by: jsonOffset)

    var indexOffset = Constants.firstArrayObjectChildOffset

    while indexOffset < writtenBytes {
      self.advance(at: indexOffset + Constants.jsonLocationOffset, by: jsonOffset)
      indexOffset = indexOffset &+ type(atOffset: indexOffset).indexLength
    }
  }
}

extension JSONDescriptionProtocol {
  @inlinable
  var topLevelType: JSONType {
    return type(atOffset: 0)
  }

  @inlinable
  func arrayObjectCount() -> Int {
    assert(self.topLevelType == .array || self.topLevelType == .object)

    guard
      let count: Int32 = getInteger(
        at: Constants.arrayObjectPairCountOffset
      )
    else {
      fatalError(
        "Invalid Array or Object description. Missing header data. Please file an issue on Github.")
    }

    return Int(count)
  }

  @inlinable
  func type(atOffset offset: Int) -> JSONType {
    assert(offset < writtenBytes)

    guard offset < storage.count, let type = JSONType(rawValue: storage[offset])
    else {
      fatalError(
        "The JSON index is corrupt. No JSON Type could be found at offset \(offset). Please file a bug report on Github."
      )
    }

    return type
  }

  @inlinable
  func indexLength(atOffset offset: Int) -> Int {
    // Force unwrap because this is all internal code, if this crashes JSON is broken
    switch type(atOffset: offset) {
    case .object, .array:
      guard
        let childrenLength: Int32 = getInteger(
          at: offset + Constants.arrayObjectTotalIndexLengthOffset
        )
      else {
        fatalError(
          "The JSON index is corrupt. No IndexLength could be found for all children of an object or array. Please file a bug report on Github."
        )
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

  @inlinable
  func skipIndex(atOffset offset: inout Int) {
    offset = offset &+ indexLength(atOffset: offset)
  }
}

extension JSONDescription {
  /// Removes a key-value pair from object descriptions only.
  /// Removes both the key and the value from this description
  @usableFromInline
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
        advance(
          at: updateLocationOffset + Constants.jsonLocationOffset, by: Int32(-removedJSONLength))
      }
      skipIndex(atOffset: &updateLocationOffset)

      // Value
      if successivePair {
        advance(
          at: updateLocationOffset + Constants.jsonLocationOffset, by: Int32(-removedJSONLength))
      }
      skipIndex(atOffset: &updateLocationOffset)
    }
  }

  /// Assumes `self` to be a description of a `JSONObject`
  @usableFromInline
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
  @usableFromInline
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

  @usableFromInline
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

      buffer.prepareForRewrite(
        atOffset: baseOffset, oldSize: Int(jsonBounds.length), newSize: _length)
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

      buffer.prepareForRewrite(
        atOffset: baseOffset, oldSize: Int(jsonBounds.length), newSize: _length)
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

      buffer.prepareForRewrite(
        atOffset: baseOffset, oldSize: Int(jsonBounds.length), newSize: _length)
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
        buffer.prepareForRewrite(
          atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 4)

        _ = buffer.setStaticString(boolTrue, at: Int(jsonBounds.offset))
        rewriteTrue(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
      } else {
        length = 5
        buffer.prepareForRewrite(
          atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 5)

        _ = buffer.setStaticString(boolFalse, at: Int(jsonBounds.offset))
        rewriteFalse(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
      }
    case let object as JSONObject:
      let _length = object.jsonBuffer.writerIndex
      length = Int32(_length)

      buffer.prepareForRewrite(
        atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: _length)
      buffer.setBuffer(object.jsonBuffer, at: Int(jsonBounds.offset))
      let newDescription = object.jsonDescription.slice(
        from: 0, length: object.jsonDescription.writtenBytes)
      newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
      rewriteObjectArray(locallyAt: indexOffset, from: newDescription)
    case let array as JSONArray:
      let _length = array.jsonBuffer.writerIndex
      length = Int32(_length)

      buffer.prepareForRewrite(
        atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: _length)
      buffer.setBuffer(array.jsonBuffer, at: Int(jsonBounds.offset))
      let newDescription = array.jsonDescription
      newDescription.advanceAllJSONOffsets(by: jsonBounds.offset)
      rewriteObjectArray(locallyAt: indexOffset, from: newDescription)
    default:
      length = 4
      buffer.prepareForRewrite(
        atOffset: Int(jsonBounds.offset), oldSize: Int(jsonBounds.length), newSize: 4)

      _ = buffer.setStaticString(nullBytes, at: Int(jsonBounds.offset))
      rewriteTrue(atIndexOffset: indexOffset, jsonOffset: jsonBounds.offset)
    }
  }

  @usableFromInline
  func addJSONSize(of size: Int32) {
    assert(topLevelType == .array || topLevelType == .object)

    advance(at: Constants.jsonLengthOffset, by: size)
  }

  @usableFromInline
  func rewriteNumber(
    _ number: JSONToken.Number,
    atIndexOffset offset: Int
  ) {
    let type: JSONType = number.isInteger ? .integer : .floatingNumber
    let oldSize = indexLength(atOffset: offset)

    prepareForRewrite(
      atOffset: offset, oldSize: oldSize, newSize: Constants.stringNumberIndexLength)

    setInteger(type.rawValue, at: offset)
    setInteger(Int32(number.start.byteOffset), at: offset + Constants.jsonLocationOffset)
    setInteger(Int32(number.byteLength), at: offset + Constants.jsonLengthOffset)
  }

  @usableFromInline
  func rewriteString(_ string: JSONToken.String, atIndexOffset offset: Int) {
    let type: JSONType = string.usesEscaping ? .stringWithEscaping : .string
    let oldSize = indexLength(atOffset: offset)

    prepareForRewrite(
      atOffset: offset, oldSize: oldSize, newSize: Constants.stringNumberIndexLength)

    setInteger(type.rawValue, at: offset)
    setInteger(Int32(string.start.byteOffset), at: offset + Constants.jsonLocationOffset)
    setInteger(Int32(string.byteLength), at: offset + Constants.jsonLengthOffset)
  }

  @usableFromInline
  func rewriteShortType(to type: JSONType, indexOffset: Int, jsonOffset: Int32) {
    let oldSize = indexLength(atOffset: indexOffset)

    prepareForRewrite(
      atOffset: indexOffset, oldSize: oldSize, newSize: Constants.boolNullIndexLength)

    setInteger(type.rawValue, at: indexOffset)
    setInteger(jsonOffset, at: indexOffset + Constants.jsonLocationOffset)
  }

  @usableFromInline
  func rewriteNull(atIndexOffset indexOffset: Int, jsonOffset: Int32) {
    rewriteShortType(to: .null, indexOffset: indexOffset, jsonOffset: jsonOffset)
  }

  @usableFromInline
  func rewriteTrue(atIndexOffset offset: Int, jsonOffset: Int32) {
    rewriteShortType(to: .boolTrue, indexOffset: offset, jsonOffset: jsonOffset)
  }

  @usableFromInline
  func rewriteFalse(atIndexOffset offset: Int, jsonOffset: Int32) {
    rewriteShortType(to: .boolFalse, indexOffset: offset, jsonOffset: jsonOffset)
  }

  @usableFromInline
  func rewriteObjectArray(locallyAt localOffset: Int, from newDescription: JSONDescription) {
    let oldLength = self.indexLength(atOffset: localOffset)
    let newLength = newDescription.indexLength(atOffset: 0)

    prepareForRewrite(atOffset: localOffset, oldSize: oldLength, newSize: newLength)

    setBuffer(to: newDescription, at: localOffset)
  }

  @inlinable
  func describeString(_ string: JSONToken.String) {
    let type: JSONType = string.usesEscaping ? .stringWithEscaping : .string

    // TODO: Host endianness is faster
    writeInteger(type.rawValue)
    writeInteger(Int32(string.start.byteOffset))
    writeInteger(Int32(string.byteLength))
  }

  @inlinable
  func describeNumber(_ number: JSONToken.Number) {
    // Make a destinction between floating points and integers
    let type = number.isInteger ? JSONType.integer.rawValue : JSONType.floatingNumber.rawValue

    // Set the new type identifier
    self.writeInteger(type)

    self.writeInteger(Int32(number.start.byteOffset))
    self.writeInteger(Int32(number.byteLength))
  }

  @inlinable
  func describeTrue(atJSONOffset jsonOffset: Int32) {
    writeInteger(JSONType.boolTrue.rawValue)
    writeInteger(jsonOffset)
  }

  @inlinable
  func describeFalse(atJSONOffset jsonOffset: Int32) {
    writeInteger(JSONType.boolFalse.rawValue)
    writeInteger(jsonOffset)
  }

  @inlinable
  func describeNull(atJSONOffset jsonOffset: Int32) {
    writeInteger(JSONType.null.rawValue)
    writeInteger(jsonOffset)
  }

  @usableFromInline
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

  @usableFromInline
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

  @usableFromInline
  func complete(
    _ unfinished: consuming ObjectStartContext,
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

  @usableFromInline
  func complete(_ unfinished: consuming ArrayStartContext, withResult result: JSONToken.ArrayEnd) {
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
  @usableFromInline
  func convertSnakeCasing() -> String {
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
  @inline(__always)
  func readOnlySubDescription(offset: Int) -> JSONDescriptionView {
    JSONDescriptionView(
      description: self,
      offset: offset
    )
  }
}

extension JSONDescriptionView {
  @inline(__always)
  func readOnlySubDescription(offset extraOffset: Int) -> JSONDescriptionView {
    JSONDescriptionView(
      description: description,
      offset: self.offset + extraOffset
    )
  }
}

extension JSONDescriptionProtocol {
  @usableFromInline
  func removeSnakeCasing(from characters: inout [UInt8]) {
    var size = characters.count
    var i = 0

    while i < size {
      if characters[i] == .underscore, i + 1 < size {
        let byte = characters[i + 1]

        if byte >= .a && byte <= .z {
          characters[i] = byte - 0x20
          characters.remove(at: i + 1)
          size -= 1
        }
      }

      i = i + 1
    }
  }

  private func snakeCasedEqual(
    codingKey: [UInt8],
    snakeCasedKey: [UInt8]
  ) -> Bool {
    var newKey = snakeCasedKey
    removeSnakeCasing(from: &newKey)
    guard newKey.count == codingKey.count else {
      return false
    }

    return newKey == codingKey
  }

  @inlinable
  func containsKey(
    _ key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>,
    unicode: Bool,
    fromOffset offset: Int = Constants.firstArrayObjectChildOffset
  ) -> Bool {
    return valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: span) != nil
  }

  @inlinable
  func containsKey(
    _ key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8],
    unicode: Bool,
    fromOffset offset: Int = Constants.firstArrayObjectChildOffset
  ) -> Bool {
    return valueOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: bytes) != nil
  }

  @usableFromInline
  func keyOffset(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>
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

    let keyBytes = Array(key.utf8)
    let keySize = keyBytes.count

    for _ in 0..<count {
      // Fetch the bounds for the key in JSON
      let bounds = dataBounds(atIndexOffset: offset)

      // Extract the key bytes from span for comparison
      var spanKeyBytes = [UInt8]()
      spanKeyBytes.reserveCapacity(Int(bounds.length))
      for i in 0..<Int(bounds.length) {
        spanKeyBytes.append(span[Int(bounds.offset) + i])
      }

      // Does the key match our search?
      if !convertingSnakeCasing, bounds.length == keySize, keyBytes == spanKeyBytes {
        return (index, offset)
      } else if convertingSnakeCasing, snakeCasedEqual(codingKey: keyBytes, snakeCasedKey: spanKeyBytes) {
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

  @usableFromInline
  func keyOffset(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8]
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

    let keyBytes = Array(key.utf8)
    let keySize = keyBytes.count

    for _ in 0..<count {
      // Fetch the bounds for the key in JSON
      let bounds = dataBounds(atIndexOffset: offset)

      // Extract the key bytes from array for comparison
      var arrayKeyBytes = [UInt8]()
      arrayKeyBytes.reserveCapacity(Int(bounds.length))
      for i in 0..<Int(bounds.length) {
        arrayKeyBytes.append(bytes[Int(bounds.offset) + i])
      }

      // Does the key match our search?
      if !convertingSnakeCasing, bounds.length == keySize, keyBytes == arrayKeyBytes {
        return (index, offset)
      } else if convertingSnakeCasing, snakeCasedEqual(codingKey: keyBytes, snakeCasedKey: arrayKeyBytes) {
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

  func valueOffset(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>
  ) -> (index: Int, offset: Int)? {
    guard
      let data = keyOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: span)
    else {
      return nil
    }

    let index = data.index
    var offset = data.offset
    // Skip key
    skipIndex(atOffset: &offset)

    return (index, offset)
  }

  func valueOffset(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8]
  ) -> (index: Int, offset: Int)? {
    guard
      let data = keyOffset(forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: bytes)
    else {
      return nil
    }

    let index = data.index
    var offset = data.offset
    // Skip key
    skipIndex(atOffset: &offset)

    return (index, offset)
  }

  @inlinable
  func offset(forIndex index: Int) -> Int {
    assert(self.topLevelType == .array)
    var offset = Constants.firstArrayObjectChildOffset
    for _ in 0..<index {
      skipIndex(atOffset: &offset)
    }

    return offset
  }

  @inlinable
  func type(
    ofKey key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>
  ) -> JSONType? {
    guard
      let (_, offset) = valueOffset(
        forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: span)
    else {
      return nil
    }

    return self.type(atOffset: offset)
  }

  @inlinable
  func type(
    ofKey key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8]
  ) -> JSONType? {
    guard
      let (_, offset) = valueOffset(
        forKey: key, convertingSnakeCasing: convertingSnakeCasing, in: bytes)
    else {
      return nil
    }

    return self.type(atOffset: offset)
  }

  @inlinable
  func keys(
    in span: Span<UInt8>,
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

      // Extract bytes from span
      var keyBytes = [UInt8]()
      keyBytes.reserveCapacity(Int(bounds.length))
      for i in 0..<Int(bounds.length) {
        keyBytes.append(span[Int(bounds.offset) + i])
      }

      let usesEscaping = self.type(atOffset: offset) == .stringWithEscaping

      if usesEscaping {
        // Process escaping
        if let key = processEscapedString(keyBytes, convertingSnakeCasing: convertingSnakeCasing) {
          keys.append(key)
        }
      } else {
        if convertingSnakeCasing {
          removeSnakeCasing(from: &keyBytes)
        }
        if let key = String(bytes: keyBytes, encoding: .utf8) {
          keys.append(key)
        }
      }

      skipIndex(atOffset: &offset)
      skipIndex(atOffset: &offset)
    }

    return keys
  }

  @inlinable
  func keys(
    in bytes: [UInt8],
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

      // Extract bytes from array
      var keyBytes = [UInt8]()
      keyBytes.reserveCapacity(Int(bounds.length))
      for i in 0..<Int(bounds.length) {
        keyBytes.append(bytes[Int(bounds.offset) + i])
      }

      let usesEscaping = self.type(atOffset: offset) == .stringWithEscaping

      if usesEscaping {
        // Process escaping
        if let key = processEscapedString(keyBytes, convertingSnakeCasing: convertingSnakeCasing) {
          keys.append(key)
        }
      } else {
        if convertingSnakeCasing {
          removeSnakeCasing(from: &keyBytes)
        }
        if let key = String(bytes: keyBytes, encoding: .utf8) {
          keys.append(key)
        }
      }

      skipIndex(atOffset: &offset)
      skipIndex(atOffset: &offset)
    }

    return keys
  }

  private func processEscapedString(_ bytes: [UInt8], convertingSnakeCasing: Bool) -> String? {
    var result = [UInt8]()
    result.reserveCapacity(bytes.count)
    var i = 0

    while i < bytes.count {
      let byte = bytes[i]

      if byte != .backslash || i + 1 >= bytes.count {
        result.append(byte)
        i += 1
        continue
      }

      i += 1

      switch bytes[i] {
      case .backslash, .solidus, .quote:
        result.append(bytes[i])
        i += 1
      case .t:
        result.append(.tab)
        i += 1
      case .r:
        result.append(.carriageReturn)
        i += 1
      case .n:
        result.append(.newLine)
        i += 1
      case .f:
        result.append(.formFeed)
        i += 1
      case .b:
        result.append(.backspace)
        i += 1
      case .u:
        // Unicode escape sequence
        guard i + 4 < bytes.count else {
          return nil
        }
        // For simplicity, just skip the unicode escape - this is a simplified implementation
        // A full implementation would decode the unicode and append UTF-8 bytes
        i += 5
      default:
        return nil
      }
    }

    var processedBytes = result
    if convertingSnakeCasing {
      removeSnakeCasing(from: &processedBytes)
    }

    return String(bytes: processedBytes, encoding: .utf8)
  }

  /// While similar to `jsonBounds`, it denotes the data of _interest_. Specifically for a `String`, these are the contents between
  /// quotes
  @inlinable
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
  @inlinable
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

  @inlinable
  func jsonLength(at indexOffset: Int) -> Int32 {
    guard
      let length: Int32 = getInteger(
        at: indexOffset + Constants.jsonLengthOffset
      )
    else {
      fatalError("Missing data to form a JSONLength. Please file an issue on Github")
    }

    return length
  }

  /// The offset where you can find this value in JSON
  @usableFromInline
  func jsonOffset(at indexOffset: Int) -> Int32 {
    guard
      let offset: Int32 = getInteger(
        at: indexOffset + Constants.jsonLocationOffset
      )
    else {
      fatalError(
        "Invalid Array or Object description. Missing header data. Please file an issue on Github.")
    }

    return offset
  }

  @inlinable
  func stringBounds(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>
  ) -> JSONToken.String? {
    guard
      let (_, offset) = valueOffset(
        forKey: key,
        convertingSnakeCasing: convertingSnakeCasing,
        in: span
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

  @inlinable
  func integerBounds(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>
  ) -> JSONToken.Number? {
    guard
      let (_, offset) = valueOffset(
        forKey: key,
        convertingSnakeCasing: convertingSnakeCasing,
        in: span
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

  @inlinable
  func floatingBounds(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in span: Span<UInt8>
  ) -> JSONToken.Number? {
    guard
      let (_, offset) = valueOffset(
        forKey: key,
        convertingSnakeCasing: convertingSnakeCasing,
        in: span
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

  @inlinable
  func stringBounds(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8]
  ) -> JSONToken.String? {
    guard
      let (_, offset) = valueOffset(
        forKey: key,
        convertingSnakeCasing: convertingSnakeCasing,
        in: bytes
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

  @inlinable
  func integerBounds(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8]
  ) -> JSONToken.Number? {
    guard
      let (_, offset) = valueOffset(
        forKey: key,
        convertingSnakeCasing: convertingSnakeCasing,
        in: bytes
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

  @inlinable
  func floatingBounds(
    forKey key: String,
    convertingSnakeCasing: Bool,
    in bytes: [UInt8]
  ) -> JSONToken.Number? {
    guard
      let (_, offset) = valueOffset(
        forKey: key,
        convertingSnakeCasing: convertingSnakeCasing,
        in: bytes
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

@usableFromInline
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

  @inline(__always)
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
