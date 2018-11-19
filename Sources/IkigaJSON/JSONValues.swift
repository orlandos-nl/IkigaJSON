import Foundation

fileprivate let lowercasedRadix16table: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66]
fileprivate let uppercasedRadix16table: [UInt8] = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46]

extension UInt8 {
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
    let offset: Int
    let length: Int
    
    func makeString(from pointer: UnsafePointer<UInt8>, escaping: Bool, unicode: Bool) -> String? {
        var data = Data(bytes: pointer + offset, count: length)
        
        // If we can't take a shortcut by decoding immediately thanks to an escaping character
        if escaping || unicode {
            var length = self.length
            var i = 0
            
            next: while i < length {
                defer {
                    i = i &+ 1
                }
                
                let byte = data[i]
                
                unescape: if escaping {
                    if byte != .backslash || i &+ 1 >= length {
                        break unescape
                    }
                    
                    data.remove(at: i)
                    length = length &- 1
                    
                    switch data[i] {
                    case .backslash, .solidus, .quote:
                        continue next // just removal needed
                    case .u:
                        data.remove(at: i)
                        length = length &- 1
                        decodeUnicode(from: &data, offset: i, length: &length)
                    case .t:
                        data[i] = .tab
                    case .r:
                        data[i] = .carriageReturn
                    case .n:
                        data[i] = .newLine
                    case .f: // form feed, unsupported
                        return nil
                    case .b: // backspace, unsupported
                        return nil
                    default:
                        // Try unicode decoding
                        break unescape
                    }
                    
                    continue next
                }
            }
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    internal func makeDouble(from pointer: UnsafePointer<UInt8>, floating: Bool) -> Double? {
        func fallback() -> Double? {
            let data = Data(bytes: pointer + self.offset, count: length)
            
            if let string = String(data: data, encoding: .utf8) {
                return Double(string)
            }
            
            return nil
        }
        
        var offset = self.offset
        
        if !floating {
            guard let int = makeInt(from: pointer) else {
                return nil
            }
            
            return Double(exactly: int)
        }
        
        let end = offset &+ length
        var exponentPow10 = 0
        var fullStop = false
        var significand: Int = numericCast(pointer[offset] &- 0x30)
        offset = offset &+ 1
        
        loop: while offset < end {
            let byte = pointer[offset]
            if byte < 0x30 || byte > 0x39 {
                if byte == .fullStop {
                    // Starting exponent
                    fullStop = true
                    offset = offset &+ 1
                    continue loop
                } else if byte == .e || byte == .E {
                    exponentPow10 = exponentPow10 &- 1
                }
                
                break loop
            }
            
            if fullStop {
                exponentPow10 = exponentPow10 &- 1
            }
            
            significand = (significand &* 10) &+ numericCast(pointer[offset] &- 0x30)
            offset = offset &+ 1
            
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
        
        // end of double
        if offset >= end {
            let exponent = makeExponent()
            if let double = fastDouble(exponent: exponent, significand: Double(significand)) {
                return double
            }
            
            return fallback()
        }
        
        let e = pointer[offset]
        
        guard e == .e || e == .E else {
            return fallback()
        }
        
        offset = offset &+ 1
        
        guard let pow10exp = pointer.makeInt(offset: &offset, length: end &- offset) else {
            return fallback()
        }
        
        exponentPow10 = exponentPow10 &+ pow10exp
        let exponent = makeExponent()
        
        if let double = fastDouble(exponent: exponent, significand: Double(significand)) {
            return double
        }
        
        return fallback()
    }
    
    internal func makeInt(from pointer: UnsafePointer<UInt8>) -> Int? {
        var offset = self.offset
        
        return pointer.makeInt(offset: &offset, length: length)
    }
}

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
