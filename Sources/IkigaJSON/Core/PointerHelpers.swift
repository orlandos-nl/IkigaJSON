#if swift(<5.8)
extension UnsafeMutablePointer {
  func update(from source: UnsafePointer<Pointee>, count: Int) {
    self.update(from: source, count: count)
  }
}
#endif
