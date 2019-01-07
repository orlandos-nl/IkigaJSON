import XCTest
import Foundation
import IkigaJSON

var newParser: IkigaJSONDecoder {
    return IkigaJSONDecoder()
}

var newEncoder: IkigaJSONEncoder {
    return IkigaJSONEncoder()
}

final class IkigaJSONTests: XCTestCase {
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
    
    func testKeyDecoding() throws {
        let parser = newParser
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
    
    func testJSONObject() throws {
        let json = """
        {
            "id": "0",
            "username": "Joannis",
            "role": "admin",
            "awesome": true,
            "superAwesome": false
        }
        """.data(using: .utf8)!
        
        let object = try JSONObject(data: json)
        XCTAssertEqual(object["id"].string, "0")
        XCTAssertEqual(object["username"].string, "Joannis")
        XCTAssertEqual(object["role"].string, "admin")
        XCTAssertEqual(object["awesome"].bool, true)
        XCTAssertEqual(object["superAwesome"].bool, false)
        
        XCTAssertNil(object["ID"])
        XCTAssertNil(object["user_name"])
        XCTAssertNil(object["test"])
    }
    
    func testJSONArray() throws {
        let json = """
        [0,1,2,true,"false"]
        """.data(using: .utf8)!
        
        let array = try JSONArray(data: json)
        XCTAssertEqual(array[0].int, 0)
        XCTAssertEqual(array[1].int, 1)
        XCTAssertEqual(array[2].int, 2)
        XCTAssertEqual(array[3].bool, true)
        XCTAssertEqual(array[4].string, "false")
        
        XCTAssertNil(array[4].bool)
    }
    
    func testNestedJSONObject() throws {
        let json = """
        {
            "id": "0",
            "username": "Joannis",
            "roles": ["admin", "user"],
            "awesome": true,
            "details": {
                "pet": "Noodles"
            },
            "superAwesome": false
        }
        """.data(using: .utf8)!
        
        let object = try JSONObject(data: json)
        XCTAssertEqual(object["id"].string, "0")
        XCTAssertEqual(object["username"].string, "Joannis")
        XCTAssertEqual(object["roles"][0].string, "admin")
        XCTAssertEqual(object["roles"][1].string, "user")
        XCTAssertEqual(object["details"]["pet"].string, "Noodles")
        XCTAssertEqual(object["awesome"].bool, true)
        XCTAssertEqual(object["superAwesome"].bool, false)
        
        XCTAssertNil(object["ID"])
        XCTAssertNil(object["user_name"])
        XCTAssertNil(object["test"])
        XCTAssertNil(object["roles"]["admin"])
        XCTAssertNil(object["roles"]["details"]["hoi"])
        XCTAssertNil(object["roles"]["details"][5])
        XCTAssertNil(object["roles"]["details"][0])
    }
    
    func testNestedJSONArray() throws {
        let json = """
        [0,1,[1,true,true,"hoi"],{"name":"Klaas"},"false"]
        """.data(using: .utf8)!
        
        let array = try JSONArray(data: json)
        XCTAssertEqual(array[0].int, 0)
        XCTAssertEqual(array[1].int, 1)
        XCTAssertNotNil(array[2].array)
        XCTAssertEqual(array[2][0].int, 1)
        XCTAssertEqual(array[2][1].bool, true)
        XCTAssertEqual(array[2][2].bool, true)
        XCTAssertEqual(array[2][3].string, "hoi")
        XCTAssertEqual(array[3]["name"].string, "Klaas")
        XCTAssertEqual(array[4].string, "false")
        
        XCTAssertNil(array[4].bool)
        XCTAssertNil(array[3]["henk"])
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
        
        let user = try! newParser.decode(User.self, from: json)
        
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
        
        let user = try! newParser.decode(User.self, from: json)
        
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
    
    @available(OSX 10.12, *)
    func testISO8601DateStrategy() throws {
        let decoder = newParser
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
    
    @available(OSX 10.12, *)
    func testEpochSecDateStrategy() throws {
        let decoder = newParser
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
    
    @available(OSX 10.12, *)
    func testEpochMSDateStrategy() throws {
        let decoder = newParser
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
        let json = """
        {
            "id": "0",
            "username": "Joannis\\tis\\nawesome\\/\\\\\\"",
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
        
        let user = try! newParser.decode(User.self, from: json)
        
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
    
    func testCodablePerformance() throws {
        let data = """
        {
            "awesome": true,
            "superAwesome": false
        }
        """.data(using: .utf8)!
        
        struct User: Decodable {
            let awesome: Bool
            let superAwesome: Bool
        }
        
        _ = try! newParser.decode(User.self, from: data)
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
    }
    
    func testNestedObjectAccess() {
        var profile: JSONObject = [
            "username": "Joannis"
        ]
        
        var user: JSONObject = [
            "profile": profile
        ]
        
        XCTAssertEqual(user["profile"]["username"] as? String, "Joannis")
        
        profile["username"] = "Henk"
        user["profile"] = profile
        
        XCTAssertEqual(user["profile"]["username"] as? String, "Henk")
    }
    
    func testArrayAccess() {
        
    }
    
    func testNestedArrayAccess() {
        
    }
    
    static var allTests = [
        ("testObject", testObject),
        ("testArray", testArray),
        ("testEscaping", testEscaping),
        ("testNumerical", testNumerical),
        ("testCodablePerformance", testCodablePerformance),
    ]
}
