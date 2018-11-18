extension JSONParser {
    internal mutating func scanArray() throws {
        assert(pointer.pointee == .squareLeft, "An array was scanned but the first byte was not `[`")
        
        var didParseFirstValue = false
        
        let array = description.describeArray(atOffset: totalOffset)
        let offset = totalOffset
        advance(1)
        var count: UInt32 = 0
        
        repeat {
            try skipWhitespace()
            
            if pointer.pointee == .squareRight {
                advance(1)
                let result = _ArrayObjectDescription(count: count, byteCount: UInt32(totalOffset &- offset))
                return description.complete(array, withResult: result)
            } else if didParseFirstValue, nextByte() != .comma {
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedComma)
            } else {
                didParseFirstValue = true
            }
            
            try skipWhitespace() // needed because of the comma
            try scanValue()
            
            count = count &+ 1
        } while hasMoreData
        
        throw JSONError.missingData
    }
    
    internal mutating func scanObject() throws {
        assert(pointer.pointee == .curlyLeft, "An object was scanned but the first byte was not `{`")
        
        var didParseFirstValue = false
        
        let object = description.describeObject(atOffset: totalOffset)
        let offset = totalOffset
        advance(1)
        var count: UInt32 = 0
        
        repeat {
            try skipWhitespace()
            
            if pointer.pointee == .curlyRight {
                advance(1)
                let result = _ArrayObjectDescription(count: count, byteCount: UInt32(totalOffset &- offset))
                return description.complete(object, withResult: result)
            } else if didParseFirstValue, nextByte() != .comma {
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedComma)
            } else {
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
            
            count = count &+ 1
        } while hasMoreData
        
        throw JSONError.missingData
    }
    
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
            description.describeFalse()
        case .t: // true
            guard count > 4 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .r, pointer[2] == .u, pointer[3] == .e else {
                throw JSONError.invalidLiteral
            }
            
            advance(4)
            description.describeTrue()
        case .n: // null
            guard count > 4 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .u, pointer[2] == .l, pointer[3] == .l else {
                throw JSONError.invalidLiteral
            }
            
            advance(4)
            description.describeNull()
        case .zero ... .nine, .minus:// Numerical
            try scanNumber()
        default:
            throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedValue)
        }
    }
    
    fileprivate mutating func nextByte() -> UInt8 {
        let byte = pointer.pointee
        self.advance(1)
        return byte
    }
    
    fileprivate mutating func scanNumber() throws {
        var length = 1
        var floating = false
        
        loop: while length < count {
            let byte = pointer[length]
            
            if byte < .zero || byte > .nine {
                if byte != .fullStop, byte != .e, byte != .E, byte != .plus, byte != .minus {
                    break loop
                }
                
                // not a first minus sign
                floating = byte != .minus || length > 1
            }
            
            length = length &+ 1
        }
        
        // Only a minus was parsed
        if floating && length == 1 {
            throw JSONError.unexpectedToken(.minus, reason: .expectedValue)
        }
        
        let start = totalOffset
        advance(length)
        let bounds = Bounds(offset: start, length: length)
        
        description.describeNumber(bounds, floatingPoint: floating)
    }
    
    fileprivate mutating func scanStringLiteral() throws {
        if pointer.pointee != .quote {
            throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedObjectKey)
        }
        
        var offset = 1
        var didEscape = false
        
        defer {
            advance(offset)
        }
        
        while offset < count {
            defer { offset = offset &+ 1 }
            
            let byte = pointer[offset]
            
            // Unescaped quote
            if byte == .quote {
                var escaped = false
                var backwardsOffset = offset &- 1
                
                escapeLoop: while backwardsOffset > 1 {
                    defer { backwardsOffset = backwardsOffset &- 1 }
                    
                    if pointer[backwardsOffset] == .backslash {
                        escaped = !escaped
                    } else {
                        break escapeLoop
                    }
                }
                
                if !escaped {
                    // Minus the first quote, seocnd quote hasn't been added to offset yet as `defer` didn't trigger
                    let bounds = Bounds(offset: totalOffset &+ 1, length: offset &- 1)
                    description.describeString(bounds, escaped: didEscape)
                    return
                }
            } else if byte == .backslash {
                didEscape = true
            }
        }
        
        throw JSONError.missingData
    }
}
