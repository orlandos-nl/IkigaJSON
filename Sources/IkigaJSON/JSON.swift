import Foundation

internal struct JSONParser {
    internal init(pointer: UnsafePointer<UInt8>, count: Int) {
        self.pointer = pointer
        self.count = count
    }
    
    internal init() {}
    
    internal mutating func initialize(pointer: UnsafePointer<UInt8>, count: Int) {
        self.pointer = pointer
        self.count = count
    }
    
    mutating func recycle() {
        description.recycle()
        self.totalOffset = 0
        self.pointer = nil
        self.count = nil
    }
    
    internal var description = JSONDescription()
    internal private(set) var totalOffset = 0
    internal private(set) var pointer: UnsafePointer<UInt8>!
    internal private(set) var count: Int!
    
    internal mutating func advance(_ offset: Int) {
        totalOffset = totalOffset &+ offset
        pointer += offset
        count = count &- offset
    }
    
    internal var hasMoreData: Bool {
        assert(count >= 0, "The count was reduced into negatives")
        return count != 0
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
    
    internal static func scanValue(fromPointer pointer: UnsafePointer<UInt8>, count: Int) throws -> JSONDescription {
        var parser = JSONParser(pointer: pointer, count: count)
        try parser.scanValue()
        return parser.description
    }
}
