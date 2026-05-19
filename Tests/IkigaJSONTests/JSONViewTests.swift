import Foundation
import XCTest
import IkigaJSON

final class JSONObjectViewTests: XCTestCase {
    func testEmptyObjectParsed() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("{}".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(view.keys, [])
        }
    }

    func testRejectsArrayInput() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[]".utf8)
        do {
            try bytes.withUnsafeBufferPointer { buffer in
                let span = unsafe Span<UInt8>(_unsafeElements: buffer)
                _ = try JSONObjectView(span: span)
            }
            XCTFail("Expected JSONObjectError.expectedObject")
        } catch JSONObjectError.expectedObject {
            // Expected
        }
    }

    func testRejectsInvalidJSON() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("{invalid}".utf8)
        do {
            try bytes.withUnsafeBufferPointer { buffer in
                let span = unsafe Span<UInt8>(_unsafeElements: buffer)
                _ = try JSONObjectView(span: span)
            }
            XCTFail("Expected parsing error")
        } catch is JSONObjectError {
            // Expected
        }
    }

    func testKeys() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis","age":42}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(Set(view.keys), ["name", "age"])
        }
    }

    func testStringValue() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(try view.string(forKey: "name"), "Joannis")
            XCTAssertNil(try view.string(forKey: "missing"))
        }
    }

    func testStringValueForNonStringKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"age":42}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertNil(try view.string(forKey: "age"))
        }
    }

    func testEscapedStringValue() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"message":"Hello\nWorld"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(try view.string(forKey: "message"), "Hello\nWorld")
        }
    }

    func testIntegerValue() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"count":42}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(try view.integer(forKey: "count"), 42)
            XCTAssertNil(try view.integer(forKey: "missing"))
        }
    }

    func testIntegerValueForNonIntegerKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertNil(try view.integer(forKey: "name"))
        }
    }

    func testDoubleValue() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"pi":3.14}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(try view.double(forKey: "pi")!, 3.14, accuracy: 0.001)
            XCTAssertNil(try view.double(forKey: "missing"))
        }
    }

    func testBooleanValues() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"active":true,"deleted":false}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(try view.boolean(forKey: "active"), true)
            XCTAssertEqual(try view.boolean(forKey: "deleted"), false)
            XCTAssertNil(try view.boolean(forKey: "missing"))
        }
    }

    func testBooleanValueForNonBoolKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"count":42}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertNil(try view.boolean(forKey: "count"))
        }
    }

    func testIsNullValue() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"value":null,"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertTrue(try view.isNull(forKey: "value"))
            XCTAssertFalse(try view.isNull(forKey: "name"))
            XCTAssertFalse(try view.isNull(forKey: "missing"))
        }
    }

    func testSubscriptReturnsValues() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis","age":42,"active":true}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(view["name"] as? String, "Joannis")
            XCTAssertEqual(view["age"] as? Int, 42)
            XCTAssertEqual(view["active"] as? Bool, true)
            XCTAssertNil(view["missing"])
        }
    }

    func testSubscriptReturnsNullAsNSNull() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"value":null}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssert(view["value"] is NSNull)
        }
    }

    func testData() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let json = #"{"name":"Joannis"}"#
        let bytes: [UInt8] = Array(json.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            XCTAssertEqual(view.data, Data(json.utf8))
        }
    }

    func testWithObjectViewForNestedObject() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"user":{"name":"Joannis","age":42}}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            let keyCount = try view.withObjectView(forKey: "user") { $0.keys.count }
            XCTAssertEqual(keyCount, 2)
        }
    }

    func testWithObjectViewReturnsNilForMissingKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            let result = try view.withObjectView(forKey: "missing") { $0.keys.count }
            XCTAssertNil(result)
        }
    }

    func testWithObjectViewReturnsNilForNonObjectKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            let result = try view.withObjectView(forKey: "name") { $0.keys.count }
            XCTAssertNil(result)
        }
    }

    func testWithArrayViewForNestedArray() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"tags":["swift","json","parsing"]}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            let count = try view.withArrayView(forKey: "tags") { $0.count }
            XCTAssertEqual(count, 3)
        }
    }

    func testWithArrayViewReturnsNilForMissingKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            let result = try view.withArrayView(forKey: "missing") { $0.count }
            XCTAssertNil(result)
        }
    }

    func testWithArrayViewReturnsNilForNonArrayKey() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"{"name":"Joannis"}"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONObjectView(span: span)
            let result = try view.withArrayView(forKey: "name") { $0.count }
            XCTAssertNil(result)
        }
    }
}

final class JSONArrayViewTests: XCTestCase {
    func testEmptyArrayParsed() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view.count, 0)
        }
    }

    func testRejectsObjectInput() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("{}".utf8)
        do {
            try bytes.withUnsafeBufferPointer { buffer in
                let span = unsafe Span<UInt8>(_unsafeElements: buffer)
                _ = try JSONArrayView(span: span)
            }
            XCTFail("Expected JSONArrayError.expectedArray")
        } catch JSONArrayError.expectedArray {
            // Expected
        }
    }

    func testRejectsInvalidJSON() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[invalid]".utf8)
        do {
            try bytes.withUnsafeBufferPointer { buffer in
                let span = unsafe Span<UInt8>(_unsafeElements: buffer)
                _ = try JSONArrayView(span: span)
            }
            XCTFail("Expected parsing error")
        } catch is JSONArrayError {
            // Expected
        }
    }

    func testCount() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[1,2,3,4,5]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view.count, 5)
        }
    }

    func testStringElements() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"["hello","world"]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view[0] as? String, "hello")
            XCTAssertEqual(view[1] as? String, "world")
        }
    }

    func testIntegerElements() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[1,2,3]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view[0] as? Int, 1)
            XCTAssertEqual(view[1] as? Int, 2)
            XCTAssertEqual(view[2] as? Int, 3)
        }
    }

    func testDoubleElements() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[3.14,2.71]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual((view[0] as? Double)!, 3.14, accuracy: 0.001)
            XCTAssertEqual((view[1] as? Double)!, 2.71, accuracy: 0.001)
        }
    }

    func testBoolElements() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[true,false,true]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view[0] as? Bool, true)
            XCTAssertEqual(view[1] as? Bool, false)
            XCTAssertEqual(view[2] as? Bool, true)
        }
    }

    func testNullElement() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[null]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssert(view[0] is NSNull)
        }
    }

    func testMixedElements() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"["hello",42,true,null,3.14]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view.count, 5)
            XCTAssertEqual(view[0] as? String, "hello")
            XCTAssertEqual(view[1] as? Int, 42)
            XCTAssertEqual(view[2] as? Bool, true)
            XCTAssert(view[3] is NSNull)
            XCTAssertEqual((view[4] as? Double)!, 3.14, accuracy: 0.001)
        }
    }

    func testData() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let json = "[1,2,3]"
        let bytes: [UInt8] = Array(json.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view.data, Data(json.utf8))
        }
    }

    func testNestedObjectElement() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"[{"name":"Joannis","age":42}]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            let obj = view[0] as? JSONObject
            XCTAssertNotNil(obj)
            XCTAssertEqual(obj?["name"] as? String, "Joannis")
            XCTAssertEqual(obj?["age"] as? Int, 42)
        }
    }

    func testNestedArrayElement() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[[1,2],[3,4]]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(view.count, 2)
            let inner = view[0] as? JSONArray
            XCTAssertNotNil(inner)
            XCTAssertEqual(inner?.count, 2)
            XCTAssertEqual(inner?[0] as? Int, 1)
            XCTAssertEqual(inner?[1] as? Int, 2)
        }
    }

    // MARK: - Typed index-based API

    func testStringForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"["hello","world"]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(try view.string(forIndex: 0), "hello")
            XCTAssertEqual(try view.string(forIndex: 1), "world")
        }
    }

    func testStringForIndexWithEscaping() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"["Hello\nWorld"]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(try view.string(forIndex: 0), "Hello\nWorld")
        }
    }

    func testStringForIndexReturnsNilForNonString() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[42]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertNil(try view.string(forIndex: 0))
        }
    }

    func testIntegerForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[1,2,3]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(try view.integer(forIndex: 0), 1)
            XCTAssertEqual(try view.integer(forIndex: 2), 3)
        }
    }

    func testIntegerForIndexReturnsNilForNonInteger() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"["hello"]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertNil(try view.integer(forIndex: 0))
        }
    }

    func testDoubleForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[3.14,2.71]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(try view.double(forIndex: 0)!, 3.14, accuracy: 0.001)
            XCTAssertEqual(try view.double(forIndex: 1)!, 2.71, accuracy: 0.001)
        }
    }

    func testDoubleForIndexReturnsNilForNonDouble() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[42]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertNil(try view.double(forIndex: 0))
        }
    }

    func testBooleanForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[true,false]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(try view.boolean(forIndex: 0), true)
            XCTAssertEqual(try view.boolean(forIndex: 1), false)
        }
    }

    func testBooleanForIndexReturnsNilForNonBool() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[42]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertNil(try view.boolean(forIndex: 0))
        }
    }

    func testIsNullForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"[null,"hello"]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            XCTAssertEqual(try view.isNull(forIndex: 0), true)
            XCTAssertEqual(try view.isNull(forIndex: 1), false)
        }
    }

    func testWithObjectViewForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array(#"[{"name":"Joannis","age":42}]"#.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            let keyCount = try view.withObjectView(forIndex: 0) { $0.keys.count }
            XCTAssertEqual(keyCount, 2)
        }
    }

    func testWithObjectViewForIndexReturnsNilForNonObject() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[42]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            let result = try view.withObjectView(forIndex: 0) { $0.keys.count }
            XCTAssertNil(result)
        }
    }

    func testWithArrayViewForIndex() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[[1,2,3]]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            let count = try view.withArrayView(forIndex: 0) { $0.count }
            XCTAssertEqual(count, 3)
        }
    }

    func testWithArrayViewForIndexReturnsNilForNonArray() throws {
        guard #available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires macOS 26 or later")
        }
        let bytes: [UInt8] = Array("[42]".utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            let span = unsafe Span<UInt8>(_unsafeElements: buffer)
            let view = try JSONArrayView(span: span)
            let result = try view.withArrayView(forIndex: 0) { $0.count }
            XCTAssertNil(result)
        }
    }
}
