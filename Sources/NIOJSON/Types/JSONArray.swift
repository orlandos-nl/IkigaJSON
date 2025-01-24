import Foundation
import NIOCore
import JSONCore

public enum JSONArrayError: Error {
    case expectedArray
    case parsingError(JSONParserError)
}

/// An array containing only JSONValue types.
///
/// These types may be arbitrarily mixes, so a JSONArray is not strictly required to only have values of the same concrete type such as `Array<String>`.
///
/// Creat a new JSONArray from an array literal:
///
///     var names: JSONArray = ["Joannis", "Robbert", "Testie"]
///
/// To create a JSONArray with no key-value pairs, use an empty array literal (`[]`)
/// or use the empty initializer (`JSONArray()`)
public struct JSONArray: ExpressibleByArrayLiteral, Sequence, Equatable, CustomStringConvertible {
    public static func == (lhs: JSONArray, rhs: JSONArray) -> Bool {
        let lhsCount = lhs.count
        guard lhsCount == rhs.count else {
            return false
        }
        
        for i in 0..<lhsCount where !equateJSON(lhs[i], rhs[i]) {
            return false
        }
        
        return true
    }
    
    /// The raw textual (JSON formatted) representation of this JSONArray
    public internal(set) var jsonBuffer: ByteBuffer
    
    /// An internal index that keeps track of all values within this JSONArray
    var jsonDescription: JSONDescription
    
    /// A textual (JSON formatted) representation of this JSONArray as `Foundation.Data`
    public var data: Data {
        return jsonBuffer.withUnsafeReadableBytes { buffer in
            return Data(buffer: buffer.bindMemory(to: UInt8.self))
        }
    }

    public var description: String {
        string
    }
    
    /// A list of all top-level keys within this JSONArray
    public var string: String! {
        return String(data: data, encoding: .utf8)
    }
    
    /// Creates a new, empty JSONArray
    public init() {
        self.init(descriptionSize: 4_096)
    }
    
    /// Parses the data as a JSON Array and configures this JSONArray to index and represent the JSON data
    public init(data: Data) throws {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        try self.init(buffer: buffer)
    }
    
    /// Parses the buffer as a JSON Array and configures this JSONArray to index and represent the JSON data
    public init(buffer: ByteBuffer) throws(JSONArrayError) {
        self.jsonBuffer = buffer
        
        do {
            self.jsonDescription = try buffer.withUnsafeReadableBytes { buffer in
                Result<JSONDescription, JSONParserError> { () throws(JSONParserError) -> JSONDescription in
                    let buffer = buffer.bindMemory(to: UInt8.self)
                    var tokenizer = JSONTokenizer(
                        pointer: buffer.baseAddress!,
                        count: buffer.count,
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
    }
    
    /// An internal type that creates an empty JSONArray with a predefined expected description size
    private init(descriptionSize: Int) {
        var buffer = ByteBufferAllocator().buffer(capacity: 4_096)
        buffer.writeInteger(UInt8.squareLeft)
        buffer.writeInteger(UInt8.squareRight)
        self.jsonBuffer = buffer
        
        let description = JSONDescription(size: descriptionSize)
        let context = description.arrayStartFound(JSONToken.ArrayStart(start: .init(byteIndex: 0)))
        let result = JSONToken.ArrayEnd(
            start: JSONSourcePosition(byteIndex: 0),
            end: JSONSourcePosition(byteIndex: 2),
            memberCount: 0
        )
        description.arrayEndFound(result, context: context)

        self.jsonDescription = description
    }
    
    public func makeIterator() -> JSONArrayIterator {
        return JSONArrayIterator(array: self)
    }
    
    /// Creates a new JSONArray from an array literal.
    ///
    ///     var names: JSONArray = ["Joannis", "Robbert", "Testie"]
    public init(arrayLiteral elements: JSONValue...) {
        self.init()
        
        for element in elements {
            self.append(element)
        }
    }
    
    public var count: Int {
        return jsonDescription.arrayObjectCount()
    }
    
    internal init(buffer: ByteBuffer, description: JSONDescription) {
        self.jsonBuffer = buffer
        self.jsonDescription = description
    }
    
    public mutating func append(_ value: JSONValue) {
        let oldSize = jsonBuffer.writerIndex
        // Before `]`
        jsonBuffer.moveWriterIndex(to: jsonBuffer.writerIndex &- 1)
        
        if count > 0 {
            jsonBuffer.writeInteger(UInt8.comma)
        }
        
        let valueJSONOffset = jsonBuffer.writerIndex
        let indexOffset = jsonDescription.writtenBytes

        defer {
            jsonBuffer.writeInteger(UInt8.squareRight)
            let extraSize = jsonBuffer.writerIndex - oldSize
            jsonDescription.incrementArrayCount(jsonSize: Int32(extraSize), atIndexOffset: indexOffset)
        }
        
        func write(_ string: String) -> (offset: Int, length: Int) {
            jsonBuffer.writeString(string)
            let length = jsonBuffer.writerIndex - valueJSONOffset
            return (offset: valueJSONOffset, length: length)
        }
        
        switch value {
        case let value as String:
            // TODO: Without copy
            let (escaped, bytes) = value.escaped
            jsonBuffer.writeInteger(UInt8.quote)
            jsonBuffer.writeBytes(bytes)
            jsonBuffer.writeInteger(UInt8.quote)
            let length = jsonBuffer.writerIndex - valueJSONOffset
            let token = JSONToken.String(
                start: JSONSourcePosition(byteIndex: jsonBuffer.writerIndex),
                byteLength: length,
                usesEscaping: escaped
            )
            jsonDescription.describeString(token)
        case let value as Int:
            let bounds = write(String(value))
            let token = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: bounds.offset),
                byteLength: bounds.length,
                isInteger: true
            )
            jsonDescription.describeNumber(token)
        case let value as Double:
            let bounds = write(String(value))
            let token = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: bounds.offset),
                byteLength: bounds.length,
                isInteger: false
            )
            jsonDescription.describeNumber(token)
        case let value as Bool:
            if value {
                jsonBuffer.writeStaticString(boolTrue)
                jsonDescription.describeTrue(atJSONOffset: Int32(valueJSONOffset))
            } else {
                jsonBuffer.writeStaticString(boolFalse)
                jsonDescription.describeFalse(atJSONOffset: Int32(valueJSONOffset))
            }
        case is NSNull:
            jsonBuffer.writeStaticString(nullBytes)
            jsonDescription.describeNull(atJSONOffset: Int32(valueJSONOffset))
        case var value as JSONArray:
            jsonBuffer.writeBuffer(&value.jsonBuffer)
            jsonDescription.addNestedDescription(value.jsonDescription, at: Int32(valueJSONOffset))
        case var value as JSONObject:
            jsonBuffer.writeBuffer(&value.jsonBuffer)
            jsonDescription.addNestedDescription(value.jsonDescription, at: Int32(valueJSONOffset))
        default:
            preconditionFailure("Unsupported JSON value \(value)")
        }
    }

//    public mutating func remove(at index: Int) {
//        _checkBounds(index)
//
//        let indexStart = reader.offset(forIndex: index)
//        let bounds = reader.dataBounds(atIndexOffset: indexStart)
//        description.removeArrayDescription(atIndex: indexStart, jsonOffset: bounds.offset, removedLength: bounds.length)
//    }

    private func _checkBounds(_ index: Int) {
        precondition(index <= jsonDescription.arrayObjectCount(), "Index out of bounds. \(index) > \(count)")
        precondition(index >= 0, "Negative index requested for JSONArray.")
    }
    
    private func value(at index: Int, in json: UnsafePointer<UInt8>) -> JSONValue {
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
            let subBuffer = jsonBuffer.getSlice(at: Int(jsonBounds.offset), length: Int(jsonBounds.length))!
            
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
            return string.makeString(from: json, unicode: true)!
        case .integer:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let number = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                isInteger: type == .integer
            )
            return number.makeInt(from: json)!
        case .floatingNumber:
            let bounds = jsonDescription.dataBounds(atIndexOffset: offset)
            let number = JSONToken.Number(
                start: JSONSourcePosition(byteIndex: Int(bounds.offset)),
                byteLength: Int(bounds.length),
                isInteger: type == .integer
            )
            return number.makeDouble(from: json)
        case .null:
            return NSNull()
        }
    }

    public subscript(index: Int) -> JSONValue {
        get {
            return jsonBuffer.withBytePointer { pointer in
                value(at: index, in: pointer)
            }
        }
        set {
            _checkBounds(index)
            
            // Array descriptions are 17 bytes
            var offset = Constants.firstArrayObjectChildOffset
            
            for _ in 0..<index {
                jsonDescription.skipIndex(atOffset: &offset)
            }

            jsonDescription.rewrite(buffer: &jsonBuffer, to: newValue, at: offset)
        }
    }
}

extension String {
    internal var escaped: (Bool, [UInt8]) {
        var escaped = false
        
        var characters = [UInt8](self.utf8)
        
        var i = characters.count
        nextByte: while i > 0 {
            i = i &- 1
            
            switch characters[i] {
            case .newLine:
                escaped = true
                characters[i] = .backslash
                characters.insert(.n, at: i &+ 1)
            case .carriageReturn:
                escaped = true
                characters[i] = .backslash
                characters.insert(.r, at: i &+ 1)
            case .quote:
                escaped = true
                characters.insert(.backslash, at: i)
            case .tab:
                escaped = true
                characters[i] = .backslash
                characters.insert(.t, at: i &+ 1)
            case .backspace:
                escaped = true
                characters[i] = .backslash
                characters.insert(.b, at: i &+ 1)
            case .formFeed:
                escaped = true
                characters[i] = .backslash
                characters.insert(.f, at: i &+ 1)
            case .backslash:
                escaped = true
                characters.insert(.backslash, at: i &+ 1)
            default:
                continue
            }
        }
        
        return (escaped, characters)
    }
}

public struct JSONArrayIterator: IteratorProtocol {
    private let array: JSONArray
    
    init(array: JSONArray) {
        self.array = array
        self.count = array.count
    }
    
    private let count: Int
    private var index = 0
    
    public mutating func next() -> JSONValue? {
        guard index < count else { return nil }
        defer { index = index &+ 1 }
        return array[index]
    }
}
