public enum JSONDecoderError: Error {
  case expectedArray
  case expectedObject
  case decodingError(expected: Any.Type, keyPath: [any CodingKey])
  case unknownJSONStrategy
  case missingKeyedContainer
  case missingUnkeyedContainer
  case missingSuperDecoder
  case endOfArray
  case invalidDate(String?)
  case invalidData(String?)
  case invalidURL(String)
  case invalidDecimal(String)
}
