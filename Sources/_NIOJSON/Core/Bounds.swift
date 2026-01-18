import Foundation
import _JSONCore

private let lowercasedRadix16table: [UInt8] = [
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
]
private let uppercasedRadix16table: [UInt8] = [
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
]

extension UInt8 {
  fileprivate func decodeHex() -> UInt8? {
    if let num = lowercasedRadix16table.firstIndex(of: self) {
      return numericCast(num)
    } else if let num = uppercasedRadix16table.firstIndex(of: self) {
      return numericCast(num)
    } else {
      return nil
    }
  }
}

// MARK: - Span-based String Parsing

extension JSONToken.String {
  /// Makes a String from a Span.
  /// Assumes the length is checked against the bounds `self`
  func makeString(from span: Span<UInt8>, unicode: Bool) -> String? {
    let startOffset = start.byteOffset

    if usesEscaping {
      // Process escaped string
      var buffer = [UInt8]()
      buffer.reserveCapacity(byteLength)

      var readerIndex = 0
      var unicodes = [UInt16]()

      func flushUnicodes() {
        if !unicodes.isEmpty {
          // Convert UTF-16 code units to a String, then append its UTF-8 bytes
          let character = String(decoding: unicodes, as: Unicode.UTF16.self)
          buffer.append(contentsOf: character.utf8)
          unicodes.removeAll(keepingCapacity: true)
        }
      }

      next: while readerIndex < byteLength {
        let byte = span[startOffset + readerIndex]

        if byte != .backslash || readerIndex + 1 >= byteLength {
          flushUnicodes()
          buffer.append(byte)
          readerIndex += 1
          continue next
        }

        readerIndex += 1

        if span[startOffset + readerIndex] == .u {
          readerIndex += 1
          guard readerIndex + 3 < byteLength else {
            return nil
          }
          guard
            let hex0 = span[startOffset + readerIndex].decodeHex(),
            let hex1 = span[startOffset + readerIndex + 1].decodeHex(),
            let hex2 = span[startOffset + readerIndex + 2].decodeHex(),
            let hex3 = span[startOffset + readerIndex + 3].decodeHex()
          else {
            return nil
          }

          var unicodeValue: UInt16 = 0
          unicodeValue &+= UInt16(hex0) &<< 12
          unicodeValue &+= UInt16(hex1) &<< 8
          unicodeValue &+= UInt16(hex2) &<< 4
          unicodeValue &+= UInt16(hex3)

          unicodes.append(unicodeValue)
          readerIndex += 4
          continue next
        }

        flushUnicodes()

        switch span[startOffset + readerIndex] {
        case .backslash, .solidus, .quote:
          buffer.append(span[startOffset + readerIndex])
          readerIndex += 1
        case .t:
          buffer.append(.tab)
          readerIndex += 1
        case .r:
          buffer.append(.carriageReturn)
          readerIndex += 1
        case .n:
          buffer.append(.newLine)
          readerIndex += 1
        case .f:
          buffer.append(.formFeed)
          readerIndex += 1
        case .b:
          buffer.append(.backspace)
          readerIndex += 1
        default:
          return nil
        }
      }

      flushUnicodes()
      return String(decoding: buffer, as: Unicode.UTF8.self)
    } else {
      // No escaping, use withUnsafeBufferPointer for efficient string creation
      return unsafe span.withUnsafeBytes { buffer in
        let slice = unsafe UnsafeRawBufferPointer(rebasing: buffer[startOffset..<(startOffset + byteLength)])
        return String(decoding: slice, as: Unicode.UTF8.self)
      }
    }
  }
}

// MARK: - Array-based String Parsing

extension JSONToken.String {
  /// Makes a String from an Array.
  /// Assumes the length is checked against the bounds `self`
  func makeString(from bytes: [UInt8], unicode: Bool) -> String? {
    let startOffset = start.byteOffset

    if usesEscaping {
      // Process escaped string
      var buffer = [UInt8]()
      buffer.reserveCapacity(byteLength)

      var readerIndex = 0
      var unicodes = [UInt16]()

      func flushUnicodes() {
        if !unicodes.isEmpty {
          // Convert UTF-16 code units to a String, then append its UTF-8 bytes
          let character = String(decoding: unicodes, as: Unicode.UTF16.self)
          buffer.append(contentsOf: character.utf8)
          unicodes.removeAll(keepingCapacity: true)
        }
      }

      next: while readerIndex < byteLength {
        let byte = bytes[startOffset + readerIndex]

        if byte != .backslash || readerIndex + 1 >= byteLength {
          flushUnicodes()
          buffer.append(byte)
          readerIndex += 1
          continue next
        }

        readerIndex += 1

        if bytes[startOffset + readerIndex] == .u {
          readerIndex += 1
          guard readerIndex + 3 < byteLength else {
            return nil
          }
          guard
            let hex0 = bytes[startOffset + readerIndex].decodeHex(),
            let hex1 = bytes[startOffset + readerIndex + 1].decodeHex(),
            let hex2 = bytes[startOffset + readerIndex + 2].decodeHex(),
            let hex3 = bytes[startOffset + readerIndex + 3].decodeHex()
          else {
            return nil
          }

          var unicodeValue: UInt16 = 0
          unicodeValue &+= UInt16(hex0) &<< 12
          unicodeValue &+= UInt16(hex1) &<< 8
          unicodeValue &+= UInt16(hex2) &<< 4
          unicodeValue &+= UInt16(hex3)

          unicodes.append(unicodeValue)
          readerIndex += 4
          continue next
        }

        flushUnicodes()

        switch bytes[startOffset + readerIndex] {
        case .backslash, .solidus, .quote:
          buffer.append(bytes[startOffset + readerIndex])
          readerIndex += 1
        case .t:
          buffer.append(.tab)
          readerIndex += 1
        case .r:
          buffer.append(.carriageReturn)
          readerIndex += 1
        case .n:
          buffer.append(.newLine)
          readerIndex += 1
        case .f:
          buffer.append(.formFeed)
          readerIndex += 1
        case .b:
          buffer.append(.backspace)
          readerIndex += 1
        default:
          return nil
        }
      }

      flushUnicodes()
      return String(decoding: buffer, as: Unicode.UTF8.self)
    } else {
      // No escaping, use slice for efficient string creation
      let slice = bytes[startOffset..<(startOffset + byteLength)]
      return String(decoding: slice, as: Unicode.UTF8.self)
    }
  }
}

// MARK: - Span-based Number Parsing

extension JSONToken.Number {
  /// Parses a `Double` from a Span
  /// Assumes the length is checked against the bounds `self`
  internal func makeDouble(from span: Span<UInt8>) -> Double {
    if isInteger {
      return strtoiSpan(span, start: start.byteOffset, length: byteLength)
    } else {
      return strtodSpan(span, start: start.byteOffset, length: byteLength)
    }
  }

  internal func makeInt(from span: Span<UInt8>) -> Int? {
    var offset = start.byteOffset
    return span.makeInt(offset: &offset, length: Int(byteLength))
  }

  /// Parses a `Double` from an Array
  /// Assumes the length is checked against the bounds `self`
  internal func makeDouble(from bytes: [UInt8]) -> Double {
    if isInteger {
      return strtoiArray(bytes, start: start.byteOffset, length: byteLength)
    } else {
      return strtodArray(bytes, start: start.byteOffset, length: byteLength)
    }
  }

  internal func makeInt(from bytes: [UInt8]) -> Int? {
    var offset = start.byteOffset
    return bytes.makeInt(offset: &offset, length: Int(byteLength))
  }
}

public struct UTF8ParsingError: Error {}

// MARK: - Span-based strtoi/strtod

private func strtoiSpan(_ span: Span<UInt8>, start: Int, length: Int) -> Double {
  var offset = start
  let endOffset = start + length

  var result = 0
  while offset < endOffset, span[offset].isDigit {
    result &*= 10
    result &+= numericCast(span[offset] &- .zero)
    offset += 1
  }
  return Double(result)
}

private func strtodSpan(_ span: Span<UInt8>, start: Int, length: Int) -> Double {
  var offset = start
  let endOffset = start + length
  var notAtEnd: Bool { offset < endOffset }

  var result: Double
  var base = 0
  var sign: Double = 1

  switch span[offset] {
  case .minus:
    sign = -1
    offset += 1
  case .plus:
    sign = 1
    offset += 1
  default:
    ()
  }

  while notAtEnd, span[offset].isDigit {
    base &*= 10
    base &+= numericCast(span[offset] &- .zero)
    offset += 1
  }

  result = Double(base)

  guard notAtEnd else {
    return result * sign
  }

  if span[offset] == .fullStop {
    offset += 1

    var fraction = 0
    var divisor = 1

    while notAtEnd, span[offset].isDigit {
      fraction &*= 10
      fraction &+= numericCast(span[offset] &- .zero)
      divisor &*= 10
      offset += 1
    }

    result += Double(fraction) / Double(divisor)

    guard notAtEnd else {
      return result * sign
    }
  }

  guard span[offset] == .e || span[offset] == .E else {
    return result * sign
  }

  offset += 1
  var exponent = 0
  var exponentSign = 1

  guard notAtEnd else {
    return result * sign
  }

  switch span[offset] {
  case .minus:
    exponentSign = -1
    offset += 1
  case .plus:
    exponentSign = 1
    offset += 1
  default:
    ()
  }

  while notAtEnd, span[offset].isDigit {
    exponent &*= 10
    exponent &+= numericCast(span[offset] &- .zero)
    offset += 1
  }
  exponent *= exponentSign
  result *= pow(10, Double(exponent))

  return result * sign
}

// MARK: - Array-based strtoi/strtod

private func strtoiArray(_ bytes: [UInt8], start: Int, length: Int) -> Double {
  var offset = start
  let endOffset = start + length

  var result = 0
  while offset < endOffset, bytes[offset].isDigit {
    result &*= 10
    result &+= numericCast(bytes[offset] &- .zero)
    offset += 1
  }
  return Double(result)
}

private func strtodArray(_ bytes: [UInt8], start: Int, length: Int) -> Double {
  var offset = start
  let endOffset = start + length
  var notAtEnd: Bool { offset < endOffset }

  var result: Double
  var base = 0
  var sign: Double = 1

  switch bytes[offset] {
  case .minus:
    sign = -1
    offset += 1
  case .plus:
    sign = 1
    offset += 1
  default:
    ()
  }

  while notAtEnd, bytes[offset].isDigit {
    base &*= 10
    base &+= numericCast(bytes[offset] &- .zero)
    offset += 1
  }

  result = Double(base)

  guard notAtEnd else {
    return result * sign
  }

  if bytes[offset] == .fullStop {
    offset += 1

    var fraction = 0
    var divisor = 1

    while notAtEnd, bytes[offset].isDigit {
      fraction &*= 10
      fraction &+= numericCast(bytes[offset] &- .zero)
      divisor &*= 10
      offset += 1
    }

    result += Double(fraction) / Double(divisor)

    guard notAtEnd else {
      return result * sign
    }
  }

  guard bytes[offset] == .e || bytes[offset] == .E else {
    return result * sign
  }

  offset += 1
  var exponent = 0
  var exponentSign = 1

  guard notAtEnd else {
    return result * sign
  }

  switch bytes[offset] {
  case .minus:
    exponentSign = -1
    offset += 1
  case .plus:
    exponentSign = 1
    offset += 1
  default:
    ()
  }

  while notAtEnd, bytes[offset].isDigit {
    exponent &*= 10
    exponent &+= numericCast(bytes[offset] &- .zero)
    offset += 1
  }
  exponent *= exponentSign
  result *= pow(10, Double(exponent))

  return result * sign
}

// MARK: - Array-based makeInt

extension Array where Element == UInt8 {
  func makeInt(offset: inout Int, length: Int) -> Int? {
    guard offset < count else { return nil }

    let negative = self[offset] == .minus
    if negative {
      // skip 1 byte for the minus
      offset = offset &+ 1
    }

    let end = Swift.min(offset &+ length, count)
    guard offset < end else { return nil }

    var number: Int = numericCast(self[offset] &- 0x30)
    offset = offset &+ 1

    while offset < end {
      let byte = self[offset]
      if byte < 0x30 || byte > 0x39 {
        return negative ? -number : number
      }

      number = (number &* 10) &+ numericCast(self[offset] &- 0x30)
      offset = offset &+ 1

      if number < 0 {
        return nil
      }
    }

    return negative ? -number : number
  }
}
