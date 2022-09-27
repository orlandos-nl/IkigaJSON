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
        if let data = makeStringData(from: pointer, escaping: escaping, unicode: unicode) {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Makes a `Data` blob from a pointer. This data can be used to initialize a string or for comparison operations.
    /// Assumes the length is checked against the bounds `self`
    ///
    /// If `escaping` is false, the string is assumed unescaped and no additional effort will be put
    /// towards unescaping.
    func makeStringData(from pointer: UnsafePointer<UInt8>, escaping: Bool, unicode: Bool) -> Data? {
        var data = Data(bytes: pointer + Int(offset), count: Int(length))
        
        // If we can't take a shortcut by decoding immediately thanks to an escaping character
        if escaping || unicode {
            var length = Int(self.length)
            var i = 0
            
            next: while i < length {
                defer {
                    i = i &+ 1
                }
                
                let byte = data[i]
                
                unescape: if escaping {
                    // If this character is not a baskslash or this was the last character
                    // We don't need to unescape the next character
                    if byte != .backslash || i &+ 1 >= length {
                        break unescape
                    }
                    
                    // Remove the backslash and translate the next character
                    data.remove(at: i)
                    length = length &- 1
                    
                    switch data[i] {
                    case .backslash, .solidus, .quote:
                        continue next // just removal needed
                    case .u:
                        // `\u` indicates a unicode character
                        data.remove(at: i)
                        length = length &- 1
                        decodeUnicode(from: &data, offset: i, length: &length)
                    case .t:
                        data[i] = .tab
                    case .r:
                        data[i] = .carriageReturn
                    case .n:
                        data[i] = .newLine
                    case .f: // form feed, will just be passed on
                        return nil
                    case .b: // backspace, will just be passed on
                        return nil
                    default:
                        // Try unicode decoding
                        break unescape
                    }
                    
                    continue next
                }
            }
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
    internal func makeDouble(from pointer: UnsafePointer<UInt8>, floating: Bool) -> Double? {
        let offset = Int(self.offset)
        let length = Int(self.length)
        /// Falls back to the foundation implementation which makes too many copies for this use case
        ///
        /// Used when the implementation is unsure
        let slice = UnsafeBufferPointer(start: pointer + offset, count: length)
        if let string = String(bytes: slice, encoding: .utf8) {
            return Double(string)
        }
        
        return nil
    }
    
    internal func makeInt(from pointer: UnsafePointer<UInt8>) -> Int? {
        var offset = Int(self.offset)
        
        return pointer.makeInt(offset: &offset, length: Int(length))
    }
}

// FIXME: Test, probably broken still
fileprivate func decodeUnicode(from data: inout Data, offset: Int, length: inout Int) {
    var offset = offset
    
    return data.withUnsafeMutableBytes { buffer in
        let bytes = buffer.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset)
        
        while offset < length {
            guard let base = bytes[offset].decodeHex(), let secondHex = bytes[offset &+ 1].decodeHex() else {
                return
            }
            
            bytes.pointee = (base << 4) &+ secondHex
            length = length &- 1
            offset = offset &+ 2
        }
    }
}
