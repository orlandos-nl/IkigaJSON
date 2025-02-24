extension UInt8 {
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
