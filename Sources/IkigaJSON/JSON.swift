import Foundation

internal struct JSONParser {
    internal init(pointer: UnsafePointer<UInt8>, count: Int) {
        self.pointer = pointer
        self.count = count
    }
    
    internal private(set) var totalOffset = 0
    internal private(set) var pointer: UnsafePointer<UInt8>
    internal private(set) var count: Int
    
    internal mutating func advance(_ offset: Int) {
        totalOffset = totalOffset &+ offset
        pointer += offset
        count = count &- offset
    }
    
    internal var hasMoreData: Bool {
        return count > 0
    }
    
    private func assertMoreData() throws {
        guard hasMoreData else {
            throw JSONError.missingData
        }
    }
    
    fileprivate mutating func _skipWhitespace() {
        var offset = 0
        
        loop: while offset < count {
            let byte = pointer[offset]
            
            if byte != .space && byte != .tab && byte != .carriageReturn && byte != .newLine {
                break loop
            }
            
            offset = offset &+ 1
        }
        
        advance(offset)
    }
}

extension JSONParser {
    internal mutating func skipWhitespace() throws {
        _skipWhitespace()
        try assertMoreData()
    }
    
    internal static func scanArray(fromPointer pointer: UnsafePointer<UInt8>, count: Int) throws -> JSONArray {
        var parser = JSONParser(pointer: pointer, count: count)
        
        guard case .array(let array) = try parser.scanValue().storage else {
            throw JSONError.invalidTopLevelObject
        }
        
        return JSONArray(array: array)
    }
    
    internal static func scanValue(fromPointer pointer: UnsafePointer<UInt8>, count: Int) throws -> JSONValue {
        var parser = JSONParser(pointer: pointer, count: count)
        return try parser.scanValue()
    }
    
    internal static func scanObject(fromPointer pointer: UnsafePointer<UInt8>, count: Int) throws -> JSONObject {
        var parser = JSONParser(pointer: pointer, count: count)
        
        guard case .object(let object) = try parser.scanValue().storage else {
            throw JSONError.invalidTopLevelObject
        }
        
        return JSONObject(object: object)
    }
}
