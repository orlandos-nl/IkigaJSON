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

internal struct Bounds {
    var offset: Int32
    var length: Int32
    
    //// Makes a String from a pointer.
    /// Assumes the length is checked against the bounds `self`
    ///
    /// - see: `makeStringFromData` for more information
    func makeString(from pointer: UnsafePointer<UInt8>, escaping: Bool, unicode: Bool) -> String? {
        if let data = try? makeStringData(from: pointer, escaping: escaping, unicode: unicode) {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Makes a `Data` blob from a pointer. This data can be used to initialize a string or for comparison operations.
    /// Assumes the length is checked against the bounds `self`
    ///
    /// If `escaping` is false, the string is assumed unescaped and no additional effort will be put
    /// towards unescaping.
    func makeStringData(from pointer: UnsafePointer<UInt8>, escaping: Bool, unicode: Bool) throws -> Data? {
        var data = Data(bytes: pointer + Int(offset), count: Int(length))
        
        // If we can't take a shortcut by decoding immediately thanks to an escaping character
        if escaping || unicode {
            var i = 0
            var unicodes = [UInt16]()

            func flushUnicodes() {
                if !unicodes.isEmpty {
                    let character = String(utf16CodeUnits: unicodes, count: unicodes.count)
                    data.insert(contentsOf: character.utf8, at: i)
                    unicodes.removeAll(keepingCapacity: true)
                }
            }
            
            next: while i < data.count {
                let byte = data[i]
                
                unescape: if escaping {
                    // If this character is not a baskslash or this was the last character
                    // We don't need to unescape the next character
                    if byte != .backslash || i &+ 1 >= length {
                        // Flush unprocessed unicodes and move past this character
                        flushUnicodes()
                        i = i &+ 1
                        break unescape
                    }
                    
                    // Remove the backslash and translate the next character
                    data.remove(at: i)
                    
                    switch data[i] {
                    case .backslash, .solidus, .quote:
                        // just removal needed
                        flushUnicodes()

                        // Move past this character
                        i = i &+ 1

                        continue next
                    case .u:
                        // `\u` indicates a unicode character
                        data.remove(at: i)
                        let unicode = try decodeUnicode(from: &data, offset: &i)
                        unicodes.append(unicode)

                        // Continue explicitly, so that we do not trigger the unicode 'flush' flow
                        continue next
                    case .t:
                        data[i] = .tab
                        // Move past this character
                        i = i &+ 1
                    case .r:
                        data[i] = .carriageReturn
                        // Move past this character
                        i = i &+ 1
                    case .n:
                        data[i] = .newLine
                        // Move past this character
                        i = i &+ 1
                    case .f:
                        data[i] = .formFeed
                        // Move past this character
                        i = i &+ 1
                    case .b:
                        data[i] = .backspace
                        // Move past this character
                        i = i &+ 1
                    default:
                        throw JSONParserError.unexpectedEscapingToken
                    }

                    // 'flush' the accumulated `unicodes` to the buffer
                    flushUnicodes()

                    continue next
                } else {
                    // End of unicodes, flush them
                    flushUnicodes()

                    // Move past this character
                    i = i &+ 1
                }
            }

            // End of string, flush unicode
            flushUnicodes()
        }

        return data
    }
    
    /// Parses a `Double` from the pointer
    /// Assumes the length is checked against the bounds `self`
    ///
    /// If `floating` is false, an integer is assumed to reduce parsing weight
    ///
    /// Uses the fast path for doubles if possible, when failing falls back to Foundation.
    ///
    /// https://www.exploringbinary.com/fast-path-decimal-to-floating-point-conversion/
    internal func makeDouble(from pointer: UnsafePointer<UInt8>, floating: Bool) -> Double {
        let offset = Int(self.offset)
        let length = Int(self.length)

        if floating {
            /// Falls back to the foundation implementation which makes too many copies for this use case
            ///
            /// Used when the implementation is unsure
            return strtod(pointer + offset, length: length)
        } else {
            return strtoi(pointer + offset, length: length)
        }
    }
    
    internal func makeInt(from pointer: UnsafePointer<UInt8>) -> Int? {
        var offset = Int(self.offset)
        
        return pointer.makeInt(offset: &offset, length: Int(length))
    }
}

struct UTF8ParsingError: Error {}

fileprivate func decodeUnicode(from data: inout Data, offset: inout Int) throws -> UInt16 {
    let hexCharacters = 4
    guard data.count - offset >= hexCharacters else {
        throw UTF8ParsingError()
    }

    guard
        let hex0 = data.remove(at: offset).decodeHex(),
        let hex1 = data.remove(at: offset).decodeHex(),
        let hex2 = data.remove(at: offset).decodeHex(),
        let hex3 = data.remove(at: offset).decodeHex()
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
