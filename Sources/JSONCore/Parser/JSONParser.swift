import Foundation

/// This type is responsible for creating a JSONDescription for an inputted JSON buffer
public struct JSONTokenizer<Destination: JSONTokenizerDestination>: ~Copyable {
    /// Creates a new JSONParser and initializes it
    package init(
        pointer: UnsafePointer<UInt8>,
        count: Int,
        destination: Destination
    ) {
        self.pointer = pointer
        self.count = count
        self.destination = destination
    }

    /// The amount of parsed bytes from the `pointer`. Also the first index we have to parse next since programmers start at 0
    package private(set) var currentOffset = 0
    
    /// The pointer that will be parsed
    internal private(set) var pointer: UnsafePointer<UInt8>
    
    /// The amount of bytes supposedly in the pointer, this must be guaranteed internally
    internal private(set) var count: Int
    
    internal private(set) var line = 0
    internal private(set) var lastLineOffset = 0
    public var destination: Destination
    internal var column: Int {
        currentOffset - lastLineOffset
    }
    
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
    private func assertMoreData() throws(JSONParserError) {
        guard hasMoreData else {
            throw JSONParserError.missingData(line: line, column: column)
        }
    }
    
    /// Skips all whitespace (space, tab, carriage-return and newline)
    fileprivate mutating func _skipWhitespace() {
        var offset = 0
        
        loop: while offset < count {
            let byte = pointer[offset]
            
            if byte == .newLine {
                line += 1
                lastLineOffset = currentOffset + 1
            } else if byte != .space && byte != .tab && byte != .carriageReturn {
                break loop
            }
            
            offset = offset &+ 1
        }
        
        advance(offset)
    }
}

extension JSONTokenizer {
    /// Skips whitespace and throws an error if there is no data left. Usually this is the best way to parse since you'll be wanting to parse something after the whitespace.
    internal mutating func skipWhitespace() throws(JSONParserError) {
        _skipWhitespace()
        try assertMoreData()
    }
}
