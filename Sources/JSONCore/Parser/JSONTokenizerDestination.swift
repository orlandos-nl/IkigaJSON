public protocol JSONTokenizerDestination {
    associatedtype ArrayStartContext
    associatedtype ObjectStartContext

    mutating func arrayStartFound(_ start: JSONToken.ArrayStart) -> ArrayStartContext
    mutating func arrayEndFound(_ end: JSONToken.ArrayEnd, context: consuming ArrayStartContext)

    mutating func objectStartFound(_ start: JSONToken.ObjectStart) -> ObjectStartContext
    mutating func objectEndFound(_ end: JSONToken.ObjectEnd, context: consuming ObjectStartContext)

    mutating func booleanTrueFound(_ boolean: JSONToken.BooleanTrue)
    mutating func booleanFalseFound(_ boolean: JSONToken.BooleanFalse)
    mutating func nullFound(_ null: JSONToken.Null)
    mutating func stringFound(_ string: JSONToken.String)
    mutating func numberFound(_ number: JSONToken.Number)
}

public enum JSONToken: Sendable, Hashable {
    case arrayStart(ArrayStart)
    case arrayEnd(ArrayEnd)
    case objectStart(ObjectStart)
    case objectEnd(ObjectEnd)
    case booleanTrue(BooleanTrue)
    case booleanFalse(BooleanFalse)
    case null(Null)
    case number(Number)
    case string(String)

    public struct Number: Sendable, Hashable {
        public let start: JSONSourcePosition
        public let end: JSONSourcePosition
        public let isInteger: Bool

        @inlinable public var byteLength: Int {
            end.byteOffset &- start.byteOffset
        }

        package init(start: JSONSourcePosition, end: JSONSourcePosition, isInteger: Bool) {
            self.start = start
            self.end = end
            self.isInteger = isInteger
        }

        package init(start: JSONSourcePosition, byteLength: Int, isInteger: Bool) {
            self.start = start
            self.end = JSONSourcePosition(byteIndex: start.byteOffset + byteLength)
            self.isInteger = isInteger
        }
    }

    public struct String: Sendable, Hashable {
        public let start: JSONSourcePosition
        public let end: JSONSourcePosition
        public let usesEscaping: Bool

        @inlinable public var byteLength: Int {
            end.byteOffset &- start.byteOffset
        }

        package init(start: JSONSourcePosition, byteLength: Int, usesEscaping: Bool) {
            self.start = start
            self.end = JSONSourcePosition(byteIndex: start.byteOffset + byteLength)
            self.usesEscaping = usesEscaping
        }

        package init(start: JSONSourcePosition, end: JSONSourcePosition, usesEscaping: Bool) {
            self.start = start
            self.end = end
            self.usesEscaping = usesEscaping
        }
    }

    public struct BooleanTrue: Sendable, Hashable {
        public let start: JSONSourcePosition

        @inlinable public var end: JSONSourcePosition {
            JSONSourcePosition(byteIndex: start.byteOffset &+ byteLength)
        }
        public let byteLength = 4

        package init(start: JSONSourcePosition) {
            self.start = start
        }
    }

    public struct Null: Sendable, Hashable {
        public let start: JSONSourcePosition

        @inlinable public var end: JSONSourcePosition {
            JSONSourcePosition(byteIndex: start.byteOffset &+ byteLength)
        }
        public let byteLength = 4

        package init(start: JSONSourcePosition) {
            self.start = start
        }
    }

    public struct BooleanFalse: Sendable, Hashable {
        public let start: JSONSourcePosition

        @inlinable public var end: JSONSourcePosition {
            JSONSourcePosition(byteIndex: start.byteOffset &+ byteLength)
        }
        public let byteLength = 5

        package init(start: JSONSourcePosition) {
            self.start = start
        }
    }

    public struct ArrayStart: Sendable, Hashable {
        public let start: JSONSourcePosition

        package init(start: JSONSourcePosition) {
            self.start = start
        }
    }

    public struct ArrayEnd: Sendable, Hashable {
        public let start: JSONSourcePosition
        public let end: JSONSourcePosition
        public let memberCount: Int

        @inlinable public var byteLength: Int {
            end.byteOffset &- start.byteOffset
        }

        package init(start: JSONSourcePosition, end: JSONSourcePosition, memberCount: Int) {
            self.start = start
            self.end = end
            self.memberCount = memberCount
        }
    }

    public struct ObjectStart: Sendable, Hashable {
        public let start: JSONSourcePosition

        package init(start: JSONSourcePosition) {
            self.start = start
        }
    }

    public struct ObjectEnd: Sendable, Hashable {
        public let start: JSONSourcePosition
        public let end: JSONSourcePosition
        public let memberCount: Int

        @inlinable public var byteLength: Int {
            end.byteOffset &- start.byteOffset
        }

        package init(start: JSONSourcePosition, end: JSONSourcePosition, memberCount: Int) {
            self.start = start
            self.end = end
            self.memberCount = memberCount
        }
    }
}

public struct JSONSourcePosition: Sendable, Hashable {
    public let byteOffset: Int

    @usableFromInline package init(byteIndex: Int) {
        self.byteOffset = byteIndex
    }
}
