import _JSONCore
import Foundation

fileprivate let lowercasedRadix16table: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]
fileprivate let uppercasedRadix16table: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46]

fileprivate extension UInt8 {
    func decodeHex() -> UInt8? {
        if let num = lowercasedRadix16table.firstIndex(of: self) {
            return numericCast(num)
        } else if let num = uppercasedRadix16table.firstIndex(of: self) {
            return numericCast(num)
        } else {
            return nil
        }
    }
}

extension JSONToken.String {
    //// Makes a String from a pointer.
    /// Assumes the length is checked against the bounds `self`
    ///
    /// - see: `makeStringFromData` for more information
    func makeString(from pointer: UnsafePointer<UInt8>, unicode: Bool) -> String? {
        try? withStringBuffer(from: pointer, unicode: unicode) { buffer in
            return String(bytes: buffer, encoding: .utf8)
        }
    }

    /// Makes a `Data` blob from a pointer. This data can be used to initialize a string or for comparison operations.
    /// Assumes the length is checked against the bounds `self`
    ///
    /// If `escaping` is false, the string is assumed unescaped and no additional effort will be put
    /// towards unescaping.
    func withStringBuffer<T>(
        from pointer: UnsafePointer<UInt8>,
        unicode: Bool,
        _ body: (inout UnsafeMutableBufferPointer<UInt8>) throws -> T
    ) throws -> T {
        let source = UnsafeBufferPointer(start: pointer + start.byteOffset, count: byteLength)

        return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: byteLength) { buffer in
            var buffer = buffer

            guard usesEscaping else {
                memcpy(buffer.baseAddress!, source.baseAddress!, byteLength)
                return try body(&buffer)
            }

            // If we can't take a shortcut by decoding immediately thanks to an escaping character
            var readerIndex = 0
            var writerIndex = 0
            var unicodes = [UInt16]()

            func flushUnicodes() {
                if !unicodes.isEmpty {
                    var character = String(utf16CodeUnits: unicodes, count: unicodes.count)
                    character.withUTF8 { utf8 in
                        for byte in utf8 {
                            buffer[writerIndex] = byte
                            writerIndex += 1
                        }
                    }
                    unicodes.removeAll(keepingCapacity: true)
                }
            }

            next: while readerIndex < byteLength {
                let byte = source[readerIndex]
                
                // If this character is not a baskslash or this was the last character
                // We don't need to unescape the next character
                if byte != .backslash || readerIndex + 1 >= byteLength {
                    // Flush unprocessed unicodes and move past this character
                    flushUnicodes()
                    buffer[writerIndex] = byte
                    writerIndex += 1
                    readerIndex += 1
                    continue next
                }

                // Remove the backslash and translate the next character
                readerIndex += 1

                if source[readerIndex] == .u {
                    // `\u` indicates a unicode character
                    readerIndex += 1
                    guard readerIndex + 3 < byteLength else {
                        throw UTF8ParsingError()
                    }
                    let unicode = try decodeUnicode(
                        from: (
                            source[readerIndex],
                            source[readerIndex + 1],
                            source[readerIndex + 2],
                            source[readerIndex + 3]
                        )
                    )
                    
                    unicodes.append(unicode)
                    readerIndex += 4

                    // Continue explicitly, so that we do not trigger the unicode 'flush' flow
                    continue next
                }

                flushUnicodes()

                switch source[readerIndex] {
                case .backslash, .solidus, .quote:
                    buffer[writerIndex] = source[readerIndex]
                    writerIndex += 1
                    // Move past this character
                    readerIndex += 1
                case .t:
                    buffer[writerIndex] = .tab
                    writerIndex += 1
                    // Move past this character
                    readerIndex += 1
                case .r:
                    buffer[writerIndex] = .carriageReturn
                    writerIndex += 1
                    // Move past this character
                    readerIndex += 1
                case .n:
                    buffer[writerIndex] = .newLine
                    writerIndex += 1
                    // Move past this character
                    readerIndex += 1
                case .f:
                    buffer[writerIndex] = .formFeed
                    writerIndex += 1
                    // Move past this character
                    readerIndex += 1
                case .b:
                    buffer[writerIndex] = .backspace
                    writerIndex += 1
                    // Move past this character
                    readerIndex += 1
                default:
                    throw UTF8ParsingError()
                }
            }

            flushUnicodes()
            
            // Strip off the trailing bytes
            buffer = UnsafeMutableBufferPointer(start: buffer.baseAddress!, count: writerIndex)
            return try body(&buffer)
        }
    }
}

extension JSONToken.Number {
    /// Parses a `Double` from the pointer
    /// Assumes the length is checked against the bounds `self`
    ///
    /// If `floating` is false, an integer is assumed to reduce parsing weight
    ///
    /// Uses the fast path for doubles if possible, when failing falls back to Foundation.
    ///
    /// https://www.exploringbinary.com/fast-path-decimal-to-floating-point-conversion/
    internal func makeDouble(from pointer: UnsafePointer<UInt8>) -> Double {
        if isInteger {
            return strtoi(pointer + start.byteOffset, length: byteLength)
        } else {
            /// Falls back to the foundation implementation which makes too many copies for this use case
            ///
            /// Used when the implementation is unsure
            return strtod(pointer + start.byteOffset, length: byteLength)
        }
    }
    
    internal func makeInt(from pointer: UnsafePointer<UInt8>) -> Int? {
        var offset = start.byteOffset
        return pointer.makeInt(offset: &offset, length: Int(byteLength))
    }
}

public struct UTF8ParsingError: Error {}

fileprivate func decodeUnicode(
    from bytes: (UInt8, UInt8, UInt8, UInt8),
) throws -> UInt16 {
    guard
        let hex0 = bytes.0.decodeHex(),
        let hex1 = bytes.1.decodeHex(),
        let hex2 = bytes.2.decodeHex(),
        let hex3 = bytes.3.decodeHex()
    else {
        throw UTF8ParsingError()
    }

    var unicode: UInt16 = 0
    unicode &+= UInt16(hex0) &<< 12
    unicode &+= UInt16(hex1) &<< 8
    unicode &+= UInt16(hex2) &<< 4
    unicode &+= UInt16(hex3)

    return unicode
}

fileprivate func strtoi(_ pointer: UnsafePointer<UInt8>, length: Int) -> Double {
    var pointer = pointer
    let endPointer = pointer + length
    var notAtEnd: Bool { pointer != endPointer }

    var result = 0
    while notAtEnd, pointer.pointee.isDigit {
        result &*= 10
        result &+= numericCast(pointer.pointee &- .zero)
        pointer += 1
    }
    return Double(result)
}

fileprivate func strtod(_ pointer: UnsafePointer<UInt8>, length: Int) -> Double {
    var pointer = pointer
    let endPointer = pointer + length
    var notAtEnd: Bool { pointer != endPointer }

    var result: Double
    var base = 0
    var sign: Double = 1

    switch pointer.pointee {
    case .minus:
        sign = -1
        pointer += 1
    case .plus:
        sign = 1
        pointer += 1
    default:
        ()
    }

    while notAtEnd, pointer.pointee.isDigit {
        base &*= 10
        base &+= numericCast(pointer.pointee &- .zero)
        pointer += 1
    }

    result = Double(base)

    guard notAtEnd else {
        return result * sign
    }

    if pointer.pointee == .fullStop {
        pointer += 1

        var fraction = 0
        var divisor = 1

        while notAtEnd, pointer.pointee.isDigit {
            fraction &*= 10
            fraction &+= numericCast(pointer.pointee &- .zero)
            divisor &*= 10
            pointer += 1
        }

        result += Double(fraction) / Double(divisor)

        guard notAtEnd else {
            return result * sign
        }
    }

    guard pointer.pointee == .e || pointer.pointee == .E else {
        return result * sign
    }

    pointer += 1
    var exponent = 0
    var exponentSign = 1

    switch pointer.pointee {
    case .minus:
        exponentSign = -1
        pointer += 1
    case .plus:
        exponentSign = 1
        pointer += 1
    default:
        ()
    }

    while notAtEnd, pointer.pointee.isDigit {
        exponent &*= 10
        exponent &+= numericCast(pointer.pointee &- .zero)
        pointer += 1
    }
    exponent *= exponentSign
    result *= pow(10, Double(exponent))

    return result * sign
}
