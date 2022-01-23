public enum JSONParserError: Error {
    public enum Reason {
        case expectedObjectKey
        case expectedObjectClose
        case expectedTopLevelObject
        case expectedValue
        case expectedColon
        case expectedComma
        case expectedArrayClose
    }
    
    case expectedObject
    case internalStateError
    case invalidDate(String?)
    case invalidData(String?)
    case endOfObject
    case unknownJSONStrategy
    case missingKeyedContainer
    case missingUnkeyedContainer
    case missingSuperDecoder
    case decodingError(expected: Any.Type, keyPath: [CodingKey])
    case invalidTopLevelObject
    case missingData, invalidLiteral
    case missingToken(UInt8, reason: Reason)
    case unexpectedToken(UInt8, reason: Reason)
}

internal struct TypeConversionError<F: FixedWidthInteger>: Error {
    let from: F
    let to: Any.Type
}
