import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(CSVTests.allTests),
        testCase(JSONTests.allTests),
    ]
}
#endif
