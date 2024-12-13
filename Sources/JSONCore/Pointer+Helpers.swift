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

package func fastDouble(exponent: Int, significand: Double) -> Double? {
    if exponent < -308 {
        return nil
    } else if exponent >= 0 {
        return significand * exponents[exponent]
    } else {
        return significand / exponents[-exponent]
    }
}

extension UnsafePointer<UInt8> {
    package func makeInt(offset: inout Int, length: Int) -> Int? {
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

extension UInt8 {
    package static let backspace: UInt8 = 0x08
    package static let tab: UInt8 = 0x09
    package static let newLine: UInt8 = 0x0a
    package static let formFeed: UInt8 = 0x0c
    package static let carriageReturn: UInt8 = 0x0d
    package static let space: UInt8 = 0x20
    package static let quote: UInt8 = 0x22
    package static let plus: UInt8 = 0x2b
    package static let comma: UInt8 = 0x2c
    package static let minus: UInt8 = 0x2d
    package static let fullStop: UInt8 = 0x2e
    package static let solidus: UInt8 = 0x2f
    package static let zero: UInt8 = 0x30
    package static let nine: UInt8 = 0x39
    package static let colon: UInt8 = 0x3a
    package static let E: UInt8 = 0x45
    package static let underscore: UInt8 = 0x5f
    package static let A: UInt8 = 0x41
    package static let Z: UInt8 = 0x5a
    package static let a: UInt8 = 0x61
    package static let b: UInt8 = 0x62
    package static let e: UInt8 = 0x65
    package static let f: UInt8 = 0x66
    package static let l: UInt8 = 0x6c
    package static let n: UInt8 = 0x6e
    package static let r: UInt8 = 0x72
    package static let s: UInt8 = 0x73
    package static let t: UInt8 = 0x74
    package static let u: UInt8 = 0x75
    package static let z: UInt8 = 0x7a
    package static let squareLeft: UInt8 = 0x5b
    package static let backslash: UInt8 = 0x5c
    package static let squareRight: UInt8 = 0x5d
    package static let curlyLeft: UInt8 = 0x7b
    package static let curlyRight: UInt8 = 0x7d

    @usableFromInline
    package var isDigit: Bool {
        self >= .zero && self <= .nine
    }
}
