import XCTest
import Foundation
@testable import Officer

var newParser: OfficerJSONDecoder {
    return OfficerJSONDecoder()
//var newParser: Foundation.JSONDecoder {
//    return Foundation.JSONDecoder()
}

final class JSONTests: XCTestCase {
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
        
        measure {
            for _ in 0..<10_000 {
                let user = try! newParser.decode(User.self, from: json)
                
                XCTAssertEqual(user.id, "0")
                XCTAssertEqual(user.username, "Joannis")
                XCTAssertEqual(user.role, "admin")
                XCTAssertTrue(user.awesome)
                XCTAssertFalse(user.superAwesome)
            }
        }
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
        
        measure {
            for _ in 0..<10_000 {
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
        }
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
        
        measure {
            for _ in 0..<10_000 {
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
        }
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
        
        measure {
            for _ in 0..<10_000 {
                let stuff = try! newParser.decode(Stuff.self, from: json)
                
                XCTAssertEqual(stuff.piD, 3.14)
                XCTAssertEqual(stuff.piF, 3.14)
                XCTAssertEqual(stuff.u8, 255)
                XCTAssertEqual(stuff.u8zero, 0)
                XCTAssertEqual(stuff.i8, -127)
                XCTAssertEqual(stuff.imax, .max)
                XCTAssertEqual(stuff.imin, .min)
            }
        }
    }
    
    func testBasic() throws {
        let json = """
        {
            "id": "0",
            "username": "Joannis",
            "role": "admin",
            "awesome": true,
            "superAwesome": false
        }
        """
        
        let bytes = [UInt8](json.utf8)
        let desc = try JSONParser.scanValue(fromPointer: bytes, count: bytes.count)
        
        guard case .object(let object) = desc.storage else {
            XCTFail("Not an object")
            return
        }
        
        XCTAssertEqual(object.pairs.count, 5)
        
        let keys = object.pairs.compactMap { (key, _) in
            return key.makeString(from: bytes)
        }
        
        XCTAssertEqual(keys, ["id", "username", "role", "awesome", "superAwesome"])
        
        if case .string(let string) = object.pairs[0].value.storage {
            XCTAssertEqual(string.makeString(from: bytes), "0")
        } else {
            XCTFail("Not a string")
        }
        
        if case .string(let string) = object.pairs[1].value.storage {
            XCTAssertEqual(string.makeString(from: bytes), "Joannis")
        } else {
            XCTFail("Not a string")
        }
        
        if case .string(let string) = object.pairs[2].value.storage {
            XCTAssertEqual(string.makeString(from: bytes), "admin")
        } else {
            XCTFail("Not a string")
        }
        
        guard object.pairs[3].value.bool == true else {
            return XCTFail("Not true")
        }
        
        guard object.pairs[4].value.bool == false else {
            return XCTFail("Not a bool")
        }
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
        
        measure {
            for _ in 0..<10_000 {
                _ = try! newParser.decode(User.self, from: data)
            }
        }
    }
    
    static var allTests = [
        ("testBasic", testBasic),
        ("testObject", testObject),
        ("testArray", testArray),
        ("testEscaping", testEscaping),
        ("testNumerical", testNumerical),
        ("testCodablePerformance", testCodablePerformance),
    ]
}
