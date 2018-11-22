//import Foundation
//
//public struct JSONObject {
//    let data: Data
//    let description: JSONDescription
//    var reader: ReadOnlyJSONDescription
//
//    public init(data: Data, description: JSONDescription) throws {
//
//    }
//
//    public init(data: Data) throws {
//        self.data = data
//
//        let size = data.count
//        self.description = try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
//            return try JSONParser.scanValue(fromPointer: pointer, count: size)
//        }
//        self.reader = description.readOnly
//
//        guard reader.type == .object else {
//            throw JSONError.expectedObject
//        }
//    }
//
//    private func withPointer<T>(_ run: (UnsafePointer<UInt8>) -> T) -> T {
//        return data.withUnsafeBytes(run)
//    }
//
//    public subscript(key: String) -> JSONValue? {
//        get {
//            return withPointer { pointer in
//                let type = reader.type(ofKey: key, in: pointer)
//
//                switch type {
//
//                }
//            }
//        }
//    }
//
//    public func value(_ type: String.Type, unicode: Bool = true, forKey key: String) -> String? {
//        return withPointer { pointer in
//            guard let (bounds, escaped) = reader.stringBounds(forKey: key, in: pointer) else {
//                return nil
//            }
//
//            return bounds.makeString(from: pointer, escaping: escaped, unicode: unicode)
//        }
//    }
//
//    public func value<F: FixedWidthInteger>(_ type: F.Type, forKey key: String) -> F? {
//        return withPointer { pointer in
//            guard let bounds = reader.integerBounds(forKey: key, in: pointer) else {
//                return nil
//            }
//
//            do {
//                return try bounds.makeInt(from: pointer)?.convert(to: type)
//            } catch {
//                return nil
//            }
//        }
//    }
//
//    public func value(_ type: Double.Type, forKey key: String) -> Double? {
//        return withPointer { pointer in
//            guard let (bounds, floating) = reader.floatingBounds(forKey: key, in: pointer) else {
//                return nil
//            }
//
//            return bounds.makeDouble(from: pointer, floating: floating)
//        }
//    }
//
//    public func value(_ type: Bool.Type, forKey key: String) -> Bool? {
//        return withPointer { pointer in
//            guard let type = reader.type(ofKey: key, in: pointer) else { return nil }
//
//            switch type {
//            case .boolTrue: return true
//            case .boolFalse: return false
//            default: return nil
//            }
//        }
//    }
//
//    public func value(_ type: JSONObject.Type, forKey key: String) -> JSONObject? {
//        return withPointer { pointer in
//            guard let offset = reader.offset(forKey: key, in: pointer) else {
//                return nil
//            }
//
//            reader.sub
//        }
//    }
//}
//
//public protocol JSONValue {}
