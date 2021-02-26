/// All parsing logic of the JSON parser

extension JSONParser {
    /// Scans a JSON object and parses values within it
    internal mutating func scanArray() throws {
        assert(pointer.pointee == .squareLeft, "An array was scanned but the first byte was not `[`")
        
        // Used to keep track if a comma needs to be parsed before the next value
        var didParseFirstValue = false
        
        // Start describing the array, this is not complete yet, merely a placeholder
        let array = description.describeArray(atJSONOffset: Int32(currentOffset))
        let startOffset = currentOffset
        
        // Skip past the array open `[`
        advance(1)
        
        var arrayCount: Int32 = 0
        
        repeat {
            // Whitespace before the comma
            try skipWhitespace()
            
            // Check for end of array or comma
            if pointer.pointee == .squareRight {
                // End of array
                advance(1)
                
                // Complete the array description
                let result = _ArrayObjectDescription(valueCount: arrayCount, jsonByteCount: Int32(currentOffset &- startOffset))
                return description.complete(array, withResult: result)
            } else if didParseFirstValue, nextByte() != .comma {
                // No comma here means this is invalid JSON
                // Commas are required between each element
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedComma)
            } else {
                // Parsed a comma, always override didParseFirstValue
                // Overwriting this in the stack is not heavier than an if statement
                didParseFirstValue = true
            }
            
            // Whitespace after the comma
            try skipWhitespace()
            
            try scanValue()
            arrayCount = arrayCount &+ 1
        } while hasMoreData
        
        throw JSONError.missingData
    }
    
    /// Scans a JSON object and parses keys and values within it
    internal mutating func scanObject() throws {
        assert(pointer.pointee == .curlyLeft, "An object was scanned but the first byte was not `{`")
        
        // Used to keep track if a comma needs to be parsed before the next value
        var didParseFirstValue = false
        
        // Start describing the object, this is not complete yet, merely a placeholder
        let object = description.describeObject(atJSONOffset: Int32(currentOffset))
        let startOffset = currentOffset
        
        // Skip past the object open `{`
        advance(1)
        
        var pairCount: Int32 = 0
        
        repeat {
            try skipWhitespace()
            
            if pointer.pointee == .curlyRight {
                // End of object
                advance(1)
                
                // Complete the object description
                let result = _ArrayObjectDescription(valueCount: pairCount, jsonByteCount: Int32(currentOffset &- startOffset))
                return description.complete(object, withResult: result)
            } else if didParseFirstValue, nextByte() != .comma {
                // No comma here means this is invalid JSON because a value was already parsed
                // Commas are required between each element
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedComma)
            } else {
                // Parsed a comma, always override didParseFirstValue
                // Overwriting this in the stack is not heavier than an if statement
                didParseFirstValue = true
            }
            
            try skipWhitespace() // needed because of the comma
            try scanStringLiteral()
            try skipWhitespace()
            
            guard nextByte() == .colon else {
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedColon)
            }
            
            try skipWhitespace()
            try scanValue()
            
            pairCount = pairCount &+ 1
        } while hasMoreData
        
        throw JSONError.missingData
    }
    
    /// Scans _any_ value and writes it to the description
    internal mutating func scanValue() throws {
        guard hasMoreData else {
            throw JSONError.missingData
        }
        
        switch pointer.pointee {
        case .quote:
            try scanStringLiteral()
        case .curlyLeft:
            try scanObject()
        case .squareLeft:
            try scanArray()
        case .f: // false
            guard count > 5 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .a, pointer[2] == .l, pointer[3] == .s, pointer[4] == .e else {
                throw JSONError.invalidLiteral
            }
            
            advance(5)
            description.describeFalse(atJSONOffset: Int32(currentOffset))
        case .t: // true
            guard count > 4 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .r, pointer[2] == .u, pointer[3] == .e else {
                throw JSONError.invalidLiteral
            }
            
            advance(4)
            description.describeTrue(atJSONOffset: Int32(currentOffset))
        case .n: // null
            guard count > 4 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .u, pointer[2] == .l, pointer[3] == .l else {
                throw JSONError.invalidLiteral
            }
            
            advance(4)
            description.describeNull(atJSONOffset: Int32(currentOffset))
        case .zero ... .nine, .minus:// Numerical
            try scanNumber()
        default:
            throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedValue)
        }
    }
    
    /// Gets the next byte and advances by 1, doesn't boundary check
    fileprivate mutating func nextByte() -> UInt8 {
        let byte = pointer.pointee
        self.advance(1)
        return byte
    }
    
    /// Scans a number literal, be it double or integer, and writes it to the description
    ///
    /// Integers are simpler to parse, so a difference is made in the binary description
    ///
    /// We don't copy the number out here, this saves performance in many areas
    fileprivate mutating func scanNumber() throws {
        var byteLength = 1
        var floating = false
        
        /// We don't parse/copy the integer out yet
        loop: while byteLength < count {
            let byte = pointer[byteLength]
            
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
            throw JSONError.unexpectedToken(.minus, reason: .expectedValue)
        }
        
        let start = currentOffset
        advance(byteLength)
        let bounds = Bounds(offset: Int32(start), length: Int32(byteLength))
        description.describeNumber(at: bounds, floatingPoint: floating)
    }
    
    /// Scans a String literal at the current offset and writes it to the description. Used for values as well as object keys
    ///
    /// We don't copy the String out here, this saves performance in many areas
    fileprivate mutating func scanStringLiteral() throws {
        if pointer.pointee != .quote {
            throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedObjectKey)
        }
        
        // The offset is calculated and written later, updating the offset too much results in performance loss
        var currentIndex: Int = 1
        
        // If any excaping character is detected, it will be noted
        // This reduces the performance cost on parsing most strings, removing a second unneccessary check
        var didEscape = false
        
        defer {
            advance(currentIndex)
        }
        
        while currentIndex < count {
            defer { currentIndex = currentIndex &+ 1 }
            
            let byte = pointer[currentIndex]
            
            // If it's a quote, check if it's escaped
            if byte == .quote {
                var escaped = false
                var backwardsOffset = currentIndex &- 1
                
                // Every escaped character can have another escaped character
                escapeLoop: while backwardsOffset >= 1 {
                    defer { backwardsOffset = backwardsOffset &- 1 }
                    
                    if pointer[backwardsOffset] == .backslash {
                        // TODO: Is this the fastest way?
                        // An integer incrementing that `& 1 == 1` is also escaped, likely more solutions
                        escaped = !escaped
                    } else {
                        break escapeLoop
                    }
                }
                
                if !escaped {
                    // Defer didn't trigger yet
                    let bounds = Bounds(offset: Int32(currentOffset), length: Int32(currentIndex &+ 1))
                    description.describeString(at: bounds, escaped: didEscape)
                    return
                }
            } else if byte == .backslash {
                // Strings are parsed front-to-back, so this backslash is meaningless except it helps us detect if it's escaped
                didEscape = true
            }
        }
        
        throw JSONError.missingData
    }
}
