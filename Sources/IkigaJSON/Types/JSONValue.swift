import Foundation

public protocol JSONValue {}

extension JSONObject: JSONValue {
    public init?(json: JSONValue?) {
        guard let me = json.object else { return nil }
        self = me
    }
}

extension JSONArray: JSONValue {
    public init?(json: JSONValue?) {
        guard let me = json.array else { return nil }
        self = me
    }
}

extension String: JSONValue {
    public init?(json: JSONValue?) {
        guard let me = json.string else { return nil }
        self = me
    }
}

extension Int: JSONValue {
    public init?(json: JSONValue?) {
        guard let me = json.int else { return nil }
        self = me
    }
}

extension Double: JSONValue {
    public init?(json: JSONValue?) {
        guard let me = json.double else { return nil }
        self = me
    }
}

extension Bool: JSONValue {
    public init?(json: JSONValue?) {
        guard let me = json.bool else { return nil }
        self = me
    }
}

extension NSNull: JSONValue {
    public convenience init?(json: JSONValue?) {
        guard json is NSNull else { return nil }
        self.init()
    }
}

extension JSONValue {
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
        get {
            return self.object?[key]
        }
        set {
            if var object = self as? JSONObject {
                object[key] = newValue
                self = object as! Self
            }
        }
    }
    
    public subscript(index: Int) -> JSONValue {
        get {
            return (self as! JSONArray)[index]
        }
        set {
            if var array = self as? JSONArray {
                array[index] = newValue
                self = array as! Self
            }
        }
    }
}

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
}
