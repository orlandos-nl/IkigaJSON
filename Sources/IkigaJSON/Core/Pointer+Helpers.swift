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

extension ByteBuffer {
    func withBytePointer<T>(_ run: (UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        return try withUnsafeReadableBytes { buffer in
            let buffer = buffer.bindMemory(to: UInt8.self)
            return try run(buffer.baseAddress!)
        }
    }
}

internal let allocator = ByteBufferAllocator()

internal extension UInt8 {
    static let backspace: UInt8 = 0x08
    static let tab: UInt8 = 0x09
    static let newLine: UInt8 = 0x0a
    static let formFeed: UInt8 = 0x0c
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
    static let A: UInt8 = 0x41
    static let Z: UInt8 = 0x5a
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

    @usableFromInline
    var isDigit: Bool {
        self >= .zero && self <= .nine
    }
}
