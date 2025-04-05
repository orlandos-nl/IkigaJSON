import NIOCore

extension ByteBuffer {
    func withBytePointer<T>(_ run: (UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        return try withUnsafeReadableBytes { buffer in
            let buffer = buffer.bindMemory(to: UInt8.self)
            return try run(buffer.baseAddress!)
        }
    }
}
