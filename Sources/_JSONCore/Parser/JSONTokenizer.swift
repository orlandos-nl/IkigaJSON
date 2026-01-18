/// This type is responsible for creating a JSONDescription for an inputted JSON buffer
public struct JSONTokenizer<Destination: JSONTokenizerDestination>: ~Copyable, ~Escapable {
  /// Creates a new JSONParser and initializes it
  @_lifetime(copy span)
  public init(
    span: Span<UInt8>,
    destination: Destination
  ) {
    self.bytes = span
    self.destination = destination
  }

  /// Creates a new JSONParser and initializes it
  ///
  /// The Bytes are owned by the JSONTokenizer for the duration of its usage
  /// As soon as the type is destroyed/consumed, you get ownership of the bytes
  /// Any deallocation of the bytes should happen after JSONTokenizer is destroyed/consumed
  @_lifetime(borrow bytes)
  @unsafe
  public init(
    bytes: borrowing UnsafeBufferPointer<UInt8>,
    destination: Destination
  ) {
    self.bytes = unsafe Span(_unsafeElements: bytes)
    self.destination = destination
  }

  /// The amount of parsed bytes from the `pointer`. Also the first index we have to parse next since programmers start at 0
  public private(set) var currentOffset = 0

  /// The pointer that will be parsed
  @usableFromInline
  internal let bytes: Span<UInt8>

  /// The amount of bytes supposedly in the pointer, this must be guaranteed internally
  @usableFromInline
  internal var count: Int {
    bytes.count - currentOffset
  }

  @usableFromInline
  package var line: Int { -1 }

  @usableFromInline
  package var column: Int { -1 }

  @inline(__always)
  @usableFromInline
  internal var currentByte: UInt8 {
    self[0]
  }

  public var destination: Destination

  /// Advances the amount of bytes processed and updates the related offset and count
  @usableFromInline
  @_lifetime(self: copy self)
  internal mutating func advance(_ offset: Int) {
    currentOffset += offset
  }
}

extension JSONTokenizer {
  @inline(__always)
  @usableFromInline
  internal subscript(offset: Int) -> UInt8 {
    bytes[currentOffset + offset]
  }

  @usableFromInline
  internal var hasMoreData: Bool {
    return currentOffset < bytes.count
  }

  /// Throws an error if the count is 0
  private func assertMoreData() throws(JSONParserError) {
    guard hasMoreData else {
      throw JSONParserError.missingData(line: line, column: column)
    }
  }

  /// Skips all whitespace (space, tab, carriage-return and newline)
  /// Uses SWAR to scan 8 bytes at a time for better performance
  @_optimize(speed)
  @usableFromInline
  @_lifetime(self: copy self)
  mutating func _skipWhitespace() {
    let searchEnd = bytes.count
    let searchStart = currentOffset

    let offset: Int = unsafe bytes.withUnsafeBufferPointer { buffer in
      var i = searchStart

      // Align to 8-byte boundary first
      let alignedStart = (i + 7) & ~7
      while i < min(alignedStart, searchEnd) {
        let byte = unsafe buffer[i]
        if byte != .space && byte != .tab && byte != .carriageReturn && byte != .newLine {
          return i - searchStart
        }
        i &+= 1
      }

      // Process 8 bytes at a time with better memory access pattern
      while i &+ 8 <= searchEnd {
        var foundNonWhitespace = false
        var nonWhitespaceOffset = 0

        for j in 0..<8 {
          let byte = unsafe buffer[i &+ j]
          if byte != .space && byte != .tab && byte != .carriageReturn && byte != .newLine {
            foundNonWhitespace = true
            nonWhitespaceOffset = j
            break
          }
        }

        if foundNonWhitespace {
          return (i &+ nonWhitespaceOffset) - searchStart
        }
        i &+= 8
      }

      // Process remaining bytes
      while i < searchEnd {
        let byte = unsafe buffer[i]
        if byte != .space && byte != .tab && byte != .carriageReturn && byte != .newLine {
          return i - searchStart
        }
        i &+= 1
      }

      return searchEnd - searchStart
    }

    advance(offset)
  }
}

extension JSONTokenizer {
  /// Skips whitespace and throws an error if there is no data left. Usually this is the best way to parse since you'll be wanting to parse something after the whitespace.
  @_optimize(speed)
  @inline(__always)
  @usableFromInline
  @_lifetime(self: copy self)
  internal mutating func skipWhitespace() throws(JSONParserError) {
    _skipWhitespace()
    try assertMoreData()
  }
}
