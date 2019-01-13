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
    
    func prepareRewrite(offset: Int, oldSize: Int, newSize: Int) {
        // `if newSize == 5 && oldSize == 3` then We need to write over 0..<5
        // Meaning we move the rest back by (5 - 3 = 2)
        
        // Or if `newSize == 3 && oldSize == 5` we write over 0..<3 and move forward by 2 (or -2 offset)
        let diff = newSize - oldSize
        
        if diff == 0 { return }
        
        if used + diff > used {
            expandBuffer(to: used + diff)
        }
        
        let endIndex = offset + oldSize
        let source = pointer + endIndex
        let destination = source + diff
        
        memmove(destination, source, used - endIndex)
        used = used &+ diff
    }
    
    func slice(bounds: Bounds) -> Buffer {
        let buffer = Buffer(allocating: bounds.length)
        let source = self.pointer.assumingMemoryBound(to: UInt8.self) + bounds.offset
        buffer.initialize(atOffset: 0, from: source, length: bounds.length)
        buffer.used = bounds.length
        return buffer
    }
    
    deinit { pointer.deallocate() }
}
