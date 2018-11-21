//import Foundation
//
//public struct JSONObject {
//    let data: Data
//    let description: JSONDescription
//    var reader: ReadOnlyJSONDescription
//    
//    public init(data: Data) throws {
//        self.data = data
//        
//        let size = data.count
//        self.description = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
//            return try JSONParser.scanValue(fromPointer: pointer, count: size).readOnly
//        }
//        self.reader = description.readOnly
//        
//        guard reader.type == .object else {
//            throw JSONError.expectedObject
//        }
//    }
//    
//    public subscript(key: String) -> JSONValue {
//        return 
//    }
//}
