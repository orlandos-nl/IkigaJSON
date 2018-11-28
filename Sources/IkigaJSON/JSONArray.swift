import Foundation

public struct JSONArray {
    let data: Data
    var reader: ReadOnlyJSONDescription
    
    public init(data: Data) throws {
        self.data = data
        
        let size = data.count
        
        let description = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
            return try JSONParser.scanValue(fromPointer: pointer, count: size)
        }
        self.reader = description.readOnly
        
        guard reader.type == .array else {
            throw JSONError.expectedObject
        }
    }
    
    internal init(data: Data, description: ReadOnlyJSONDescription) {
        self.data = data
        self.reader = description
    }
    
    private func withPointer<T>(_ run: (UnsafePointer<UInt8>) -> T) -> T {
        return data.withUnsafeBytes(run)
    }
    
    public subscript(index: Int) -> JSONValue? {
        get {
            if index >= reader.arrayCount() {
                // No value available
                return nil
            } else if index < 0 {
                fatalError("Negative index requested for JSONArray.")
            }
            
            return withPointer { pointer in
                // Array descriptions are 17 bytes
                var offset = 17
                
                for _ in 0..<index {
                    reader.skip(withOffset: &offset)
                }
                
                guard let type = reader.type(atOffset: offset) else {
                    return nil
                }

                switch type {
                case .object:
                    let description = self.reader.subDescription(offset: offset)
                    return JSONObject(data: data, description: description)
                case .array:
                    let description = self.reader.subDescription(offset: offset)
                    return JSONArray(data: data, description: description)
                case .boolTrue:
                    return true
                case .boolFalse:
                    return false
                case .string:
                    return reader.bounds(at: offset).makeString(from: pointer, escaping: false, unicode: true)
                case .stringWithEscaping:
                    return reader.bounds(at: offset).makeString(from: pointer, escaping: true, unicode: true)
                case .integer:
                    return reader.bounds(at: offset).makeInt(from: pointer)
                case .floatingNumber:
                    return reader.bounds(at: offset).makeDouble(from: pointer, floating: true)
                case .null:
                    return NSNull()
                }
                return nil
            }
        }
//        set {
//             TODO:
//        }
    }
}
