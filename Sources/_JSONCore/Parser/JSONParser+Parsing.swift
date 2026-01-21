/// All parsing logic of the JSON parser

extension JSONTokenizer {
  /// Scans a JSON object and parses values within it
  @_optimize(speed)
  @usableFromInline
  @_lifetime(self: copy self)
  internal mutating func scanArray() throws(JSONParserError) {
    assert(currentByte == .squareLeft, "An array was scanned but the first byte was not `[`")

    // Used to keep track if a comma needs to be parsed before the next value
    var didParseFirstValue = false

    // Start describing the array, this is not complete yet, merely a placeholder
    let arrayStart = JSONSourcePosition(byteIndex: currentOffset)
    let context = destination.arrayStartFound(.init(start: arrayStart))

    // Skip past the array open `[`
    advance(1)

    var memberCount = 0

    repeat {
      // Whitespace before the comma
      try skipWhitespace()

      // Check for end of array or comma
      if currentByte == .squareRight {
        // End of array
        advance(1)

        // Complete the array description
        let arrayEnd = JSONToken.ArrayEnd(
          start: arrayStart,
          end: JSONSourcePosition(byteIndex: currentOffset),
          memberCount: memberCount
        )
        return destination.arrayEndFound(arrayEnd, context: context)
      } else if didParseFirstValue, nextByte() != .comma {
        // No comma here means this is invalid JSON
        // Commas are required between each element
        throw JSONParserError.unexpectedToken(
          line: line, column: column, token: currentByte, reason: .expectedComma)
      } else {
        // Parsed a comma, always override didParseFirstValue
        // Overwriting this in the stack is not heavier than an if statement
        didParseFirstValue = true
      }

      // Whitespace after the comma
      try skipWhitespace()

      try scanValue()
      memberCount &+= 1
    } while hasMoreData

    throw JSONParserError.missingData(line: line, column: column)
  }

  /// Scans a JSON object and parses keys and values within it
  @_optimize(speed)
  @usableFromInline
  @_lifetime(self: copy self)
  internal mutating func scanObject() throws(JSONParserError) {
    assert(currentByte == .curlyLeft, "An object was scanned but the first byte was not `{`")

    // Used to keep track if a comma needs to be parsed before the next value
    var didParseFirstValue = false

    // Start describing the object, this is not complete yet, merely a placeholder
    let start = JSONSourcePosition(byteIndex: currentOffset)
    let context = destination.objectStartFound(JSONToken.ObjectStart(start: start))

    // Skip past the object open `{`
    advance(1)

    var memberCount = 0

    repeat {
      try skipWhitespace()

      if currentByte == .curlyRight {
        // End of object
        advance(1)

        // Complete the object description
        let end = JSONSourcePosition(byteIndex: currentOffset)
        let objectEnd = JSONToken.ObjectEnd(
          start: start,
          end: end,
          memberCount: memberCount
        )
        return destination.objectEndFound(objectEnd, context: context)
      } else if didParseFirstValue, nextByte() != .comma {
        // No comma here means this is invalid JSON because a value was already parsed
        // Commas are required between each element
        throw JSONParserError.unexpectedToken(
          line: line, column: column, token: currentByte, reason: .expectedComma)
      } else {
        // Parsed a comma, always override didParseFirstValue
        // Overwriting this in the stack is not heavier than an if statement
        didParseFirstValue = true
      }

      try skipWhitespace()  // needed because of the comma
      try scanStringLiteral()
      try skipWhitespace()

      guard nextByte() == .colon else {
        throw JSONParserError.unexpectedToken(
          line: line, column: column, token: currentByte, reason: .expectedColon)
      }

      try skipWhitespace()
      try scanValue()

      memberCount &+= 1
    } while hasMoreData

    throw JSONParserError.missingData(line: line, column: column)
  }

  /// Scans _any_ value and calls into the destination
  @_optimize(speed)
  @inlinable
  @_lifetime(self: copy self)
  public mutating func scanValue() throws(JSONParserError) {
    guard hasMoreData else {
      throw JSONParserError.missingData(line: line, column: column)
    }

    try skipWhitespace()

    switch currentByte {
    case .quote:
      try scanStringLiteral()
    case .curlyLeft:
      try scanObject()
    case .squareLeft:
      try scanArray()
    case .f:  // false
      guard count >= 5 else {
        throw JSONParserError.missingData(line: line, column: column)
      }

      guard self[1] == .a, self[2] == .l, self[3] == .s, self[4] == .e else {
        throw JSONParserError.invalidLiteral(line: line, column: column)
      }

      advance(5)
      destination.booleanFalseFound(.init(start: .init(byteIndex: currentOffset)))
    case .t:  // true
      guard count >= 4 else {
        throw JSONParserError.missingData(line: line, column: column)
      }

      guard self[1] == .r, self[2] == .u, self[3] == .e else {
        throw JSONParserError.invalidLiteral(line: line, column: column)
      }

      advance(4)
      destination.booleanTrueFound(.init(start: .init(byteIndex: currentOffset)))
    case .n:  // null
      guard count >= 4 else {
        throw JSONParserError.missingData(line: line, column: column)
      }

      guard self[1] == .u, self[2] == .l, self[3] == .l else {
        throw JSONParserError.invalidLiteral(line: line, column: column)
      }

      advance(4)
      destination.nullFound(.init(start: .init(byteIndex: currentOffset)))
    case .zero ... .nine, .minus:  // Numerical
      try scanNumber()
    default:
      throw JSONParserError.unexpectedToken(
        line: line, column: column, token: currentByte, reason: .expectedValue)
    }
  }

  /// Gets the next byte and advances by 1, doesn't boundary check
  @_optimize(speed)
  @usableFromInline
  @_lifetime(self: copy self)
  mutating func nextByte() -> UInt8 {
    let byte = currentByte
    self.advance(1)
    return byte
  }

  /// Scans a number literal, be it double or integer, and calls into the destination
  ///
  /// Integers are simpler to parse, so a different parsing strategy may be sed for performance
  @_optimize(speed)
  @usableFromInline
  @_lifetime(self: copy self)
  mutating func scanNumber() throws(JSONParserError) {
    var byteLength = 1
    var floating = false

    /// We don't parse/copy the integer out yet
    loop: while byteLength < count {
      let byte = self[byteLength]

      if byte < .zero || byte > .nine {
        if byte != .fullStop, byte != .e, byte != .E, byte != .plus, byte != .minus {
          break loop
        }

        // not a first minus sign
        floating = byte != .minus || byteLength > 1
      }

      byteLength = byteLength &+ 1
    }

    // Only a minus was parsed
    if floating && byteLength == 1 {
      throw JSONParserError.unexpectedToken(
        line: line, column: column, token: .minus, reason: .expectedValue)
    }

    let start = JSONSourcePosition(byteIndex: currentOffset)
    advance(byteLength)
    let end = JSONSourcePosition(byteIndex: currentOffset)
    destination.numberFound(JSONToken.Number(start: start, end: end, isInteger: !floating))
  }

  /// Scans a String literal at the current offset and calls into the destination. Used for values as well as object keys
  ///
  /// We don't copy the String out here, this saves performance in many areas
  @_optimize(speed)
  @usableFromInline
  @_lifetime(self: copy self)
  mutating func scanStringLiteral() throws(JSONParserError) {
    if currentByte != .quote {
      throw JSONParserError.unexpectedToken(
        line: line, column: column, token: currentByte, reason: .expectedObjectKey)
    }

    // Fast path: scan 8 bytes at a time looking for " or \
    let searchStart = currentOffset &+ 1
    let searchEnd = bytes.count

    // Use closure only to find the string end index, return results outside
    // to avoid overlapping access errors with self mutation
    let result: (foundIndex: Int, didEscape: Bool, found: Bool) = unsafe bytes.withUnsafeBufferPointer { buffer in
      // Broadcast targets to all bytes in 64-bit words
      let quoteTarget: UInt64 = 0x2222222222222222  // " = 0x22
      let backslashTarget: UInt64 = 0x5C5C5C5C5C5C5C5C  // \ = 0x5C

      var i = searchStart
      var didEscape = false

      // Align to 8-byte boundary first
      let alignedStart = (i + 7) & ~7
      while i < min(alignedStart, searchEnd) {
        let byte = buffer[i]
        if byte == .quote {
          // Found unescaped quote - string ends here
          return (i - currentOffset, didEscape, true)
        } else if byte == .backslash {
          didEscape = true
        }
        i &+= 1
      }

      // Process 8 bytes at a time
      while i &+ 8 <= searchEnd {
        let word = unsafe buffer.baseAddress!.advanced(by: i).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }

        // Check for quote
        let xoredQuote = word ^ quoteTarget
        let hasQuote = (xoredQuote &- 0x0101010101010101) & ~xoredQuote & 0x8080808080808080

        // Check for backslash
        let xoredBackslash = word ^ backslashTarget
        let hasBackslash = (xoredBackslash &- 0x0101010101010101) & ~xoredBackslash & 0x8080808080808080

        let combined = hasQuote | hasBackslash

        if combined != 0 {
          // Found something - process bytes one by one to handle escaping correctly
          for j in 0..<8 {
            let byte = buffer[i &+ j]
            if byte == .quote {
              // Check if escaped
              var escaped = false
              if didEscape {
                var backwardsOffset = (i &+ j) &- 1
                while backwardsOffset >= searchStart &- 1 {
                  if buffer[backwardsOffset] == .backslash {
                    escaped = !escaped
                    backwardsOffset &-= 1
                  } else {
                    break
                  }
                }
              }
              if !escaped {
                return ((i &+ j) - currentOffset, didEscape, true)
              }
            } else if byte == .backslash {
              didEscape = true
            }
          }
        }
        i &+= 8
      }

      // Process remaining bytes
      while i < searchEnd {
        let byte = buffer[i]
        if byte == .quote {
          // Check if escaped
          var escaped = false
          if didEscape {
            var backwardsOffset = i &- 1
            while backwardsOffset >= searchStart &- 1 {
              if buffer[backwardsOffset] == .backslash {
                escaped = !escaped
                backwardsOffset &-= 1
              } else {
                break
              }
            }
          }
          if !escaped {
            return (i - currentOffset, didEscape, true)
          }
        } else if byte == .backslash {
          didEscape = true
        }
        i &+= 1
      }

      // String not terminated
      return (searchEnd - currentOffset, didEscape, false)
    }

    guard result.found else {
      throw JSONParserError.missingData(line: line, column: column)
    }

    let currentIndex = result.foundIndex
    let start = JSONSourcePosition(byteIndex: currentOffset)
    advance(currentIndex &+ 1)
    destination.stringFound(
      .init(start: start, byteLength: currentIndex &+ 1, usesEscaping: result.didEscape))
  }
}
