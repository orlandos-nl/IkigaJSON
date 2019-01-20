import Foundation
import Darwin

internal final class Buffer {
    internal private(set) var pointer: UnsafeMutableRawPointer
    internal private(set) var size: Int
    internal var used: Int
    
    var copy: Buffer {
        return Buffer(copying: self)
    }
    
    static func allocate(size: Int) -> Buffer {
        return Buffer(allocating: size)
    }
    
    init(allocating size: Int) {
        self.pointer = .allocate(byteCount: size, alignment: 1)
        self.size = size
        self.used = 0
    }
    
    init(copying data: Data) {
        let size = data.count
        pointer = .allocate(byteCount: size, alignment: 1)
        
        let writePointer = pointer.bindMemory(to: UInt8.self, capacity: size)
        
        data.withUnsafeBytes { (readPointer: UnsafePointer<UInt8>) in
            writePointer.initialize(from: readPointer, count: size)
        }
        
        self.size = size
        self.used = size
    }
    
    init(copying buffer: Buffer) {
        let size = buffer.size
        pointer = .allocate(byteCount: size, alignment: 1)
        
        let writePointer = pointer.bindMemory(to: UInt8.self, capacity: size)
        writePointer.initialize(
            from: buffer.pointer.bindMemory(to: UInt8.self, capacity: size),
            count: size
        )
        
        self.size = size
        self.used = size
    }
    
    func expandBuffer(to size: Int) {
        pointer = realloc(pointer, size)
        self.size = size
    }
    
    func initialize(atOffset offset: Int, from bytes: UnsafePointer<UInt8>, length: Int) {
        (pointer + offset).bindMemory(to: UInt8.self, capacity: length).initialize(from: bytes, count: length)
    }
    
    deinit { pointer.deallocate() }
}
