enum Constants {
  /// Type byte + JSON location + JSON length + pair count + totalIndexLength
  ///
  /// Pair count is * 2 for objects since a pair is a key and a value
  /// Pair count is * 1 for arrays since a pair is only a value
  ///
  /// The total index length is the length of all child indexes combined
  ///
  /// typeByte + Int + Int + PairCount + TotalIndexLength
  @usableFromInline
  static let arrayObjectIndexLength = 17

  /// Type byte + JSON location + JSON length
  ///
  /// typeByte + Int + Int
  @usableFromInline
  static let stringNumberIndexLength = 9

  /// Type byte + JSON location
  ///
  /// typeByte + Int
  @usableFromInline
  static let boolNullIndexLength = 5

  /// When parsing an index from it's Int, this is where you'll find a Int
  @usableFromInline
  static let jsonLocationOffset = 1

  /// When parsing an index from it's Int, this is where you'll find a Int if present
  @usableFromInline
  static let jsonLengthOffset = 5

  /// When parsing an index from it's Int, this is where you'll find the pair count if present
  @usableFromInline
  static let arrayObjectPairCountOffset = 9

  /// When parsing an index from it's Int, this is where you'll find the totalIndexLength if present
  @usableFromInline
  static let arrayObjectTotalIndexLengthOffset = 13

  @usableFromInline
  static let firstArrayObjectChildOffset = 17
}
