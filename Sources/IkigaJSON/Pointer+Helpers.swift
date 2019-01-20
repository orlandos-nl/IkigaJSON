import NIO

// Lazily generate and load all exponents
// TODO: Compile time?
fileprivate let exponents: [Double] = {
    let base: Double = 1
    
    var exponents = [Double]()
    exponents.reserveCapacity(309)
    
    for i in 0..<309 {
        exponents.append(base * Double(i))
    }
    
    return exponents
}()

func fastDouble(exponent: Int, significand: Double) -> Double? {
    if exponent < -308 {
        return nil
    } else if exponent >= 0 {
        return significand * exponents[exponent]
    } else {
        return significand / exponents[-exponent]
    }
}

extension UnsafePointer where Pointee == UInt8 {
    func makeInt(offset: inout Int, length: Int) -> Int? {
        let negative = self[offset] == .minus
        if negative {
            // skip 1 byte for the minus
            offset = offset &+ 1
        }
        
        let end = offset &+ length
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

internal let allocator = ByteBufferAllocator()

extension UnsafeRawPointer {
    var uint8: UnsafePointer<UInt8> {
        return self.assumingMemoryBound(to: UInt8.self)
    }
    
    var int32: UnsafePointer<Int32> {
        return self.assumingMemoryBound(to: Int32.self)
    }
}

extension UnsafeMutableRawPointer {
    var uint8: UnsafeMutablePointer<UInt8> {
        return self.assumingMemoryBound(to: UInt8.self)
    }
    
    var int32: UnsafeMutablePointer<Int32> {
        return self.assumingMemoryBound(to: Int32.self)
    }
}

extension UnsafePointer where Pointee: Equatable {
    func peek(for element: Pointee, from baseIndex: Int = 0, untilIndex index: Int) -> Int? {
        var i = baseIndex
        
        while i < index {
            if self[i] == element {
                return i
            }
            
            i = i &+ 1
        }
        
        return nil
    }
}

internal extension UInt8 {
    static let tab: UInt8 = 0x09
    static let newLine: UInt8 = 0x0a
    static let carriageReturn: UInt8 = 0x0d
    static let space: UInt8 = 0x20
    static let quote: UInt8 = 0x22
    static let plus: UInt8 = 0x2b
    static let comma: UInt8 = 0x2c
    static let minus: UInt8 = 0x2d
    static let fullStop: UInt8 = 0x2e
    static let solidus: UInt8 = 0x2f
    static let zero: UInt8 = 0x30
    static let nine: UInt8 = 0x39
    static let colon: UInt8 = 0x3a
    static let E: UInt8 = 0x45
    static let underscore: UInt8 = 0x5f
    static let a: UInt8 = 0x61
    static let b: UInt8 = 0x62
    static let e: UInt8 = 0x65
    static let f: UInt8 = 0x66
    static let l: UInt8 = 0x6c
    static let n: UInt8 = 0x6e
    static let r: UInt8 = 0x72
    static let s: UInt8 = 0x73
    static let t: UInt8 = 0x74
    static let u: UInt8 = 0x75
    static let z: UInt8 = 0x7a
    static let squareLeft: UInt8 = 0x5b
    static let backslash: UInt8 = 0x5c
    static let squareRight: UInt8 = 0x5d
    static let curlyLeft: UInt8 = 0x7b
    static let curlyRight: UInt8 = 0x7d
}
