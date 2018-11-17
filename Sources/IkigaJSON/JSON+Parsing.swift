extension JSONParser {
    internal mutating func scanArray() throws -> JSONArrayDescription {
        assert(pointer.pointee == .squareLeft, "An object was scanned but the first byte was not `{`")
        
        var didParseFirstValue = false
        advance(1)
        var description = JSONArrayDescription()
        
        repeat {
            try skipWhitespace()
            
            if pointer.pointee == .squareRight {
                advance(1)
                return description
            } else if didParseFirstValue, nextByte() != .comma {
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedComma)
            } else {
                didParseFirstValue = true
            }
            
            try skipWhitespace() // needed because of the comma
            let value = try scanValue()
            
            description.values.append(value)
        } while hasMoreData
        
        throw JSONError.unexpectedToken(.curlyRight, reason: .expectedArrayClose)
    }
    
    internal mutating func scanObject() throws -> JSONObjectDescription {
        assert(pointer.pointee == .curlyLeft, "An object was scanned but the first byte was not `{`")
        
        var didParseFirstPair = false
        advance(1)
        var description = JSONObjectDescription()
        
        repeat {
            try skipWhitespace()
            
            if pointer.pointee == .curlyRight {
                advance(1)
                return description
            } else if didParseFirstPair, nextByte() != .comma {
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedComma)
            } else {
                didParseFirstPair = true
            }
            
            try skipWhitespace() // needed because of the comma
            let key = try scanStringLiteral()
            try skipWhitespace()
            
            guard nextByte() == .colon else {
                throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedColon)
            }
            
            try skipWhitespace()
            let value = try scanValue()
            
            description.pairs.append((key: key, value: value))
        } while hasMoreData
        
        throw JSONError.unexpectedToken(.curlyRight, reason: .expectedObjectClose)
    }
    
    internal mutating func scanValue() throws -> JSONValue {
        switch pointer.pointee {
        case .quote:
            return try JSONValue(storage: .string(self.scanStringLiteral()))
        case .curlyLeft:
            return try JSONValue(storage: .object(scanObject()))
        case .squareLeft:
            return try JSONValue(storage: .array(scanArray()))
        case .f: // false
            guard count > 5 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .a, pointer[2] == .l, pointer[3] == .s, pointer[4] == .e else {
                throw JSONError.invalidLiteral
            }
            
            advance(5)
            return .booleanFalse
        case .t: // true
            guard count > 4 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .r, pointer[2] == .u, pointer[3] == .e else {
                throw JSONError.invalidLiteral
            }
            
            advance(4)
            return .booleanTrue
        case .n: // null
            guard count > 4 else {
                throw JSONError.missingData
            }
            
            guard pointer[1] == .u, pointer[2] == .l, pointer[3] == .l else {
                throw JSONError.invalidLiteral
            }
            
            advance(4)
            return .null
        case .zero ... .nine, .minus:// Numerical
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
            let number = JSONNumber(bounds: bounds, floating: floating)
            return JSONValue(storage: .number(number))
        default:
            throw JSONError.unexpectedToken(pointer.pointee, reason: .expectedValue)
        }
    }
    
    fileprivate mutating func nextByte() -> UInt8 {
        let byte = pointer.pointee
        self.advance(1)
        return byte
    }
    
    internal mutating func scanStringLiteral() throws -> _JSONString {
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
                    return _JSONString(bounds: bounds, escaping: didEscape)
                }
            } else if byte == .backslash {
                didEscape = true
            }
        }
        
        throw JSONError.missingData
    }
}
