import Foundation
import NIOCore
import _JSONCore

public struct JSONArrayView: ~Copyable, ~Escapable {
  /// The raw textual (JSON formatted) representation of this JSONArray
    private let span: Span<UInt8>
    
    /// An internal index that keeps track of all values within this JSONObject
    var jsonDescription: JSONDescription
    
    /// A list of all top-level keys within this JSONObject
    public var keys: [String] {
        return self.jsonDescription.keys(
            in: span, unicode: true, convertingSnakeCasing: false)
    }
    
    @safe
    public var data: Data {
        unsafe span.withUnsafeBytes { buffer in
            unsafe Data(buffer)
        }
    }
    
    /// A JSON formatted String with the contents of this JSONObject
    
    @available(macOS 26.0, *)
    public var string: String {
        get throws {
            let span = try UTF8Span(validating: span)
            return String(copying: span)
        }
    }
    
    /// Parses the buffer as a JSON Object and configures this JSONObject to index and represent the JSON data
    @_lifetime(copy span)
    public init(span: Span<UInt8>) throws(JSONArrayError) {
        let jsonDescription: JSONDescription
        do {
            jsonDescription = try Result<JSONDescription, JSONParserError> { () throws(JSONParserError) -> JSONDescription in
                var tokenizer = JSONTokenizer(
                    span: span,
                    destination: JSONDescription()
                )
                try tokenizer.scanValue()
                return tokenizer.destination
            }.get()
        } catch {
            throw JSONArrayError.parsingError(error)
        }
        
        guard jsonDescription.topLevelType == .array else {
            throw JSONArrayError.expectedArray
        }
        
        self.span = span
        self.jsonDescription = jsonDescription
    }

  public var count: Int {
    return jsonDescription.arrayObjectCount()
  }
    
  private func _checkBounds(_ index: Int) {
    precondition(
      index <= jsonDescription.arrayObjectCount(), "Index out of bounds. \(index) > \(count)")
    precondition(index >= 0, "Negative index requested for JSONArray.")
  }

  private func value(at index: Int, in span: Span<UInt8>) -> JSONValue {
    _checkBounds(index)

    // Array descriptions are 17 bytes
    var offset = Constants.firstArrayObjectChildOffset

    for _ in 0..<index {
      jsonDescription.skipIndex(atOffset: &offset)
    }

    let type = jsonDescription.type(atOffset: offset)

    switch type {
    case .object, .array:
      let indexLength = jsonDescription.indexLength(atOffset: offset)
      let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)

      let subDescription = jsonDescription.slice(from: offset, length: indexLength)
      subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
        let subSpan = span.extracting(Int(jsonBounds.offset) ..< Int(jsonBounds.offset + jsonBounds.length))
        var subBuffer = ByteBuffer()
        unsafe subBuffer.writeBytes(subSpan.bytes)

      if type == .object {
        return JSONObject(buffer: subBuffer, description: subDescription)
      } else {
        return JSONArray(buffer: subBuffer, description: subDescription)
      }
    case .boolTrue:
      return true
    case .boolFalse:
      return false
    case .string, .stringWithEscaping:
      let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
      let string = JSONToken.String(
        start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
        byteLength: Int(bounds.length),
        usesEscaping: type == .stringWithEscaping
      )
      return string.makeString(from: span, unicode: true)!
    case .integer:
      let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
      let number = JSONToken.Number(
        start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
        byteLength: Int(bounds.length),
        isInteger: type == .integer
      )
      return number.makeInt(from: span)!
    case .floatingNumber:
      let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
      let number = JSONToken.Number(
        start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
        byteLength: Int(bounds.length),
        isInteger: type == .integer
      )
      return number.makeDouble(from: span)
    case .null:
      return NSNull()
    }
  }

  public subscript(index: Int) -> JSONValue {
    value(at: index, in: span)
  }
}
