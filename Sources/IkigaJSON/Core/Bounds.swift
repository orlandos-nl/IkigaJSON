import Foundation

fileprivate let lowercasedRadix16table: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]
fileprivate let uppercasedRadix16table: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46]

fileprivate extension UInt8 {
    func decodeHex() -> UInt8? {
        if let num = lowercasedRadix16table.index(of: self) {
            return numericCast(num)
        } else if let num = uppercasedRadix16table.index(of: self) {
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
            // JSON strings are surrounded by `""`
            var length = Int(self.length) - 2
            var i = 1
            
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
        func fallback() -> Double? {
            let data = Data(bytes: pointer + offset, count: length)
            
            if let string = String(data: data, encoding: .utf8) {
                return Double(string)
            }
            
            return nil
        }
        
        /// If the number is not floating, an integer will be instantiated and converted
        if !floating {
            guard let int = makeInt(from: pointer) else {
                return nil
            }
            
            return Double(exactly: int)
        }
        
        let end = Int(self.offset) + Int(self.length)
        var exponentPow10 = 0
        var fullStop = false
        var hasExponent = false
        var exponentNegative = false
        var significand: Int = numericCast(pointer[offset] &- 0x30)
        var currentIndex = Int(self.offset &+ 1)
        
        /// Parses the decimal number
        loop: while currentIndex < end {
            let byte = pointer[currentIndex]
            if byte < 0x30 || byte > 0x39 {
                defer {
                    currentIndex = currentIndex &+ 1
                }
                
                if byte == .fullStop {
                    // Starting exponent
                    fullStop = true
                    continue loop
                } else if byte == .e || byte == .E {
                    hasExponent = true
                    continue loop
                } else {
                    break loop
                }
            }
            
            if hasExponent {
                if !exponentNegative {
                    if byte == .minus {
                        exponentNegative = true
                    } else if byte == .plus {
                        exponentNegative = false
                    } else {
                        exponentPow10 = exponentPow10 &- 1
                    }
                } else {
                    exponentPow10 = exponentPow10 &+ 1
                }
            } else if fullStop {
                exponentPow10 = exponentPow10 &- 1
            }
            
            significand = (significand &* 10) &+ numericCast(pointer[currentIndex] &- 0x30)
            currentIndex = currentIndex &+ 1
            
            if significand < 0 {
                return fallback()
            }
        }
        
        func makeExponent() -> Int {
            var base = 1
            
            if exponentPow10 < 0 {
                for _ in exponentPow10..<0 {
                    base = base &* 10
                }
                
                return -base
            } else if exponentPow10 > 0 {
                for _ in 0..<exponentPow10 {
                    base = base &* 10
                }
            }
            
            return base
        }
        
        // If the end of the double is reached
        if currentIndex >= end {
            let exponent = makeExponent()
            if let double = fastDouble(exponent: exponent, significand: Double(significand)) {
                return double
            }
            
            return fallback()
        }
        
        let e = pointer[currentIndex]
        
        // If this is not `e`-notated we're unsure what to expect so we trigger the fallback
        // This is necessary, since the end of the double has not been found
        guard e == .e || e == .E else {
            return fallback()
        }
        
        currentIndex = currentIndex &+ 1
        
        // Find the exponent's power
        guard let pow10exp = pointer.makeInt(offset: &currentIndex, length: end &- currentIndex) else {
            return fallback()
        }
        
        // Apply the exponent to the parsed number
        exponentPow10 = exponentPow10 &+ pow10exp
        let exponent = makeExponent()
        
        // Try the fast double instantiation route
        if let double = fastDouble(exponent: exponent, significand: Double(significand)) {
            return double
        }
        
        // Otherwise use the fallback implementation
        return fallback()
    }
    
    internal func makeInt(from pointer: UnsafePointer<UInt8>) -> Int? {
        var offset = Int(self.offset)
        
        return pointer.makeInt(offset: &offset, length: Int(length))
    }
}

// FIXME: Test, probably broken still
fileprivate func decodeUnicode(from data: inout Data, offset: Int, length: inout Int) {
    var offset = offset
    
    return data.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) in
        let bytes = bytes.advanced(by: offset)
        
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
