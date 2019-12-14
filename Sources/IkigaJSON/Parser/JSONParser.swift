import Foundation

/// This type is responsible for creating a JSONDescription for an inputted JSON buffer
internal struct JSONParser {
    /// Creates a new JSONParser and initializes it
    internal init(pointer: UnsafePointer<UInt8>, count: Int) {
        self.pointer = pointer
        self.count = count
        self.description = JSONDescription(size: min(max(count, 4096), 16_777_216))
    }
    
    /// Recycles this JSONParser for a second initialization and parsing
    /// Initializes the JSONParser with a pointer and count.
    /// This is a separate function so the allocated description buffer can be reused.
    mutating func recycle(pointer: UnsafePointer<UInt8>, count: Int) {
        description.recycle()
        self.currentOffset = 0
        self.pointer = pointer
        self.count = count
    }
    
    /// This description is where we write a binary format that describes the JSON data.
    ///
    /// It's made to be highly performant in parsing and slicing JSON
    @usableFromInline
    internal var description: JSONDescription
    
    /// The amount of parsed bytes from the `pointer`. Also the first index we have to parse next since programmers start at 0
    internal private(set) var currentOffset = 0
    
    /// The pointer that will be parsed
    internal private(set) var pointer: UnsafePointer<UInt8>
    
    /// The amount of bytes supposedly in the pointer, this must be guaranteed internally
    internal private(set) var count: Int
    
    /// Advances the amount of bytes processed and updates the related offset and count
    internal mutating func advance(_ offset: Int) {
        currentOffset = currentOffset &+ offset
        pointer += offset
        count = count &- offset
    }
    
    internal var hasMoreData: Bool {
        assert(count >= 0, "The count was reduced into negatives")
        return count != 0
    }
    
    /// Throws an error if the count is 0
    private func assertMoreData() throws {
        guard hasMoreData else {
            throw JSONError.missingData
        }
    }
    
    /// Skips all whitespace (space, tab, carriage-return and newline)
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
    /// Skips whitespace and throws an error if there is no data left. Usually this is the best way to parse since you'll be wanting to parse something after the whitespace.
    internal mutating func skipWhitespace() throws {
        _skipWhitespace()
        try assertMoreData()
    }
    
    /// Scans a value into the description and returns the description.
    ///
    /// - WARNING: If you recycle this parser you cannot use the description expecting the old results
    internal static func scanValue(fromPointer pointer: UnsafePointer<UInt8>, count: Int) throws -> JSONDescription {
        var parser = JSONParser(pointer: pointer, count: count)
        try parser.scanValue()
        return parser.description
    }
}
