import NIOCore
import _JSONCore

#if swift(>=6.2.1) && Spans
  @available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
public struct StreamingJSONLinesDecoder<Element: Decodable> {
  private let maxElementSize: Int
  private let settings: JSONDecoderSettings
  private var buffer = ByteBuffer()
  public var decoder: IkigaJSONDecoder
  private var state: State = .expectingValue

  enum State {
    case expectingValue, expectingCR, expectingLF
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

    var elements = [Element]()

    while let byte: UInt8 = buffer.getInteger(at: buffer.readerIndex) {
      switch byte {
      case .squareLeft, .curlyLeft:
        guard case .expectingValue = state else {
          throw JSONLinesDecodingError.unexpectedElement
        }

        let readerIndex = buffer.readerIndex
        do {
          let element = try decoder.decode(Element.self, from: &buffer)
          elements.append(element)
          state = .expectingCR
        } catch let error as JSONParserError {
          if case .missingData = error {
            buffer.moveReaderIndex(to: readerIndex)
            buffer.discardReadBytes()
            return elements
          } else {
            throw error
          }
        }
      case .carriageReturn:
        guard case .expectingCR = state else {
          throw JSONLinesDecodingError.unexpectedCarriageReturn
        }

        buffer.moveReaderIndex(forwardBy: 1)
        state = .expectingLF
        continue
      case .newLine:
        switch state {
        case .expectingLF, .expectingCR:
          buffer.moveReaderIndex(forwardBy: 1)
          state = .expectingValue
          continue
        default:
          throw JSONLinesDecodingError.unexpectedLineFeed
        }
      default:
        throw JSONLinesDecodingError.unexpectedToken(byte)
      }
    }

    buffer.discardReadBytes()
    return elements
  }
}

private enum JSONLinesDecodingError: Error {
  case unexpectedElement
  case unexpectedCarriageReturn
  case unexpectedLineFeed
  case unexpectedToken(UInt8)
}
