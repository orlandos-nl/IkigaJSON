/// All parsing logic of the JSON parser

extension JSONTokenizer {
    /// Scans a JSON object and parses values within it
    internal mutating func scanArray() throws(JSONParserError) {
        assert(pointer.pointee == .squareLeft, "An array was scanned but the first byte was not `[`")
        
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
            if pointer.pointee == .squareRight {
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
                throw JSONParserError.unexpectedToken(line: line, column: column, token: pointer.pointee, reason: .expectedComma)
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
    internal mutating func scanObject() throws(JSONParserError) {
        assert(pointer.pointee == .curlyLeft, "An object was scanned but the first byte was not `{`")
        
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
            
            if pointer.pointee == .curlyRight {
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
                throw JSONParserError.unexpectedToken(line: line, column: column, token: pointer.pointee, reason: .expectedComma)
            } else {
                // Parsed a comma, always override didParseFirstValue
                // Overwriting this in the stack is not heavier than an if statement
                didParseFirstValue = true
            }
            
            try skipWhitespace() // needed because of the comma
            try scanStringLiteral()
            try skipWhitespace()
            
            guard nextByte() == .colon else {
                throw JSONParserError.unexpectedToken(line: line, column: column, token: pointer.pointee, reason: .expectedColon)
            }
            
            try skipWhitespace()
            try scanValue()
            
            memberCount &+= 1
        } while hasMoreData
        
        throw JSONParserError.missingData(line: line, column: column)
    }
    
    /// Scans _any_ value and calls into the destination
    public mutating func scanValue() throws(JSONParserError) {
        guard hasMoreData else {
            throw JSONParserError.missingData(line: line, column: column)
        }
        
        try skipWhitespace()
        
        switch pointer.pointee {
        case .quote:
            try scanStringLiteral()
        case .curlyLeft:
            try scanObject()
        case .squareLeft:
            try scanArray()
        case .f: // false
            guard count > 5 else {
                throw JSONParserError.missingData(line: line, column: column)
            }
            
            guard pointer[1] == .a, pointer[2] == .l, pointer[3] == .s, pointer[4] == .e else {
                throw JSONParserError.invalidLiteral(line: line, column: column)
            }
            
            advance(5)
            destination.booleanFalseFound(.init(start: .init(byteIndex: currentOffset)))
        case .t: // true
            guard count > 4 else {
                throw JSONParserError.missingData(line: line, column: column)
            }
            
            guard pointer[1] == .r, pointer[2] == .u, pointer[3] == .e else {
                throw JSONParserError.invalidLiteral(line: line, column: column)
            }
            
            advance(4)
            destination.booleanTrueFound(.init(start: .init(byteIndex: currentOffset)))
        case .n: // null
            guard count > 4 else {
                throw JSONParserError.missingData(line: line, column: column)
            }
            
            guard pointer[1] == .u, pointer[2] == .l, pointer[3] == .l else {
                throw JSONParserError.invalidLiteral(line: line, column: column)
            }
            
            advance(4)
            destination.nullFound(.init(start: .init(byteIndex: currentOffset)))
        case .zero ... .nine, .minus:// Numerical
            try scanNumber()
        default:
            throw JSONParserError.unexpectedToken(line: line, column: column, token: pointer.pointee, reason: .expectedValue)
        }
    }
    
    /// Gets the next byte and advances by 1, doesn't boundary check
    fileprivate mutating func nextByte() -> UInt8 {
        let byte = pointer.pointee
        self.advance(1)
        return byte
    }
    
    /// Scans a number literal, be it double or integer, and calls into the destination
    ///
    /// Integers are simpler to parse, so a different parsing strategy may be sed for performance
    fileprivate mutating func scanNumber() throws(JSONParserError) {
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
            throw JSONParserError.unexpectedToken(line: line, column: column, token: .minus, reason: .expectedValue)
        }
        
        let start = JSONSourcePosition(byteIndex: currentOffset)
        advance(byteLength)
        let end = JSONSourcePosition(byteIndex: currentOffset)
        destination.numberFound(JSONToken.Number(start: start, end: end, isInteger: !floating))
    }
    
    /// Scans a String literal at the current offset and calls into the destination. Used for values as well as object keys
    ///
    /// We don't copy the String out here, this saves performance in many areas
    fileprivate mutating func scanStringLiteral() throws(JSONParserError) {
        if pointer.pointee != .quote {
            throw JSONParserError.unexpectedToken(line: line, column: column, token: pointer.pointee, reason: .expectedObjectKey)
        }
        
        // The offset is calculated and written later, updating the offset too much results in performance loss
        var currentIndex: Int = 1
        
        // If any excaping character is detected, it will be noted
        // This reduces the performance cost on parsing most strings, removing a second unneccessary check
        var didEscape = false
        defer { advance(currentIndex) }

        while currentIndex < count {
            defer { currentIndex = currentIndex &+ 1 }
            
            let byte = pointer[currentIndex]
            
            // If it's a quote, check if it's escaped
            if byte == .quote {
                var escaped = false
                
                if didEscape {
                    // No need to run this logic if no escape symbol was present
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
                }
                
                if !escaped {
                    // Defer didn't trigger yet
                    let start = JSONSourcePosition(byteIndex: currentOffset)
                    destination.stringFound(.init(
                        start: start,
                        byteLength: currentIndex &+ 1,
                        usesEscaping: didEscape
                    ))
                    return
                }
            } else if byte == .backslash {
                // Strings are parsed front-to-back, so this backslash is meaningless except it helps us detect if it's escaped
                didEscape = true
            }
        }
        
        throw JSONParserError.missingData(line: line, column: column)
    }
}
