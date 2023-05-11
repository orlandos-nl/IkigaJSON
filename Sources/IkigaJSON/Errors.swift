public enum JSONParserError: Error, CustomStringConvertible {
    public enum Reason: CustomStringConvertible {
        case expectedObjectKey
        case expectedObjectClose
        case expectedTopLevelObject
        case expectedValue
        case expectedColon
        case expectedComma
        case expectedArrayClose
        
        public var description: String {
            switch self {
            case .expectedObjectKey:
                return "Expected Object Key"
            case .expectedObjectClose:
                return "Expected End of Object: `}`"
            case .expectedTopLevelObject:
                return "Expected Top Level Object"
            case .expectedValue:
                return "Expected a Value Literal"
            case .expectedColon:
                return "Expected a colon"
            case .expectedComma:
                return "Expected a comma"
            case .expectedArrayClose:
                return "Expected End of Array: `]`"
            }
        }
    }
    
    public var description: String {
        switch self {
        case .expectedArray:
            return "Expected JSON Array"
        case .expectedObject:
            return "Expected JSON Object"
        case .internalStateError, .unknownJSONStrategy, .missingKeyedContainer, .missingUnkeyedContainer, .decodingError, .endOfArray, .missingSuperDecoder:
            return "JSON Decoder Error"
        case .invalidDate:
            return "Incorrect Date"
        case .invalidData:
            return "Invalid String"
        case .endOfObject:
            return "Unexpected end of object"
        case .invalidTopLevelObject:
            return "Invalid Top Level Object"
        case .missingData:
            return "Unexpected End of File"
        case .invalidLiteral:
            return "Invalid Literal"
        case .invalidObjectIdLiteral:
            return "Invalid ObjectId"
        case .missingToken(_, _, let uInt8, let reason):
            return "Missing token '\(Character(.init(uInt8)))': \(reason)"
        case .unexpectedToken(_, _, let uInt8, let reason):
            return "Unexpected token '\(Character(.init(uInt8)))': \(reason)"
        case .unexpectedEscapingToken:
            return "Unexpected escaping token"
        }
    }
    
    public var column: Int? {
        switch self {
        case .expectedObject, .expectedArray, .unexpectedEscapingToken:
            return nil
        case .internalStateError(_, column: let column):
            return column
        case .invalidDate, .invalidData:
            return nil
        case .endOfObject(_, column: let column):
            return column
        case .unknownJSONStrategy, .missingKeyedContainer, .missingUnkeyedContainer, .decodingError, .missingSuperDecoder, .endOfArray:
            return nil
        case .invalidTopLevelObject(_, column: let column):
            return column
        case .missingData(_, column: let column):
            return column
        case .invalidLiteral(_, column: let column):
            return column
        case .invalidObjectIdLiteral(_, column: let column):
            return column
        case .missingToken(_, column: let column, token: _, reason: _):
            return column
        case .unexpectedToken(_, column: let column, token: _, reason: _):
            return column
        }
    }
    
    public var line: Int? {
        switch self {
        case .expectedObject, .expectedArray, .unexpectedEscapingToken:
            return nil
        case .internalStateError(line: let line, _):
            return line
        case .invalidDate, .invalidData:
            return nil
        case .endOfObject(line: let line, _):
            return line
        case .unknownJSONStrategy, .missingKeyedContainer, .missingUnkeyedContainer, .decodingError, .missingSuperDecoder, .endOfArray:
            return nil
        case .invalidTopLevelObject(line: let line, _):
            return line
        case .missingData(line: let line, _):
            return line
        case .invalidLiteral(line: let line, _):
            return line
        case .invalidObjectIdLiteral(let line, _):
            return line
        case .missingToken(line: let line, _, token: _, reason: _):
            return line
        case .unexpectedToken(line: let line, _, token: _, reason: _):
            return line
        }
    }
    
    case expectedArray
    case expectedObject
    case internalStateError(line: Int, column: Int)
    case invalidDate(String?)
    case invalidData(String?)
    case endOfObject(line: Int, column: Int)
    case unknownJSONStrategy
    case missingKeyedContainer
    case missingUnkeyedContainer
    case missingSuperDecoder
    case endOfArray
    case decodingError(expected: Any.Type, keyPath: [CodingKey])
    case invalidTopLevelObject(line: Int, column: Int)
    case missingData(line: Int, column: Int)
    case invalidLiteral(line: Int, column: Int)
    case invalidObjectIdLiteral(line: Int, column: Int)
    case missingToken(line: Int, column: Int, token: UInt8, reason: Reason)
    case unexpectedToken(line: Int, column: Int, token: UInt8, reason: Reason)
    case unexpectedEscapingToken
}

internal struct TypeConversionError<F: FixedWidthInteger>: Error {
    let from: F
    let to: Any.Type
}
