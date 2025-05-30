#if swift(>=6.2) && Spans
/// This type is responsible for creating a JSONDescription for an inputted JSON buffer
public struct JSONTokenizer<Destination: JSONTokenizerDestination>: ~Copyable, ~Escapable {
    /// Creates a new JSONParser and initializes it
    @lifetime(copy span)
    public init(
        span: borrowing Span<UInt8>,
        destination: Destination
    ) {
        self.bytes = span
        self.destination = destination
    }
    
    /// Creates a new JSONParser and initializes it
    ///
    /// The Bytes are owned by the JSONTokenizer for the duration of its usage
    /// As soon as the type is destroyed/consumed, you get ownership of the bytes
    /// Any deallocation of the bytes should happen after JSONTokenizer is destroyed/consumed
    @lifetime(borrow bytes)
    public init(
        bytes: borrowing UnsafeBufferPointer<UInt8>,
        destination: Destination
    ) {
        self.bytes = bytes.span
        self.destination = destination
    }

    /// The amount of parsed bytes from the `pointer`. Also the first index we have to parse next since programmers start at 0
    public private(set) var currentOffset = 0
    
    /// The pointer that will be parsed
    @usableFromInline
    internal let bytes: Span<UInt8>
    
    /// The amount of bytes supposedly in the pointer, this must be guaranteed internally
    @usableFromInline
    internal var count: Int {
        bytes.count - currentOffset
    }
    
    #if SourcePositions
    public private(set) var line = 0
    public private(set) var lastLineOffset = 0
    #else
    @usableFromInline
    package var line: Int { -1 }

    @usableFromInline
    package var lastLineOffset: Int { -1 }
    #endif

    @inline(__always)
    @usableFromInline
    internal var currentByte: UInt8 {
        self[0]
    }

    public var destination: Destination

    #if SourcePositions
    @inlinable
    public var column: Int {
        currentOffset - lastLineOffset
    }
    #else
    @usableFromInline
    package var column: Int { -1 }
    #endif

    /// Advances the amount of bytes processed and updates the related offset and count
    @lifetime(copy self)
    @usableFromInline
    internal mutating func advance(_ offset: Int) {
        currentOffset += offset
    }
}
#else
/// This type is responsible for creating a JSONDescription for an inputted JSON buffer
public struct JSONTokenizer<Destination: JSONTokenizerDestination>: ~Copyable {
    /// Creates a new JSONParser and initializes it
    ///
    /// The Bytes are owned by the JSONTokenizer for the duration of its usage
    /// As soon as the type is destroyed/consumed, you get ownership of the bytes
    /// Any deallocation of the bytes should happen after JSONTokenizer is destroyed/consumed
    public init(
        bytes: UnsafeBufferPointer<UInt8>,
        destination: Destination
    ) {
        self.bytes = bytes
        self.destination = destination
    }

    /// The amount of parsed bytes from the `pointer`. Also the first index we have to parse next since programmers start at 0
    public private(set) var currentOffset = 0
    
    /// The pointer that will be parsed
    @usableFromInline
    internal let bytes: UnsafeBufferPointer<UInt8>
    
    /// The amount of bytes supposedly in the pointer, this must be guaranteed internally
    @usableFromInline
    internal var count: Int {
        bytes.count - currentOffset
    }
    
    #if SourcePositions
    public private(set) var line = 0
    public private(set) var lastLineOffset = 0
    #else
    @usableFromInline
    package var line: Int { -1 }

    @usableFromInline
    package var lastLineOffset: Int { -1 }
    #endif

    @inline(__always)
    @usableFromInline
    internal var currentByte: UInt8 {
        self[0]
    }

    public var destination: Destination

    #if SourcePositions
    @usableFromInline
    public var column: Int {
        currentOffset - lastLineOffset
    }
    #else
    @usableFromInline
    package var column: Int { -1 }
    #endif

    /// Advances the amount of bytes processed and updates the related offset and count
    @usableFromInline
    internal mutating func advance(_ offset: Int) {
        currentOffset += offset
    }
}
#endif

extension JSONTokenizer {
    @inline(__always)
    @usableFromInline
    internal subscript(offset: Int) -> UInt8 {
        bytes[currentOffset + offset]
    }

    @usableFromInline
    internal var hasMoreData: Bool {
        return currentOffset < bytes.count
    }
    
    /// Throws an error if the count is 0
    private func assertMoreData() throws(JSONParserError) {
        guard hasMoreData else {
            throw JSONParserError.missingData(line: line, column: column)
        }
    }
    
    /// Skips all whitespace (space, tab, carriage-return and newline)
    @_optimize(speed)
    @usableFromInline
    mutating func _skipWhitespace() {
        var offset = 0
        
        loop: while offset < count {
            let byte = self[offset]
            
            #if SourcePositions
            if byte == .newLine {
                line += 1
                lastLineOffset = currentOffset + 1
            }
            #endif

            switch byte {
            case .space, .tab, .carriageReturn, .newLine:
                offset += 1
            default:
                break loop
            }
        }
        
        advance(offset)
    }
}

extension JSONTokenizer {
    /// Skips whitespace and throws an error if there is no data left. Usually this is the best way to parse since you'll be wanting to parse something after the whitespace.
    @_optimize(speed)
    @inline(__always)
    @usableFromInline
    internal mutating func skipWhitespace() throws(JSONParserError) {
        _skipWhitespace()
        try assertMoreData()
    }
}
