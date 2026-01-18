extension UInt8 {
  @usableFromInline static let backspace: UInt8 = 0x08
  @usableFromInline static let tab: UInt8 = 0x09
  @usableFromInline static let newLine: UInt8 = 0x0a
  @usableFromInline static let formFeed: UInt8 = 0x0c
  @usableFromInline static let carriageReturn: UInt8 = 0x0d
  @usableFromInline static let space: UInt8 = 0x20
  @usableFromInline static let quote: UInt8 = 0x22
  @usableFromInline static let plus: UInt8 = 0x2b
  @usableFromInline static let comma: UInt8 = 0x2c
  @usableFromInline static let minus: UInt8 = 0x2d
  @usableFromInline static let fullStop: UInt8 = 0x2e
  @usableFromInline static let solidus: UInt8 = 0x2f
  @usableFromInline static let zero: UInt8 = 0x30
  @usableFromInline static let nine: UInt8 = 0x39
  @usableFromInline static let colon: UInt8 = 0x3a
  @usableFromInline static let E: UInt8 = 0x45
  @usableFromInline static let underscore: UInt8 = 0x5f
  @usableFromInline static let A: UInt8 = 0x41
  @usableFromInline static let Z: UInt8 = 0x5a
  @usableFromInline static let a: UInt8 = 0x61
  @usableFromInline static let b: UInt8 = 0x62
  @usableFromInline static let e: UInt8 = 0x65
  @usableFromInline static let f: UInt8 = 0x66
  @usableFromInline static let l: UInt8 = 0x6c
  @usableFromInline static let n: UInt8 = 0x6e
  @usableFromInline static let r: UInt8 = 0x72
  @usableFromInline static let s: UInt8 = 0x73
  @usableFromInline static let t: UInt8 = 0x74
  @usableFromInline static let u: UInt8 = 0x75
  @usableFromInline static let z: UInt8 = 0x7a
  @usableFromInline static let squareLeft: UInt8 = 0x5b
  @usableFromInline static let backslash: UInt8 = 0x5c
  @usableFromInline static let squareRight: UInt8 = 0x5d
  @usableFromInline static let curlyLeft: UInt8 = 0x7b
  @usableFromInline static let curlyRight: UInt8 = 0x7d

  @usableFromInline
  var isDigit: Bool {
    self >= .zero && self <= .nine
  }
}
