//import NIOCore
//public struct StreamingJSONArrayDecoder<Element: Decodable> {
//    enum State {
//        // Before the array has openend
//        case beforeArrayOpen
//        
//        // After array has opened, or element has been parsed
//        case expectCommaOrClose
//        
//        // After a comma separating elements
//        case expectElement
//        
//        // After the array has closed
//        case afterArrayClose
//    }
//    
//    private let maxElementSize: Int
//    private let settings: JSONDecoderSettings
//    private var state = State.beforeArrayOpen
//    public var didReachEnd: Bool {
//        state == .afterArrayClose
//    }
//    
//    public init(
//        decoding type: Element.Type,
//        maxElementSize: Int = Int(UInt16.max),
//        settings: JSONDecoderSettings = JSONDecoderSettings()
//    ) {
//        self.settings = settings
//        self.maxElementSize = maxElementSize
//    }
//    
//    /// Parses all readable elements from `buffer`.
//    /// If `buffer.readableBytes == 0` after calling this function, you can discard the buffer.
//    /// If `didReachEnd == true`, you've reached the end of your JSON Array stream
//    /// If `buffer.readableBytes > 0`, prepend the (remainder of this) buffer to the next chunk
//    mutating func parseBuffer(_ buffer: inout ByteBuffer) throws -> [Element] {
//        switch state {
//        case .beforeArrayOpen:
//            while let byte: UInt8 = buffer.readInteger() {
//                switch byte {
//                case .squareLeft:
//                    state = .inbetweenArrayOpen
//                    return try parseBuffer(buffer)
//                case .space, .tab, .carriageReturn:
//                    continue
//                default:
//                    throw StreamingJSONDecodingError.expectedArrayOpen
//                }
//            }
//            
//            throw StreamingJSONDecodingError.unexpectedEndOfFile
//        case .inbetweenArrayOpen:
//            var elements = [Element]()
//            
//            while let byte: UInt8 = buffer.readInteger() {
//                switch byte {
//                case .squareRight where state == .expectCommaOrClose:
//                    state = .afterArrayClose
//                    return elements
//                case .squareRight where state == .expectCommaOrClose:
//                    state = .afterArrayClose
//                    return elements
//                case .space, .tab, .carriageReturn:
//                    continue
//                case .comma where state == .expectCommaOrClose:
//                    state = .expectElement
//                default:
//                    guard case .expectElement = self else {
//                        throw StreamingJSONArrayDecoder.unexpectedToken
//                    }
//                    
//                    if buffer.readableBytes == 0 {
//                        // Un-read the last byte, because we're not using it
//                        buffer.moveReaderIndex(to: buffer.readerIndex - 1)
//                        
//                        return elements
//                    }
//                    
//                    buffer.readWithUnsafeReadableBytes { buffer in
//                        let buffer = buffer.bindMemory(to: UInt8.self)
//                        let parser = JSONParser(
//                            pointer: buffer.baseAddress!,
//                            count: buffer.count
//                        )
//                        try parser.scanValue()
//                        let decoder = IkigaJSONDecoder(settings: settings)
//                        let element = try decoder.decode(
//                            Element.self,
//                            from: buffer,
//                            parser: parer,
//                            settings: settings
//                        )
//                        elements.append(element)
//                        
//                        return parser.currentOffset
//                    }
//                }
//            }
//
//            return elements
//        case .afterArrayClose:
//            return []
//        }
//    }
//}
//
//fileprivate enum StreamingJSONDecodingError: Error {
//    case expectedArrayOpen
//    case unexpectedEndOfFile
//    case unexpectedToken
//}
