import Foundation

public extension TypedJson {
    enum Entry {
        case int(TypedJson, from: Int, to: Int),
             float(TypedJson, from: Int, to: Int),
             bool(TypedJson, from: Int, to: Int),
             string(TypedJson, from: Int, to: Int),
             object([String: Entry]),
             array([Entry])

        public var parsed: Any? {
            switch self {
            case let .int(buffer, from, to):
                return buffer.slice(from, to).asInt
            case let .float(buffer, from, to):
                return buffer.slice(from, to).asFloat
            case let .bool(buffer, from, _):
                return buffer.byte(at: from) == ._charT
            case let .string(buffer, from, to):
                return buffer.slice(from, to).asUnescapedString
            case let .array(list):
                return list.compactMap(\.parsed)
            case let .object(fields):
                return fields.mapValues(\.parsed)
            }
        }

        public var asInt: Int? {
            if case let .int(buffer, from, to) = self {
                return buffer.slice(from, to).asInt
            }
            return nil
        }

        public var asFloat: Float? {
            if case let .float(buffer, from, to) = self {
                return buffer.slice(from, to).asFloat
            }
            return nil
        }

        public var asBool: Bool? {
            if case let .bool(buffer, from, _) = self {
                return buffer.byte(at: from) == ._charT
            }
            return nil
        }

        public var asString: String? {
            if case let .string(buffer, from, to) = self {
                return buffer.slice(from, to).asUnescapedString
            }
            return nil
        }

        public subscript(named: String) -> Entry? {
            if case let .object(fields) = self {
                return fields[named]
            }
            return nil
        }

        public subscript(index: Int) -> Entry? {
            if case let .array(items) = self, index >= 0, index < items.count {
                return items[index]
            }
            return nil
        }

        public var asArray: [Entry]? {
            if case let .array(items) = self {
                return items
            }
            return nil
        }

        public var keys: [String]? {
            if case let .object(fields) = self {
                return Array(fields.keys)
            }
            return nil
        }
    }
}
