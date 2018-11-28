import Foundation

public protocol JSONValue {}
extension JSONObject: JSONValue {}
extension JSONArray: JSONValue {}
extension String: JSONValue {}
extension Int: JSONValue {}
extension Double: JSONValue {}
extension Bool: JSONValue {}
extension NSNull: JSONValue {}

extension Optional where Wrapped == JSONValue {
    public var string: String? {
        return self as? String
    }
    
    public var double: Double? {
        return self as? Double
    }
    
    public var int: Int? {
        return self as? Int
    }
    
    public var null: NSNull? {
        return self as? NSNull
    }
    
    public var bool: Bool? {
        return self as? Bool
    }
    
    public var object: JSONObject? {
        return self as? JSONObject
    }

    public var array: JSONArray? {
        return self as? JSONArray
    }
    
    public subscript(key: String) -> JSONValue? {
        return self.object?[key]
    }
    
    public subscript(index: Int) -> JSONValue? {
        return self.array?[index]
    }
}
