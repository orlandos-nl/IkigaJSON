/// Fast byte scanning utilities using SWAR (SIMD Within A Register) techniques.
/// These operate on 64-bit words to scan 8 bytes at a time without needing actual SIMD instructions.

/// Find the first occurrence of a byte in a buffer, starting from offset.
/// Returns the index of the byte, or nil if not found.
@inlinable
public func findByte(_ target: UInt8, in buffer: UnsafeBufferPointer<UInt8>, from offset: Int) -> Int? {
  let count = buffer.count
  guard offset < count else { return nil }

  let baseAddress = buffer.baseAddress!
  var i = offset

  // Process 8 bytes at a time using SWAR
  let target64 = UInt64(target) &* 0x0101010101010101

  // Align to 8-byte boundary first (process leading bytes one by one)
  let alignedStart = (i + 7) & ~7
  while i < min(alignedStart, count) {
    if baseAddress[i] == target {
      return i
    }
    i &+= 1
  }

  // Process 8 bytes at a time
  while i &+ 8 <= count {
    let word = baseAddress.advanced(by: i).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }

    // XOR with target broadcast to all bytes - matching bytes become 0x00
    let xored = word ^ target64

    // Use the hasZeroByte trick: (v - 0x0101...) & ~v & 0x8080...
    // This sets the high bit of any byte that was 0x00
    let hasZero = (xored &- 0x0101010101010101) & ~xored & 0x8080808080808080

    if hasZero != 0 {
      // Found a match - find which byte
      // Count trailing zeros / 8 gives us the byte index (on little-endian)
      let byteIndex = hasZero.trailingZeroBitCount / 8
      return i &+ byteIndex
    }
    i &+= 8
  }

  // Process remaining bytes
  while i < count {
    if baseAddress[i] == target {
      return i
    }
    i &+= 1
  }

  return nil
}

/// Find the first occurrence of either of two bytes in a buffer.
/// Returns the index of the first match, or nil if neither found.
@inlinable
public func findEitherByte(_ target1: UInt8, _ target2: UInt8, in buffer: UnsafeBufferPointer<UInt8>, from offset: Int) -> Int? {
  let count = buffer.count
  guard offset < count else { return nil }

  let baseAddress = buffer.baseAddress!
  var i = offset

  // Broadcast targets to all bytes in 64-bit words
  let t1_64 = UInt64(target1) &* 0x0101010101010101
  let t2_64 = UInt64(target2) &* 0x0101010101010101

  // Align to 8-byte boundary
  let alignedStart = (i + 7) & ~7
  while i < min(alignedStart, count) {
    let byte = baseAddress[i]
    if byte == target1 || byte == target2 {
      return i
    }
    i &+= 1
  }

  // Process 8 bytes at a time
  while i &+ 8 <= count {
    let word = baseAddress.advanced(by: i).withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }

    // Check for target1
    let xored1 = word ^ t1_64
    let hasZero1 = (xored1 &- 0x0101010101010101) & ~xored1 & 0x8080808080808080

    // Check for target2
    let xored2 = word ^ t2_64
    let hasZero2 = (xored2 &- 0x0101010101010101) & ~xored2 & 0x8080808080808080

    let combined = hasZero1 | hasZero2

    if combined != 0 {
      // Found a match - find which byte (first one in memory order)
      let byteIndex = combined.trailingZeroBitCount / 8
      return i &+ byteIndex
    }
    i &+= 8
  }

  // Process remaining bytes
  while i < count {
    let byte = baseAddress[i]
    if byte == target1 || byte == target2 {
      return i
    }
    i &+= 1
  }

  return nil
}

/// Count leading whitespace bytes (space, tab, CR, LF) starting from offset.
/// Returns the number of whitespace bytes found.
@inlinable
public func countLeadingWhitespace(in buffer: UnsafeBufferPointer<UInt8>, from offset: Int) -> Int {
  let count = buffer.count
  guard offset < count else { return 0 }

  let baseAddress = buffer.baseAddress!
  var i = offset

  // Process bytes until we hit non-whitespace
  // For whitespace, the common cases are: space (0x20), tab (0x09), LF (0x0A), CR (0x0D)
  // We can use a lookup table approach or check individually

  // Align to 8-byte boundary first
  let alignedStart = (i + 7) & ~7
  while i < min(alignedStart, count) {
    let byte = baseAddress[i]
    if byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
      return i - offset
    }
    i &+= 1
  }

  // For whitespace we need a different approach since we're checking multiple values
  // Use SWAR to check if all bytes in a word are whitespace
  // A byte is whitespace if it's <= 0x20 AND (byte == 0x20 OR byte <= 0x0D)
  // Simplified: check if byte is in {0x09, 0x0A, 0x0D, 0x20}

  // Process 8 bytes at a time with individual checks (still faster due to better memory access)
  while i &+ 8 <= count {
    // Check if any of the 8 bytes is non-whitespace
    var foundNonWhitespace = false
    for j in 0..<8 {
      let byte = baseAddress[i &+ j]
      if byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
        return (i &+ j) - offset
      }
    }
    i &+= 8
  }

  // Process remaining bytes
  while i < count {
    let byte = baseAddress[i]
    if byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
      return i - offset
    }
    i &+= 1
  }

  return count - offset
}
