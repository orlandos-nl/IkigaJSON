import XCTest
import NIO
import Foundation
import IkigaJSON

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif

#if swift(>=6.2.1) && Spans
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
var newParser: IkigaJSONDecoder {
    return IkigaJSONDecoder()
}

//var parser: JSONDecoder {
//    return JSONDecoder()
//}

var newEncoder: IkigaJSONEncoder {
    return IkigaJSONEncoder()
}

#if swift(>=6.2.1) && Spans
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
#endif
final class IkigaJSONTests: XCTestCase {
    func testDecodeUInt64() throws {
        let json = """
        [
            7168154684488697857,
            7168154684488699905,
            7168154684488701953,
            7168154684488704001,
            7168154684488706049,
            7168154684488708097,
            7168154684488710145,
            7168154684488712193,
            7168154684488714241,
            7168154684488716289
        ]
        """.data(using: .utf8)!
        
        XCTAssertNoThrow(try IkigaJSONDecoder().decode([UInt64].self, from: json))
    }

    func testMemoryLeak() throws {
        for _ in 0..<100_000 {
            _ = try! JSONObject(buffer: .init(string: "{}"))
        }
    }

    func testURL() throws {
        struct Info: Codable, Equatable {
            let website: URL
        }

        let domain = "https://unbeatable.software"
        let info = Info(website: URL(string: domain)!)
        let jsonObject = try IkigaJSONEncoder().encodeJSONObject(from: info)
        XCTAssertEqual(jsonObject["website"].string, domain)
        let info2 = try IkigaJSONDecoder().decode(Info.self, from: jsonObject.data)
        XCTAssertEqual(info, info2)
    }

    func testDecimal() throws {
        struct Info: Codable, Equatable {
            let secretNumber: Decimal
        }

        let secretNumber: Decimal = 3.1414
        let info = Info(secretNumber: secretNumber)
        let jsonObject = try IkigaJSONEncoder().encodeJSONObject(from: info)
        XCTAssertEqual(jsonObject["secretNumber"].double!, 3.1414, accuracy: 0.001)
        let info2 = try IkigaJSONDecoder().decode(Info.self, from: jsonObject.data)
        XCTAssertEqual(info, info2)
    }

    func testEscapedUnicode() throws {
        do {
            let json: Data = #"{"simple":"\u00DF", "complex": "\ud83d\udc69\u200d\ud83d\udc69"}"#.data(using: .utf8)!

            let result = try IkigaJSONDecoder().decode([String: String].self, from: json)
            XCTAssertEqual(result, ["simple": "\u{00DF}", "complex": "\u{1F469}\u{200D}\u{1F469}"])
        }

        do {
            let json: Data = #"{"simple":"\u00DFhello world", "complex": "\uD83D\uDC69\u200D\uD83D\uDC69\u200D\uD83D\uDC67\u200D\uD83D\uDC67hello world"}"#.data(using: .utf8)!

            let result = try IkigaJSONDecoder().decode([String: String].self, from: json)
            XCTAssertEqual(result, ["simple": "ßhello world", "complex": "👩‍👩‍👧‍👧hello world"])
        }
    }

    func testEscapedUnicodeWeis() throws {
        do {
            let json: Data = #"{"foo":"\u0022wei\u00DF\u0022"}"#.data(using: .utf8)!

            let result = try IkigaJSONDecoder().decode([String: String].self, from: json)
            XCTAssertEqual(result, ["foo": #""weiß""#])
        }
    }
    
    func testPropertyWrapper() throws {
        @propertyWrapper struct FluentPropertyTest<Value: Codable & Equatable>: Codable, Equatable {
            var wrappedValue: Value
            init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.init(wrappedValue: try container.decode(Value.self))
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(self.wrappedValue)
            }
        }
        
        struct SomeType<Value: Codable & Equatable>: Codable, Equatable {
            @FluentPropertyTest var value: Value?
        }
        
        let typeA = SomeType<String?>(value: .some(.none))
        let typeB = SomeType<String?>(value: "cheese")
        
        let jsonA = try IkigaJSONEncoder().encode(typeA)
        let jsonB = try IkigaJSONEncoder().encode(typeB)
        
        let typeAdecoded = try IkigaJSONDecoder().decode(SomeType<String?>.self, from: jsonA)
        let typeBdecoded = try IkigaJSONDecoder().decode(SomeType<String?>.self, from: jsonB)
        
        let typeAreencoded = try IkigaJSONEncoder().encode(typeAdecoded)
        let typeBreencoded = try IkigaJSONEncoder().encode(typeBdecoded)
        
        XCTAssertEqual(jsonA, typeAreencoded)
        XCTAssertEqual(jsonB, typeBreencoded)
    }
    
    func testConst() {
        let json = """
        [
            {
                "description": "const with -2.0 matches integer and float types",
                "schema": {
                    "$schema": "https://json-schema.org/draft/2020-12/schema",
                    "const": -2.0
                }
            }
        ]
        """
        let b = ByteBuffer(string: json)
        guard let a = try? JSONArray(buffer: b) else {
            XCTFail()
            return
        }
        XCTAssertEqual(a[0]["schema"]?["const"].double, -2.0)
    }
    
    func testMissingCommaInObject() {
        let json = """
        {
            "yes": "✅",
            "bug": "🐛",
            "awesome": [true, false,     false, false,true]
            "flag": "🇳🇱"
        }
        """.data(using: .utf8)!
        
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        XCTAssertThrowsError(try newParser.decode(Test.self, from: json))
    }

    func testEncodeNestedArray() throws {
        struct Object: Codable {
            var array = Array(repeating: Set<String>(minimumCapacity: 12), count: 8)
        }

        let data = try IkigaJSONEncoder().encode(Object())
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"array\":[[],[],[],[],[],[],[],[]]}")
    }
    
    func testDecodeOptionalUUID() throws {
        struct Account {
            typealias IDValue = UUID
        }
        
        struct LoginRequest: Codable {
            let accountId: Account.IDValue? // This is a UUID
        }
        
        let id = UUID().uuidString
        
        let object: JSONObject = [
            "accountId": id
        ]
        
        let decoder = IkigaJSONDecoder()
        var request = try decoder.decode(LoginRequest.self, from: object.string)
        XCTAssertEqual(request.accountId?.uuidString, id)
        
        request = try decoder.decode(LoginRequest.self, from: "{}")
        XCTAssertNil(request.accountId)
    }
    
    func testArrayDoS() throws {
        let json = "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]],[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]],[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]],[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]],[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]],]"
        
        XCTAssertThrowsError(try newParser.decode([String].self, from: json))
    }
    
    func testEncodeNilAsNull() throws {
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int?
            
            init(stringValue: String) {
                self.stringValue = stringValue
            }
            
            init(intValue: Int) {
                self.intValue = intValue
                self.stringValue = String(intValue)
            }
        }
        
        struct Test: Encodable {
            let encodeValue: Bool
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                let value: String? = encodeValue ? "hi" : nil
                try container.encodeIfPresent(value, forKey: .init(stringValue: "hi"))
            }
        }
        
        var encoder = IkigaJSONEncoder()
        encoder.settings.nilValueEncodingStrategy = .alwaysEncodeNil
        
        let valueObject = try encoder.encodeJSONObject(from: Test(encodeValue: true))
        let nullValueObject = try encoder.encodeJSONObject(from: Test(encodeValue: false))
        
        encoder.settings.nilValueEncodingStrategy = .neverEncodeNil
        let emptyObject = try encoder.encodeJSONObject(from: Test(encodeValue: false))
        
        XCTAssertEqual(valueObject["hi"].string, "hi")
        XCTAssertNotNil(nullValueObject["hi"].null)
        XCTAssertNil(emptyObject["hi"].null)
    }
    
    func testInlineEditing() throws {
        struct Test: Codable {
            let yes: String
        }
        
        var object = JSONObject()
        object["yes"] = "a"
        object["yes"] = "ab"
        object["yes"] = "abc"
        object["yes"] = "ab"
        object["yes"] = "b"
        
        let test = try Foundation.JSONDecoder().decode(Test.self, from: object.data)
        XCTAssertEqual(test.yes, "b")
    }

    func testFormFeedParsing() throws  {
        let string = #"""
        {
            "hi": "\f"
        }
        """#.data(using: .utf8)!
        
        let object = try JSONObject(data: string)
        XCTAssertEqual(object["hi"].string, "\u{c}")
    }

    func testFormFeedEncoding() throws {
        let object: JSONObject = [
            "hi": "\u{c}"
        ]
        
        XCTAssertEqual(object.string, #"{"hi":"\f"}"#)
    }

    func testBackspaceParsing() throws  {
        let string = #"""
        {
            "hi": "\b"
        }
        """#.data(using: .utf8)!
        
        let object = try JSONObject(data: string)
        XCTAssertEqual(object["hi"].string, "\u{8}")
    }

    func testBackspaceEncoding() throws {
        let object: JSONObject = [
            "hi": "\u{8}"
        ]
        
        XCTAssertEqual(object.string, #"{"hi":"\b"}"#)
    }
    
    func testBackslashWorks() throws {
        let string = #"""
        {
            "\\hi": "\""
        }
        """#.data(using: .utf8)!
        
        XCTAssertNoThrow(try JSONObject(data: string))
    }
    
    func testEncodeDictionary() throws {
        let dict: [String: String] = ["hemail": "nova@helixbooking.com"]
        let object = try IkigaJSONEncoder().encode(dict)
        let dict2 = try JSONDecoder().decode([String: String].self, from: object)
        XCTAssertEqual(dict, dict2)
    }
    
    func testFoundationCompatibleDataEncoding() throws {
        struct UploadRequest: Codable, Equatable {
            public var filename: String
            public var data: Data
        }
        
        let json = UploadRequest(filename: "Hello.jpeg", data: Data(repeating: 0x01, count: 5))
        let data = try IkigaJSONEncoder().encode(json)
        let json2 = try JSONDecoder().decode(UploadRequest.self, from: data)
        
        XCTAssertEqual(json, json2)
    }
    
    func testImageDataDecoding() throws {
        struct UploadRequest: Codable, Equatable {
            public var filename: String
            public var data: Data
        }
        
        let data = """
        {
            "filename": "Hello.jpeg",
            "data": "\\/9j\\/4AAQSkZJRg\\/B"
        }
        """.data(using: .utf8)!
        
        XCTAssertNoThrow(try IkigaJSONDecoder().decode(UploadRequest.self, from: data))
    }
    
    func testAndrewDataDecoding() throws {
        struct UploadRequest: Codable, Equatable {
            public var filename: String
            public var data: Data
        }
        
        let data = """
        {
            "filename": "Hello.jpeg",
            "data": "\\/9j\\/4AAQSkZJRgAB"
        }
        """.data(using: .utf8)!
        
        XCTAssertNoThrow(try IkigaJSONDecoder().decode(UploadRequest.self, from: data))
    }
    
    func testFoundationCompatibleDataDecoding() throws {
        struct UploadRequest: Codable, Equatable {
            public var filename: String
            public var data: Data
        }
        
        let json = UploadRequest(filename: "Hello.jpeg", data: Data(repeating: 0x01, count: 5))
        let data = try JSONEncoder().encode(json)
        let json2 = try IkigaJSONDecoder().decode(UploadRequest.self, from: data)
        
        XCTAssertEqual(json, json2)
    }
    
    func testEncodeJSONObject() throws {
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        let test = Test(yes: "Hello", bug: "fly", awesome: [true], flag: "UK")
        XCTAssertThrowsError(try newEncoder.encodeJSONArray(from: test))
        
        let object = try newEncoder.encodeJSONObject(from: test)
        XCTAssertEqual(object["yes"].string, "Hello")
        XCTAssertEqual(object["bug"].string, "fly")
        XCTAssertEqual(object["awesome"].array?.count, 1)
        XCTAssertEqual(object["awesome"].array?[0].bool, true)
        XCTAssertEqual(object["flag"].string, "UK")
    }
    
    func testEncodeNil() throws {
        struct Test: Codable {
            let yes: Int?
        }
        
        let value = Test(yes: 3)
        let noValue = Test(yes: nil)
        
        var encoder = IkigaJSONEncoder()
        var object = try encoder.encodeJSONObject(from: value)
        XCTAssertEqual(object["yes"].int, 3)
        
        object = try encoder.encodeJSONObject(from: noValue)
        XCTAssertFalse(object["yes"] is NSNull)
        XCTAssertFalse(object.keys.contains("yes"))
        
        encoder.settings.nilValueEncodingStrategy = .alwaysEncodeNil
        
        object = try encoder.encodeJSONObject(from: noValue)
        XCTAssert(object["yes"] is NSNull)
        XCTAssert(object.keys.contains("yes"))
    }

    func testEncodeOptionalNilProperty() throws {
        struct Test: Codable {
            struct Custom: Codable, Equatable { var value = 3 }
            let yes: Custom?
        }

        let value = Test(yes: .init())
        let noValue = Test(yes: nil)

        var encoder = IkigaJSONEncoder()
        var object = try encoder.encodeJSONObject(from: value)
        XCTAssertEqual(object["yes"]?["value"]?.int, 3)

        object = try encoder.encodeJSONObject(from: noValue)
        XCTAssertFalse(object["yes"] is NSNull)
        XCTAssertFalse(object.keys.contains("yes"))

        encoder.settings.nilValueEncodingStrategy = .alwaysEncodeNil

        object = try encoder.encodeJSONObject(from: noValue)
        XCTAssert(object["yes"] is NSNull)
        XCTAssert(object.keys.contains("yes"))
    }

    func testEncodeOptionalArrayNil() throws {
        struct Test: Codable {
            struct Custom: Codable, Equatable { var value = 3 }
            let yes: [Custom?]
        }

        let value = Test(yes: [.init(), .init(), nil, .init(), .init()])

        var encoder = IkigaJSONEncoder()
        encoder.settings.nilValueEncodingStrategy = .neverEncodeNil
        
        var object = try encoder.encodeJSONObject(from: value)
        XCTAssertEqual(object["yes"]?.array?.count, 4)
        XCTAssertNil(object["yes"]?.array?[2].null)

        encoder.settings.nilValueEncodingStrategy = .alwaysEncodeNil

        object = try encoder.encodeJSONObject(from: value)
        XCTAssertEqual(object["yes"]?.array?.count, 5)
        XCTAssertNotNil(object["yes"]?.array?[2].null)
    }
    
    private func measureTime(run block: () throws -> ()) rethrows -> TimeInterval {
        let date = Date()
        
        for _ in 0..<1_000 {
            try block()
        }
        
        return Date().timeIntervalSince(date)
    }
    
    func testAllEncoding() throws {
        struct AllPrimitives: Codable {
            var s: String
            var f: Float
            var d: Double
            var b: Bool
            var b2: Bool
            var i: Int
            var i8: Int8
            var i16: Int16
            var i32: Int32
            var i64: Int64
            var u: UInt
            var u8: UInt8
            var u16: UInt16
            var u32: UInt32
            var u64: UInt64
            
            var os: String?
            var of: Float?
            var od: Double?
            var ob: Bool?
            var ob2: Bool?
            var oi: Int?
            var oi8: Int8?
            var oi16: Int16?
            var oi32: Int32?
            var oi64: Int64?
            var ou: UInt?
            var ou8: UInt8?
            var ou16: UInt16?
            var ou32: UInt32?
            var ou64: UInt64?
        }
        
        struct Test: Codable {
            var a: [AllPrimitives]
            var p: AllPrimitives
            var d: [String: AllPrimitives]
        }
        
        let primitives = AllPrimitives(s: "s", f: 3.1, d: 4.2, b: true, b2: false, i: 5, i8: 89, i16: -7667, i32: -889, i64: 123123213, u: 0x54, u8: 213, u16: 51, u32: 231, u64: 513, os: nil, of: nil, od: nil, ob: nil, ob2: nil, oi: nil, oi8: nil, oi16: nil, oi32: nil, oi64: nil, ou: nil, ou8: nil, ou16: nil, ou32: nil, ou64: nil)
        let primitives2 = AllPrimitives(s: "s", f: 3.1, d: 4.2, b: true, b2: false, i: 5, i8: 89, i16: -7667, i32: -889, i64: 123123213, u: 0x54, u8: 213, u16: 51, u32: 231, u64: 513, os: "s", of: 3.1, od: 4.2, ob: true, ob2: false, oi: -123, oi8: 12, oi16: -611, oi32: 1231512, oi64: 62341, ou: 3152113, ou8: 51, ou16: 314, ou32: 21321, ou64: 15334123441)
        
        let test = Test(a: [primitives, primitives2], p: primitives, d: ["a": primitives, "b": primitives2])
        
        func objectNil() throws {
            func testFirst(against object: JSONObject?) {
                guard let object = object else {
                    XCTFail()
                    return
                }
                
                XCTAssertEqual(object.keys, ["s", "f", "d", "b", "b2", "i", "i8", "i16", "i32", "i64", "u", "u8", "u16", "u32", "u64"])
            }
            
            func testSecond(against object: JSONObject?) {
                guard let object = object else {
                    XCTFail()
                    return
                }
                
                XCTAssertEqual(object.keys, ["s", "f", "d", "b", "b2", "i", "i8", "i16", "i32", "i64", "u", "u8", "u16", "u32", "u64", "os", "of", "od", "ob", "ob2", "oi", "oi8", "oi16", "oi32", "oi64", "ou", "ou8", "ou16", "ou32", "ou64"])
            }
            
            var encoder = IkigaJSONEncoder()
            encoder.settings.nilValueEncodingStrategy = .neverEncodeNil
            let object = try encoder.encodeJSONObject(from: test)
            
            XCTAssertEqual(object.keys, ["a", "p", "d"])
            
            testFirst(against: object["a"].array?[0].object)
            testFirst(against: object["p"].object)
            testFirst(against: object["d"].object?["a"]?.object)
            
            testSecond(against: object["a"].array?[1].object)
            testSecond(against: object["d"].object?["b"]?.object)
        }
        
        func objectNull() throws {
            func testFirst(against object: JSONObject?) {
                guard let object = object else {
                    XCTFail()
                    return
                }
                
                XCTAssertEqual(object.keys, ["s", "f", "d", "b", "b2", "i", "i8", "i16", "i32", "i64", "u", "u8", "u16", "u32", "u64", "os", "of", "od", "ob", "ob2", "oi", "oi8", "oi16", "oi32", "oi64", "ou", "ou8", "ou16", "ou32", "ou64"])
            }
            
            func testSecond(against object: JSONObject?) {
                guard let object = object else {
                    XCTFail()
                    return
                }
                
                XCTAssertEqual(object.keys, ["s", "f", "d", "b", "b2", "i", "i8", "i16", "i32", "i64", "u", "u8", "u16", "u32", "u64", "os", "of", "od", "ob", "ob2", "oi", "oi8", "oi16", "oi32", "oi64", "ou", "ou8", "ou16", "ou32", "ou64"])
            }
            
            var encoder = IkigaJSONEncoder()
            encoder.settings.nilValueEncodingStrategy = .alwaysEncodeNil
            let object = try encoder.encodeJSONObject(from: test)
            
            XCTAssertEqual(object.keys, ["a", "p", "d"])
            
            testFirst(against: object["a"].array?[0].object)
            testFirst(against: object["p"].object)
            testFirst(against: object["d"].object?["a"]?.object)
            
            testSecond(against: object["a"].array?[1].object)
            testSecond(against: object["d"].object?["b"]?.object)
        }
    }
    
    func testEncodeInt() throws {
        struct Test: Codable {
            let yes: Int
        }
        
        let value = Test(yes: 3)
        let object = try IkigaJSONEncoder().encodeJSONObject(from: value)
        XCTAssertEqual(object["yes"].int, 3)
    }
    
    func testEncodeEscaping() throws {
        struct Test: Codable, Equatable {
            let yes: String
        }
        
        let test = Test(yes: "\n")
        let json = try IkigaJSONEncoder().encode(test)
        let test2 = try JSONDecoder().decode(Test.self, from: json)
        XCTAssertEqual(test, test2)
    }
    
    func testEncodeJSONArray() throws {
        struct Test: Codable, Equatable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        let test = Test(yes: "Hello", bug: "fly", awesome: [true], flag: "UK")
        let tests = [test, test, test]
        
        XCTAssertThrowsError(try newEncoder.encodeJSONObject(from: tests))
        
        let array = try newEncoder.encodeJSONArray(from: tests)
        XCTAssertEqual(array.count, 3)
        
        for object in array {
            guard let object = object.object else {
                XCTFail("Not an object")
                return
            }
            
            XCTAssertEqual(object["yes"].string, "Hello")
            XCTAssertEqual(object["bug"].string, "fly")
            XCTAssertEqual(object["awesome"].array?.count, 1)
            XCTAssertEqual(object["awesome"].array?[0].bool, true)
            XCTAssertEqual(object["flag"].string, "UK")
        }
        
        let testsCopy = try JSONDecoder().decode([Test].self, from: array.data)
        XCTAssertEqual(testsCopy, tests)
        
        let testData = try newEncoder.encode(test)
        let testCopy = try JSONDecoder().decode(Test.self, from: testData)
        XCTAssertEqual(test, testCopy)
    }
    
    func testDecodeJSONObject() throws {
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        let jsonObject: JSONObject = [
            "yes": "true",
            "bug": "🐛",
            "awesome": [true, false, false] as JSONArray,
            "flag": "NL"
        ]
        
        let test = try newParser.decode(Test.self, from: jsonObject)
        
        XCTAssertEqual(test.yes, "true")
        XCTAssertEqual(test.bug, "🐛")
        XCTAssertEqual(test.awesome, [true, false, false])
        XCTAssertEqual(test.flag, "NL")
    }
    
    func testDecodeJSONArray() throws {
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        let jsonObject: JSONObject = [
            "yes": "true",
            "bug": "🐛",
            "awesome": [true, false, false] as JSONArray,
            "flag": "NL"
        ]
        
        let jsonArray: JSONArray = [
            jsonObject, jsonObject, jsonObject
        ]
        
        let tests = try newParser.decode([Test].self, from: jsonArray)
        XCTAssertEqual(tests.count, 3)
        
        for test in tests {
            XCTAssertEqual(test.yes, "true")
            XCTAssertEqual(test.bug, "🐛")
            XCTAssertEqual(test.awesome, [true, false, false])
            XCTAssertEqual(test.flag, "NL")
        }
    }
    
    func testMissingCommaInArray() {
        let json = """
        {
            "yes": "✅",
            "bug": "🐛",
            "awesome": [true false,     false, false,true],
            "flag": "🇳🇱"
        }
        """.data(using: .utf8)!
        
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        XCTAssertThrowsError(try newParser.decode(Test.self, from: json))
    }
    
    func testMissingEndOfArray() {
        let json = """
        {
            "yes": "✅",
            "bug": "🐛",
            "awesome": [true, false,     false, false,true
        """.data(using: .utf8)!
        
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        XCTAssertThrowsError(try newParser.decode(Test.self, from: json))
    }
    
    func testStreamingEncode() throws {
        let encoder = IkigaJSONEncoder()
        
        struct User: Codable {
            let id: String
            let username: String
            let role: String
            let awesome: Bool
            let superAwesome: Bool
        }
        
        let user0 = User(id: "0", username: "Joannis", role: "Admin", awesome: true, superAwesome: true)
        let user1 = User(id: "1", username: "Obbut", role: "Admin", awesome: true, superAwesome: true)
        
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: 4_096)
        buffer.writeStaticString("[")
        try encoder.encodeAndWrite(user0, into: &buffer)
        buffer.writeStaticString(",")
        try encoder.encodeAndWrite(user1, into: &buffer)
        buffer.writeStaticString("]")
        
        let users = try JSONArray(buffer: buffer)
        XCTAssertEqual(users.count, 2)
        
        XCTAssertEqual(users[0]["id"] as? String, "0")
        XCTAssertEqual(users[0]["username"] as? String, "Joannis")
        
        XCTAssertEqual(users[1]["id"] as? String, "1")
        XCTAssertEqual(users[1]["username"] as? String, "Obbut")
        
        let users2 = try newParser.decode([User].self, from: buffer)
        XCTAssertEqual(users2.count, 2)
        
        XCTAssertEqual(users2[0].id, "0")
        XCTAssertEqual(users2[0].username, "Joannis")
        
        XCTAssertEqual(users2[1].id, "1")
        XCTAssertEqual(users2[1].username, "Obbut")
    }
    
    func testMissingEndOfObject() {
        let json = """
        {
            "yes": "✅",
            "bug": "🐛",
            "awesome": [true, false,     false, false,true],
            "flag": "🇳🇱"
        """.data(using: .utf8)!
        
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        XCTAssertThrowsError(try newParser.decode(Test.self, from: json))
    }
    
    func testKeyEncoding() throws {
        var encoder = newEncoder
        encoder.settings.keyEncodingStrategy = .convertToSnakeCase
        
        struct Test: Codable {
            let userName: String
            let eMail: String
        }
        
        let user = Test(userName: "Joannis", eMail: "joannis@orlandos.nl")
        let json = try encoder.encodeJSONObject(from: user)
        
        XCTAssertEqual(Set(json.keys), ["user_name", "e_mail"])
    }
    
    func testEncodeNilAsNullFalse() throws {
        var encoder = newEncoder
        encoder.settings.nilValueEncodingStrategy = .neverEncodeNil
        
        struct Test: Codable {
            let nonOptional: String
            let optional: String?
        }
        
        let user = Test(nonOptional: "Joannis", optional: .none)
        let json = try encoder.encodeJSONObject(from: user)
        
        XCTAssertEqual(Set(json.keys), ["nonOptional"])
    }
    
    func testEncodeNilAsNullFalseInDoubleOptionalScenarios() throws {
        var encoder = newEncoder
        encoder.settings.nilValueEncodingStrategy = .neverEncodeNil
        
        struct Test: Codable {
            let nonOptional: String
            let optional: String??
        }
        
        let user = Test(nonOptional: "Joannis", optional: .some(.none))
        let json = try encoder.encodeJSONObject(from: user)
        
        XCTAssertEqual(Set(json.keys), ["nonOptional"])
    }
    
    func testKeyDecoding() throws {
        var parser = newParser
        parser.settings.keyDecodingStrategy = .convertFromSnakeCase
        
        struct Test: Codable {
            let userName: String
            let eMail: String
        }
        
        let json0 = """
        {
            "userName": "Joannis",
            "e_mail": "joannis@orlandos.nl"
        }
        """.data(using: .utf8)!
        
        let json1 = """
        {
            "user_name": "Joannis",
            "e_mail": "joannis@orlandos.nl"
        }
        """.data(using: .utf8)!
        
        do {
            let user = try parser.decode(Test.self, from: json0)
            XCTAssertEqual(user.userName, "Joannis")
            XCTAssertEqual(user.eMail, "joannis@orlandos.nl")
        } catch {
            XCTFail()
        }
        
        do {
            let user = try parser.decode(Test.self, from: json1)
            XCTAssertEqual(user.userName, "Joannis")
            XCTAssertEqual(user.eMail, "joannis@orlandos.nl")
        } catch {
            XCTFail()
        }
    }
    
    func testEncoding() throws {
        let json = """
        {
            "yes": "✅",
            "bug": "🐛",
            "awesome": [true, false,     false, false,true],
            "flag": "🇳🇱"
        }
        """.data(using: .utf8)!
        
        struct Test: Codable {
            let yes: String
            let bug: String
            let awesome: [Bool]
            let flag: String
        }
        
        let test = try newParser.decode(Test.self, from: json)
        XCTAssertEqual(test.yes, "✅")
        XCTAssertEqual(test.bug, "🐛")
        XCTAssertEqual(test.awesome, [true,false,false,false,true])
        XCTAssertEqual(test.flag, "🇳🇱")
        
        let jsonData = try newEncoder.encode(test)
        let test2 = try newParser.decode(Test.self, from: jsonData)
        XCTAssertEqual(test2.yes, "✅")
        XCTAssertEqual(test2.bug, "🐛")
        XCTAssertEqual(test2.awesome, [true,false,false,false,true])
        XCTAssertEqual(test2.flag, "🇳🇱")
    }
    
    func testEmojis() throws {
        let json = """
        {
            "yes": "✅",
            "bug": "🐛",
            "flag": "🇳🇱"
        }
        """.data(using: .utf8)!
        
        struct Test: Decodable {
            let yes: String
            let bug: String
            let flag: String
        }
        
        let test = try newParser.decode(Test.self, from: json)
        XCTAssertEqual(test.yes, "✅")
        XCTAssertEqual(test.bug, "🐛")
        XCTAssertEqual(test.flag, "🇳🇱")
    }
    
    func testObject() throws {
        let json = """
        {
            "id": "0",
            "username": "Joannis",
            "role": "admin",
            "awesome": true,
            "superAwesome": false
        }
        """.data(using: .utf8)!
        
        struct User: Decodable {
            let id: String
            let username: String
            let role: String
            let awesome: Bool
            let superAwesome: Bool
        }
        
        let user = try newParser.decode(User.self, from: json)
        
        XCTAssertEqual(user.id, "0")
        XCTAssertEqual(user.username, "Joannis")
        XCTAssertEqual(user.role, "admin")
        XCTAssertTrue(user.awesome)
        XCTAssertFalse(user.superAwesome)
    }
    
    func testArray() throws {
        let json = """
        {
            "id": "0",
            "username": "Joannis",
            "roles": ["admin", null, "member", "moderator"],
            "awesome": true,
            "superAwesome": false
        }
        """.data(using: .utf8)!
        
        struct User: Decodable {
            let id: String
            let username: String
            let roles: [String?]
            let awesome: Bool
            let superAwesome: Bool
        }
        
        let user = try newParser.decode(User.self, from: json)
        
        XCTAssertEqual(user.id, "0")
        XCTAssertEqual(user.username, "Joannis")
        XCTAssertEqual(user.roles.count, 4)
        XCTAssertEqual(user.roles[0], "admin")
        XCTAssertEqual(user.roles[1], nil)
        XCTAssertEqual(user.roles[2], "member")
        XCTAssertEqual(user.roles[3], "moderator")
        XCTAssertTrue(user.awesome)
        XCTAssertFalse(user.superAwesome)
    }
    
    func testISO8601DateStrategy() throws {
        var decoder = newParser
        decoder.settings.dateDecodingStrategy = .iso8601
        
        let date = Date()
        let string = ISO8601DateFormatter().string(from: date)
        
        let json = """
        {
            "createdAt": "\(string)"
        }
        """.data(using: .utf8)!
        
        struct Test: Decodable {
            let createdAt: Date
        }
        
        let test = try decoder.decode(Test.self, from: json)
        
        // Because of Double rounding errors, this is necessary
        XCTAssertEqual(Int(test.createdAt.timeIntervalSince1970), Int(date.timeIntervalSince1970))
    }
    
    func testEpochSecDateStrategy() throws {
        var decoder = newParser
        decoder.settings.dateDecodingStrategy = .secondsSince1970
        
        let date = Date()
        
        let json = """
        {
            "createdAt": \(Int(date.timeIntervalSince1970))
        }
        """.data(using: .utf8)!
        
        struct Test: Decodable {
            let createdAt: Date
        }
        
        let test = try decoder.decode(Test.self, from: json)
        
        // Because of Double rounding errors, this is necessary
        XCTAssertEqual(Int(test.createdAt.timeIntervalSince1970), Int(date.timeIntervalSince1970))
    }
    
    func testEpochMSDateStrategy() throws {
        var decoder = newParser
        decoder.settings.dateDecodingStrategy = .millisecondsSince1970
        
        let date = Date()
        
        let json = """
            {
            "createdAt": \(Int(date.timeIntervalSince1970 * 1000))
            }
            """.data(using: .utf8)!
        
        struct Test: Decodable {
            let createdAt: Date
        }
        
        let test = try decoder.decode(Test.self, from: json)
        
        // Because of Double rounding errors, this is necessary
        XCTAssertEqual(Int(test.createdAt.timeIntervalSince1970), Int(date.timeIntervalSince1970))
    }
    
    func testEscaping() throws {
        let json = #"""
        {
            "id": "0",
            "username": "Joannis\tis\nawesome\/\\\"",
            "roles": ["admin", null, "member", "moderator"],
            "awesome": true,
            "superAwesome": false
        }
        """#.data(using: .utf8)!
        
        struct User: Decodable {
            let id: String
            let username: String
            let roles: [String?]
            let awesome: Bool
            let superAwesome: Bool
        }
        
        let user = try newParser.decode(User.self, from: json)
        
        XCTAssertEqual(user.id, "0")
        XCTAssertEqual(user.username, "Joannis\tis\nawesome/\\\"")
        XCTAssertEqual(user.roles.count, 4)
        XCTAssertEqual(user.roles[0], "admin")
        XCTAssertEqual(user.roles[1], nil)
        XCTAssertEqual(user.roles[2], "member")
        XCTAssertEqual(user.roles[3], "moderator")
        XCTAssertTrue(user.awesome)
        XCTAssertFalse(user.superAwesome)
    }
    
    func testNumerical() throws {
        let json = """
        {
            "piD": 3.14,
            "piF": 0.314e1,
            "piFm": 314e-2,
            "piFp": 0.0314e+2,
            "u8": 255,
            "u8zero": 0,
            "i8": -127,
            "imax": \(Int32.max),
            "imin": \(Int32.min)
        }
        """.data(using: .utf8)!
        
        struct Stuff: Decodable {
            let piD: Double
            let piF: Float
            let piFm: Float
            let piFp: Float
            let u8: UInt8
            let u8zero: UInt8
            let i8: Int8
            let imax: Int32
            let imin: Int32
        }
        
        let stuff = try newParser.decode(Stuff.self, from: json)
        
        XCTAssertEqual(stuff.piD, 3.14)
        XCTAssertEqual(stuff.piF, 3.14)
        XCTAssertEqual(stuff.piFm, 3.14)
        XCTAssertEqual(stuff.piFp, 3.14)
        XCTAssertEqual(stuff.u8, 255)
        XCTAssertEqual(stuff.u8zero, 0)
        XCTAssertEqual(stuff.i8, -127)
        XCTAssertEqual(stuff.imax, .max)
        XCTAssertEqual(stuff.imin, .min)
    }
    
    func testObjectAccess() {
        var object: JSONObject = [
            "awesome": true,
            "superAwesome": false
        ]
        
        XCTAssertEqual(object["awesome"] as? Bool, true)
        XCTAssertEqual(object["superAwesome"] as? Bool, false)
        
        object["awesome"] = nil
        
        XCTAssertEqual(object["awesome"] as? Bool, nil)
        XCTAssertEqual(object["superAwesome"] as? Bool, false)
        
        object["awesome"] = true
        
        XCTAssertEqual(object["awesome"] as? Bool, true)
        XCTAssertEqual(object["superAwesome"] as? Bool, false)
        
        object["awesome"] = "true"
        
        XCTAssertEqual(object["awesome"] as? String, "true")
        XCTAssertEqual(object["superAwesome"] as? Bool, false)
        
        object["username"] = true
        XCTAssertEqual(object["username"] as? Bool, true)
        
        object["username"] = false
        XCTAssertEqual(object["username"] as? Bool, false)
        
        object["username"] = 3.14
        XCTAssertEqual(object["username"] as? Double, 3.14)
    }
    
    func testArrayUnsetValue() {
        var object = JSONObject()
        
        object["key"] = true
        XCTAssertEqual(object["key"] as? Bool, true)
        object["key"] = nil
        
        object["key"] = false
        XCTAssertEqual(object["key"] as? Bool, false)
        object["key"] = nil
        
        object["key"] = 3.14
        XCTAssertEqual(object["key"] as? Double, 3.14)
        object["key"] = nil
        
        object["key"] = -3.14
        XCTAssertEqual(object["key"] as? Double, -3.14)
        object["key"] = nil
        
        object["key"] = NSNull()
        XCTAssert(object["key"] is NSNull)
        object["key"] = nil
        
        object["key"] = 5
        XCTAssertEqual(object["key"] as? Int, 5)
        object["key"] = nil
        
        object["key"] = "Hello, world"
        XCTAssertEqual(object["key"] as? String, "Hello, world")
        object["key"] = nil
        
        object["key"] = [
            3, true, false, NSNull(), 3.14
        ] as JSONArray
        
        if let array = object["key"] as? JSONArray {
            XCTAssertEqual(array[0] as? Int, 3)
            XCTAssertEqual(array[1] as? Bool, true)
            XCTAssertEqual(array[2] as? Bool, false)
            XCTAssert(array[3] is NSNull)
            XCTAssertEqual(array[4] as? Double, 3.14)
        } else {
            XCTFail()
        }
        object["key"] = nil
        
        XCTAssertEqual(object.string, "{}")
    }
    
    func testInvalidJSONCase() {
        let object = """
        {
            "hoi" "",
        }
        """
        
        struct Test: Codable {
            var hoi: String
        }
        
        let decoder = IkigaJSONDecoder()
        XCTAssertThrowsError(try decoder.decode(Test.self, from: object))
    }
    
    func testDataEncoding() throws {
        struct Datas: Codable {
            var data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        }
        
        var encoder = IkigaJSONEncoder()
        let instance = Datas()
        
        encoder.settings.dataEncodingStrategy = .deferredToData
        var json = try encoder.encodeJSONObject(from: instance)
        if let bytes = json["data"] {
            XCTAssertEqual(bytes[0].int, 1)
            XCTAssertEqual(bytes[1].int, 2)
            XCTAssertEqual(bytes[2].int, 3)
            XCTAssertEqual(bytes[3].int, 4)
            XCTAssertEqual(bytes[4].int, 5)
        } else {
            XCTFail()
        }
        
        encoder.settings.dataEncodingStrategy = .base64
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["data"].string, instance.data.base64EncodedString())
        
        encoder.settings.dataEncodingStrategy = .custom({ _, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(true)
        })
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["data"].bool, true)
    }
    
    func testDataDecoding() throws {
        struct Datas: Codable {
            let data: Data
        }
        
        var decoder = IkigaJSONDecoder()

        decoder.settings.dataDecodingStrategy = .deferredToData
        var datas = try decoder.decode(Datas.self, from: "{\"data\":[1,2,3]}")
        XCTAssertEqual(datas.data, Data([1,2,3]))
        
        decoder.settings.dataDecodingStrategy = .custom({ _ in
            return Data([1, 2, 3])
        })
        datas = try decoder.decode(Datas.self, from: "{\"data\":true}")
        XCTAssertEqual(datas.data, Data([1,2,3]))
        
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        decoder.settings.dataDecodingStrategy = .base64
        datas = try decoder.decode(Datas.self, from: "{\"data\":\"\(data.base64EncodedString())\"}")
        XCTAssertEqual(datas.data, data)
    }
    
    func testArrayDataEncoding() throws {
        struct Datas: Codable {
            var datas = [Data([0x01, 0x02, 0x03, 0x04, 0x05])]
        }
        
        var encoder = IkigaJSONEncoder()
        let instance = Datas()
        
        encoder.settings.dataEncodingStrategy = .deferredToData
        var json = try encoder.encodeJSONObject(from: instance)
        if let bytes = json["datas"].array?[0].array {
            XCTAssertEqual(bytes[0].int, 1)
            XCTAssertEqual(bytes[1].int, 2)
            XCTAssertEqual(bytes[2].int, 3)
            XCTAssertEqual(bytes[3].int, 4)
            XCTAssertEqual(bytes[4].int, 5)
        } else {
            XCTFail()
        }
        
        encoder.settings.dataEncodingStrategy = .base64
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["datas"].array?[0].string, instance.datas[0].base64EncodedString())
        
        encoder.settings.dataEncodingStrategy = .custom({ _, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(true)
        })
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["datas"].array?[0].bool, true)
    }
    
    func testArrayDateEncoding() throws {
        struct Dates: Codable {
            var dates = [Date()]
        }
        
        var encoder = IkigaJSONEncoder()
        let instance = Dates()
        
        encoder.settings.dateEncodingStrategy = .iso8601
        let iso = ISO8601DateFormatter().string(from: instance.dates[0])
        var json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["dates"].array?[0].string, iso)
        
        encoder.settings.dateEncodingStrategy = .deferredToDate
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["dates"].array?[0].double, instance.dates[0].timeIntervalSinceReferenceDate)
        
        encoder.settings.dateEncodingStrategy = .secondsSince1970
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["dates"].array?[0].double, instance.dates[0].timeIntervalSince1970)
        
        encoder.settings.dateEncodingStrategy = .millisecondsSince1970
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["dates"].array?[0].double, instance.dates[0].timeIntervalSince1970 * 1000)
        
        encoder.settings.dateEncodingStrategy = .custom({ _, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(true)
        })
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["dates"].array?[0].bool, true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY"
        encoder.settings.dateEncodingStrategy = .formatted(formatter)
        json = try encoder.encodeJSONObject(from: instance)
        let result = formatter.string(from: instance.dates[0])
        XCTAssertEqual(json["dates"].array?[0].string, result)
    }
    
    func testDateEncoding() throws {
        struct DateTest: Codable {
            var date = Date()
        }
        
        var encoder = IkigaJSONEncoder()
        let instance = DateTest()
        
        encoder.settings.dateEncodingStrategy = .iso8601
        let iso = ISO8601DateFormatter().string(from: instance.date)
        var json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["date"].string, iso)
        
        encoder.settings.dateEncodingStrategy = .deferredToDate
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["date"].double, instance.date.timeIntervalSinceReferenceDate)
        
        encoder.settings.dateEncodingStrategy = .secondsSince1970
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["date"].double, instance.date.timeIntervalSince1970)
        
        encoder.settings.dateEncodingStrategy = .millisecondsSince1970
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["date"].double, instance.date.timeIntervalSince1970 * 1000)
        
        encoder.settings.dateEncodingStrategy = .custom({ date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(true)
        })
        json = try encoder.encodeJSONObject(from: instance)
        XCTAssertEqual(json["date"].bool, true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY"
        encoder.settings.dateEncodingStrategy = .formatted(formatter)
        json = try encoder.encodeJSONObject(from: instance)
        let result = formatter.string(from: instance.date)
        XCTAssertEqual(json["date"].string, result)
    }
    
    func testIkigaJSONEncoder() throws {
        struct NestedBlob: Codable, Equatable {
            let int: Int?
        }
        
        struct Blob: Codable, Equatable {
            let a: String
            let b: Int
            let c: Bool
            let d: Date
            let e: Double
            let f: NestedBlob
        }
        
        let blob = Blob(a: "hello", b: 41, c: true, d: Date(), e: 3.14, f: NestedBlob(int: 14))
        let json = try IkigaJSONEncoder().encode(blob)
        let blob2 = try JSONDecoder().decode(Blob.self, from: json)
        XCTAssertEqual(blob, blob2)
    }
    
    func testNestedObjectInObjectAccess() {
        var profile: JSONObject = [
            "username": "Joannis"
        ]
        
        var user: JSONObject = [
            "profile": profile
        ]
        
        XCTAssertEqual(user["profile"]?["username"] as? String, "Joannis")
        
        profile["username"] = "Henk"
        XCTAssertEqual(profile["username"].string, "Henk")
        
        user["profile"] = profile
        XCTAssertEqual(user["profile"]?["username"] as? String, "Henk")
        
        user["profile"] = nil
        XCTAssertNil(user["profile"])
        XCTAssertNil(user["profile"]?["username"])
        
        user["profile"] = true
        XCTAssertEqual(user["profile"] as? Bool, true)
        XCTAssertNil(user["profile"]?["username"])
        
        user["profile"] = profile
        XCTAssertEqual(user["profile"]?["username"] as? String, "Henk")
    }
    
    func testNestedArrayInObjectAccess() {
        
    }
    
    func testArrayAccess() {
        
    }
    
    func testNestedObjectInArrayAccess() {
        
    }
    
    func testNestedArrayInArrayAccess() {
        
    }

    func testDecodeArrayOfBool() throws {
        let data = zip(Array(repeating: true, count: 10), Array(repeating: false, count: 10)).flatMap { [$0, $1] }
        struct Foo: Codable {
            let bools: [Bool]
            init(bools: [Bool]) { self.bools = bools }
            init(from decoder: Decoder) throws {
                // N.B.: Decoding `Array<Bool>` from a singleValueContainer() does not exercise the
                // unkeyed container codepath.
                var container = try decoder.unkeyedContainer()
                var bools: [Bool] = []
                while !container.isAtEnd { bools.append(try container.decode(Bool.self)) }
                self.bools = bools
            }
            func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                try self.bools.forEach { try container.encode($0) }
            }
        }
        let encoded = try IkigaJSONEncoder().encode(Foo(bools: data))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "[true,false,true,false,true,false,true,false,true,false,true,false,true,false,true,false,true,false,true,false]")

        let decoded = try IkigaJSONDecoder().decode(Foo.self, from: encoded)
        XCTAssertEqual(decoded.bools, data)
    }
    
    struct NestedByUsingSuper: Codable {
        struct NestedWithinUsingSuper: Codable, Equatable { let bar: String }

        private enum CodingKeys: String, CodingKey { case foo, parent, unkeyed }

        let foo: Int, `super`: NestedWithinUsingSuper, parent: NestedWithinUsingSuper
        let unkeyed: (Bool, NestedWithinUsingSuper)
        
        init(foo: Int, barSuper: String, barParent: String, flag: Bool, barNumbered: String) {
            self.foo = foo
            self.super = .init(bar: barSuper)
            self.parent = .init(bar: barParent)
            self.unkeyed = (flag, .init(bar: barNumbered))
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.foo = try container.decode(Int.self, forKey: .foo)
            self.super = try .init(from: container.superDecoder())
            self.parent = try .init(from: container.superDecoder(forKey: .parent))
            var unkeyedContainer = try container.nestedUnkeyedContainer(forKey: .unkeyed)
            self.unkeyed = try (unkeyedContainer.decode(Bool.self), .init(from: unkeyedContainer.superDecoder()))
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.foo, forKey: .foo)
            try self.super.encode(to: container.superEncoder())
            try self.parent.encode(to: container.superEncoder(forKey: .parent))
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .unkeyed)
            try unkeyedContainer.encode(self.unkeyed.0)
            try self.unkeyed.1.encode(to: unkeyedContainer.superEncoder())
        }
    }
    
    func testSuperEncoderDecoderUsage() throws {
        let raw = NestedByUsingSuper(foo: 5, barSuper: "super bar", barParent: "parent bar", flag: true, barNumbered: "number your days")
        let encoded = try IkigaJSONEncoder().encode(raw)
        let decoded = try IkigaJSONDecoder().decode(NestedByUsingSuper.self, from: encoded)
        
        XCTAssertEqual(raw.foo, decoded.foo)
        XCTAssertEqual(raw.super, decoded.super)
        XCTAssertEqual(raw.parent, decoded.parent)
        XCTAssertEqual(raw.unkeyed.0, decoded.unkeyed.0)
        XCTAssertEqual(raw.unkeyed.1, decoded.unkeyed.1)
    }
    
    func testNilValueEncodingStrategies() throws {
        struct Foo: Codable, Equatable {
            let foo1: Int?
            let foo2: Int?
            let foo3: Int?
            
            private enum CodingKeys: String, CodingKey { case foo1, foo2, foo3 }
            
            init(_ foo1: Int?, _ foo2: Int?, _ foo3: Int?) {
                self.foo1 = foo1
                self.foo2 = foo2
                self.foo3 = foo3
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                self.foo1 = try container.decodeIfPresent(Int.self, forKey: .foo1)
                self.foo2 = try container.decodeNil(forKey: .foo2) ? nil : container.decode(Int.self, forKey: .foo2)
                self.foo3 = try container.decode(Int?.self, forKey: .foo3)
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                
                try container.encodeIfPresent(self.foo1, forKey: .foo1)
                try self.foo2.map { try container.encode($0, forKey: .foo2) } ?? container.encodeNil(forKey: .foo2)
                try container.encode(self.foo3, forKey: .foo3)
            }
        }
        
        let foob1 = Foo(0, 0, 0)
        let foob2 = Foo(nil, 0, 0)
        let foob3 = Foo(0, nil, 0)
        let foob4 = Foo(0, 0, nil)
        var encoder = IkigaJSONEncoder()
        
        encoder.settings.nilValueEncodingStrategy = .default
        XCTAssertEqual(String(decoding: try encoder.encode(foob1), as: UTF8.self), #"{"foo1":0,"foo2":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob2), as: UTF8.self), #"{"foo2":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob3), as: UTF8.self), #"{"foo1":0,"foo2":null,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob4), as: UTF8.self), #"{"foo1":0,"foo2":0,"foo3":null}"#)

        encoder.settings.nilValueEncodingStrategy = .alwaysEncodeNil
        XCTAssertEqual(String(decoding: try encoder.encode(foob1), as: UTF8.self), #"{"foo1":0,"foo2":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob2), as: UTF8.self), #"{"foo1":null,"foo2":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob3), as: UTF8.self), #"{"foo1":0,"foo2":null,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob4), as: UTF8.self), #"{"foo1":0,"foo2":0,"foo3":null}"#)

        encoder.settings.nilValueEncodingStrategy = .neverEncodeNil
        XCTAssertEqual(String(decoding: try encoder.encode(foob1), as: UTF8.self), #"{"foo1":0,"foo2":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob2), as: UTF8.self), #"{"foo2":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob3), as: UTF8.self), #"{"foo1":0,"foo3":0}"#)
        XCTAssertEqual(String(decoding: try encoder.encode(foob4), as: UTF8.self), #"{"foo1":0,"foo2":0}"#)
        
        var decoder = IkigaJSONDecoder()

        decoder.settings.nilValueDecodingStrategy = .default
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":0,"foo3":0}"#)), foob1)
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo2":0,"foo3":0}"#)), foob2)
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":null,"foo3":0}"#)), foob3)
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":0,"foo3":null}"#)), foob4)

        decoder.settings.nilValueDecodingStrategy = .decodeNilForKeyNotFound
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":0,"foo3":0}"#)), foob1)
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":null,"foo2":0,"foo3":0}"#)), foob2)
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":null,"foo3":0}"#)), foob3)
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":0,"foo3":null}"#)), foob4)

        decoder.settings.nilValueDecodingStrategy = .treatNilValuesAsMissing
        XCTAssertEqual(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":0,"foo3":0}"#)), foob1)
        XCTAssertThrowsError(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo2":0,"foo3":0}"#)))
        XCTAssertThrowsError(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo3":0}"#)))
        XCTAssertThrowsError(try decoder.decode(Foo.self, from: ByteBuffer(string: #"{"foo1":0,"foo2":0}"#)))
    }

    /// Test for lastKeySearchHint not being reset in nested objects.
    /// This test demonstrates a potential optimization inefficiency where subDecoders inherit
    /// the parent's lastKeySearchHint, which points to an invalid offset in the child's context.
    ///
    /// The issue occurs in the subDecoder(offsetBy:) method which doesn't reset lastKeySearchHint.
    /// When a parent decoder has accessed several keys sequentially (setting lastKeySearchHint
    /// to point after the last accessed key), and then creates a sub-decoder for a nested object,
    /// the child decoder inherits this hint value. This hint points to an offset in the parent's
    /// index space, which is invalid for the child's index space.
    ///
    /// While the current implementation has wraparound logic that prevents incorrect results,
    /// the inherited hint causes unnecessary wraparound searches, reducing the efficiency
    /// of the sequential access optimization.
    func testNestedObjectKeyLookupHintReset() throws {
        struct Parent: Codable, Equatable {
            let firstKey: String
            let secondKey: String
            let thirdKey: String
            let nested: Nested
            let fourthKey: String
            
            struct Nested: Codable, Equatable {
                let nestedFirstKey: String
                let nestedSecondKey: String
                let nestedThirdKey: String
            }
        }
        
        // Create a JSON with nested objects where the parent has multiple keys
        // before the nested object, setting up the lastKeySearchHint
        let json = """
        {
            "firstKey": "value1",
            "secondKey": "value2",
            "thirdKey": "value3",
            "nested": {
                "nestedFirstKey": "nestedValue1",
                "nestedSecondKey": "nestedValue2",
                "nestedThirdKey": "nestedValue3"
            },
            "fourthKey": "value4"
        }
        """.data(using: .utf8)!
        
        let expected = Parent(
            firstKey: "value1",
            secondKey: "value2",
            thirdKey: "value3",
            nested: Parent.Nested(
                nestedFirstKey: "nestedValue1",
                nestedSecondKey: "nestedValue2",
                nestedThirdKey: "nestedValue3"
            ),
            fourthKey: "value4"
        )
        
        let decoder = IkigaJSONDecoder()
        let result = try decoder.decode(Parent.self, from: json)
        
        // Verifies correct decoding despite optimization inefficiency.
        // The nested decoder ideally should start with hint = Constants.firstArrayObjectChildOffset (17),
        // rather than inheriting the parent's hint which points to an offset in the parent's context.
        XCTAssertEqual(result, expected)
        
        // Test with deeply nested structures to further verify the behavior
        struct DeeplyNested: Codable, Equatable {
            let a: String
            let b: String
            let level1: Level1
            
            struct Level1: Codable, Equatable {
                let c: String
                let d: String
                let level2: Level2
                
                struct Level2: Codable, Equatable {
                    let e: String
                    let f: String
                    let level3: Level3
                    
                    struct Level3: Codable, Equatable {
                        let g: String
                        let h: String
                    }
                }
            }
        }
        
        let deeplyNestedJson = """
        {
            "a": "value_a",
            "b": "value_b",
            "level1": {
                "c": "value_c",
                "d": "value_d",
                "level2": {
                    "e": "value_e",
                    "f": "value_f",
                    "level3": {
                        "g": "value_g",
                        "h": "value_h"
                    }
                }
            }
        }
        """.data(using: .utf8)!
        
        let expectedDeep = DeeplyNested(
            a: "value_a",
            b: "value_b",
            level1: DeeplyNested.Level1(
                c: "value_c",
                d: "value_d",
                level2: DeeplyNested.Level1.Level2(
                    e: "value_e",
                    f: "value_f",
                    level3: DeeplyNested.Level1.Level2.Level3(
                        g: "value_g",
                        h: "value_h"
                    )
                )
            )
        )
        
        let resultDeep = try decoder.decode(DeeplyNested.self, from: deeplyNestedJson)
        
        // Verifies correct decoding with deeply nested structures.
        // Each nested level inherits the parent's hint, potentially causing
        // progressively less optimal lookups as we go deeper.
        XCTAssertEqual(resultDeep, expectedDeep)
    }
    
    func testEmptyObjectKey() throws {
        // Test case for potential bug: empty keys (keyLength = 0) cause invalid range 1...0
        // This tests the hash computation loop in JSONParser+Parsing.swift line 331
        let json = """
        {"": "value"}
        """.data(using: .utf8)!
        
        // This should not crash with "Fatal error: Can't form Range with upperBound < lowerBound"
        XCTAssertNoThrow(try JSONObject(data: json))
        
        // Verify the object can be decoded and contains the empty key
        let object = try JSONObject(data: json)
        XCTAssertEqual(object[""] as? String, "value")
    }
}
