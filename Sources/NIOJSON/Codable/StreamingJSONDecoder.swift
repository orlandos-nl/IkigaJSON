import NIOCore
import JSONCore

public struct StreamingJSONArrayDecoder<Element: Decodable> {
    enum State {
        // Before the array has openend
        case beforeArrayOpen

        case arrayOpen(expectingCommaOrEnd: Bool)

        // After array has opened, or element has been parsed
        case arrayClosed
    }

    private let maxElementSize: Int
    private let settings: JSONDecoderSettings
    private var state = State.beforeArrayOpen
    private var buffer = ByteBuffer()
    public var decoder: IkigaJSONDecoder
    public var didReachEnd: Bool {
        if case .arrayClosed = state {
            return true
        }
        return false
    }
    
    public init(
        decoding type: Element.Type = Element.self,
        maxElementSize: Int = Int(UInt16.max),
        settings: JSONDecoderSettings = JSONDecoderSettings()
    ) {
        self.settings = settings
        self.maxElementSize = maxElementSize
        self.decoder = IkigaJSONDecoder(settings: settings)
    }
    
    /// Parses all readable elements from `buffer`.
    /// If `buffer.readableBytes == 0` after calling this function, you can discard the buffer.
    /// If `didReachEnd == true`, you've reached the end of your JSON Array stream
    /// If `buffer.readableBytes > 0`, prepend the (remainder of this) buffer to the next chunk
    public mutating func parseBuffer(_ newData: ByteBuffer) throws -> [Element] {
        self.buffer.writeImmutableBuffer(newData)

        switch state {
        case .beforeArrayOpen:
            while let byte: UInt8 = buffer.readInteger() {
                switch byte {
                case .squareLeft:
                    state = .arrayOpen(expectingCommaOrEnd: false)
                    return try parseBuffer(ByteBuffer())
                case .space, .tab, .carriageReturn, .newLine:
                    continue
                default:
                    throw StreamingJSONDecodingError.expectedArrayOpen
                }
            }

            return []
        case .arrayOpen(var expectingCommaOrEnd):
            var elements = [Element]()

            while let byte: UInt8 = buffer.getInteger(at: buffer.readerIndex) {
                switch byte {
                case .squareRight:
                    buffer.moveReaderIndex(forwardBy: 1)
                    state = .arrayClosed
                    return elements
                case .squareLeft, .curlyLeft:
                    if expectingCommaOrEnd {
                        throw StreamingJSONDecodingError.expectedArrayOpen
                    }

                    let readerIndex = buffer.readerIndex
                    do {
                        let element = try decoder.decode(Element.self, from: &buffer)
                        elements.append(element)
                        expectingCommaOrEnd = true
                    } catch let error as JSONParserError {
                        if case .missingData = error {
                            buffer.moveReaderIndex(to: readerIndex)
                            state = .arrayOpen(expectingCommaOrEnd: expectingCommaOrEnd)
                            buffer.discardReadBytes()
                            return elements
                        } else {
                            throw error
                        }
                    }
                case .comma where expectingCommaOrEnd:
                    buffer.moveReaderIndex(forwardBy: 1)
                    expectingCommaOrEnd = false
                    continue
                case .space, .tab, .carriageReturn, .newLine:
                    buffer.moveReaderIndex(forwardBy: 1)
                    continue
                default:
                    throw StreamingJSONDecodingError.expectedArrayOpen
                }
            }

            buffer.discardReadBytes()
            state = .arrayOpen(expectingCommaOrEnd: expectingCommaOrEnd)
            return elements
        case .arrayClosed:
            return []
        }
    }
}

fileprivate enum StreamingJSONDecodingError: Error {
    case expectedArrayOpen
    case unexpectedEndOfFile
    case unexpectedToken
}
