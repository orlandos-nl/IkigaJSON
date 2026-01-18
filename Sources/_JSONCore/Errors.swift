public enum JSONParserError: Error, Sendable {
  public enum Reason: Sendable {
    case expectedObjectKey
    case expectedObjectClose
    case expectedTopLevelObject
    case expectedValue
    case expectedColon
    case expectedComma
    case expectedArrayClose

    // Marked unavailable to save binary size
    @_unavailableInEmbedded
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

  // Marked unavailable to save binary size
  @_unavailableInEmbedded
  private var shortDescription: String {
    switch self {
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
    case .internalStateError:
      return "Internal State Error"
    case .missingToken(_, _, let uInt8, let reason):
      return "Missing token '\(Character(.init(uInt8)))': \(reason)"
    case .unexpectedToken(_, _, let uInt8, let reason):
      return "Unexpected token '\(Character(.init(uInt8)))': \(reason)"
    }
  }

  @_unavailableInEmbedded
  public var description: String {
    return "\(shortDescription) at \(line):\(column)"
  }

  // Marked unavailable to save binary size
  @_unavailableInEmbedded
  public var column: Int {
    switch self {
    case .internalStateError(_, let column):
      return column
    case .endOfObject(_, let column):
      return column
    case .invalidTopLevelObject(_, let column):
      return column
    case .missingData(_, let column):
      return column
    case .invalidLiteral(_, let column):
      return column
    case .invalidObjectIdLiteral(_, let column):
      return column
    case .missingToken(_, let column, token: _, reason: _):
      return column
    case .unexpectedToken(_, let column, token: _, reason: _):
      return column
    }
  }

  // Marked unavailable to save binary size
  @_unavailableInEmbedded
  public var line: Int {
    switch self {
    case .internalStateError(let line, _):
      return line
    case .endOfObject(let line, _):
      return line
    case .invalidTopLevelObject(let line, _):
      return line
    case .missingData(let line, _):
      return line
    case .invalidLiteral(let line, _):
      return line
    case .invalidObjectIdLiteral(let line, _):
      return line
    case .missingToken(let line, _, token: _, reason: _):
      return line
    case .unexpectedToken(let line, _, token: _, reason: _):
      return line
    }
  }

  case internalStateError(line: Int, column: Int)
  case endOfObject(line: Int, column: Int)
  case invalidTopLevelObject(line: Int, column: Int)
  case missingData(line: Int, column: Int)
  case invalidLiteral(line: Int, column: Int)
  case invalidObjectIdLiteral(line: Int, column: Int)
  case missingToken(line: Int, column: Int, token: UInt8, reason: Reason)
  case unexpectedToken(line: Int, column: Int, token: UInt8, reason: Reason)
}

public struct TypeConversionError<F: FixedWidthInteger & Sendable>: Error {
  let from: F
  let to: Any.Type

  public init(from: F, to: Any.Type) {
    self.from = from
    self.to = to
  }
}

// Marked unavailable to save binary size
@_unavailableInEmbedded
extension JSONParserError: CustomStringConvertible {}

// Marked unavailable to save binary size
@_unavailableInEmbedded
extension JSONParserError.Reason: CustomStringConvertible {}
