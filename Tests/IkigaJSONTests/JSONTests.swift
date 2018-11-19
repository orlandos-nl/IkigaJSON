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
            let u8: UInt8
            let u8zero: UInt8
            let i8: Int8
            let imax: Int32
            let imin: Int32
        }
        
        let stuff = try newParser.decode(Stuff.self, from: json)
        
        XCTAssertEqual(stuff.piD, 3.14)
        XCTAssertEqual(stuff.piF, 3.14)
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
    
    static var allTests = [
        ("testObject", testObject),
        ("testArray", testArray),
        ("testEscaping", testEscaping),
        ("testNumerical", testNumerical),
        ("testCodablePerformance", testCodablePerformance),
    ]
}
