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
    
    @available(macOS 26.0, iOS 26.0, *)
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
            jsonDescription = try unsafe span.withUnsafeBufferPointer { buffer in
                Result<JSONDescription, JSONParserError> { () throws(JSONParserError) -> JSONDescription in
                    var tokenizer = unsafe JSONTokenizer(
                        bytes: buffer,
                        destination: JSONDescription()
                    )
                    try tokenizer.scanValue()
                    return tokenizer.destination
                }
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
    
    @_lifetime(borrow span)
    internal init(span: Span<UInt8>, jsonDescription: JSONDescription) throws(JSONObjectError) {
        guard jsonDescription.topLevelType == .array else {
            throw JSONObjectError.expectedObject
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
    
    public func string(forIndex index: Int) throws -> String? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }
        
        let type = jsonDescription.type(atOffset: offset)
        guard type == .string || type == .stringWithEscaping else {
            return nil
        }

        let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
        let string = JSONToken.String(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            usesEscaping: type == .stringWithEscaping
        )
        return string.makeString(from: span, unicode: true)
    }

    public func integer(forIndex index: Int) throws -> Int? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }
        
        let type = jsonDescription.type(atOffset: offset)
        guard type == .integer else {
            return nil
        }
        
        let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
        let number = JSONToken.Number(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            isInteger: type == .integer
        )
        return number.makeInt(from: span)
    }
    
    public func double(forIndex index: Int) throws -> Double? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }
        
        let type = jsonDescription.type(atOffset: offset)
        guard type == .floatingNumber else {
            return nil
        }
        let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
        let number = JSONToken.Number(
            start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
            byteLength: Int(bounds.length),
            isInteger: type == .integer
        )
        return number.makeDouble(from: span)
    }
    
    public func boolean(forIndex index: Int) throws -> Bool? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }

        switch jsonDescription.type(atOffset: offset) {
        case .object, .array, .string, .stringWithEscaping, .integer, .floatingNumber, .null:
            return nil
        case .boolTrue:
            return true
        case .boolFalse:
            return false
        }
    }
    
    public func isNull(forIndex index: Int) throws -> Bool? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }

        return jsonDescription.type(atOffset: offset) == .null
    }
    
    public func withObjectView<T, E: Error>(
        forIndex index: Int,
        perform: (borrowing JSONObjectView) throws(E) -> T
    ) throws -> T? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }

        guard jsonDescription.type(atOffset: offset) == .object else {
            return nil
        }
        
        let indexLength = jsonDescription.indexLength(atOffset: offset)
        let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)
        
        let subDescription = jsonDescription.slice(from: offset, length: indexLength)
        subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
        
        let subSpan = span.extracting(Int(jsonBounds.offset) ..< Int(jsonBounds.offset + jsonBounds.length))
        let view = try JSONObjectView(span: subSpan, jsonDescription: subDescription)
        return try perform(view)
    }
    
    public func withArrayView<T, E: Error>(
        forIndex index: Int,
        perform: (borrowing JSONArrayView) throws(E) -> T
    ) throws -> T? {
        _checkBounds(index)

        // Array descriptions are 17 bytes
        var offset = Constants.firstArrayObjectChildOffset

        for _ in 0..<index {
          jsonDescription.skipIndex(atOffset: &offset)
        }

        guard jsonDescription.type(atOffset: offset) == .array else {
            return nil
        }
    
        let indexLength = jsonDescription.indexLength(atOffset: offset)
        let jsonBounds = jsonDescription.dataBounds(atIndexOffset: offset)
        
        let subDescription = jsonDescription.slice(from: offset, length: indexLength)
        subDescription.advanceAllJSONOffsets(by: -jsonBounds.offset)
        
        let subSpan = span.extracting(Int(jsonBounds.offset) ..< Int(jsonBounds.offset + jsonBounds.length))
        let view = try JSONArrayView(span: subSpan, jsonDescription: subDescription)
        return try perform(view)
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

  public subscript(index: Int) -> any JSONValue {
    value(at: index, in: span)
  }
}
