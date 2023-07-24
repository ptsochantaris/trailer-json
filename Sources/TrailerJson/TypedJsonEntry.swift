import Foundation

public extension TypedJson {
    enum Entry {
        case int(TypedJson, from: Int, to: Int),
             float(TypedJson, from: Int, to: Int),
             bool(TypedJson, from: Int, to: Int),
             string(TypedJson, from: Int, to: Int),
             object([String: Entry]),
             array([Entry])
        
        private var typeName: String {
            switch self {
                
            case .int:
                return "Int"
            case .float:
                return "Float"
            case .bool:
                return "Bool"
            case .string:
                return "String"
            case .object:
                return "Object"
            case .array:
                return "Array"
            }
        }

        public var parsed: Any {
            get throws {
                switch self {
                case let .int(buffer, from, to):
                    return try buffer.slice(from, to).asInt
                case let .float(buffer, from, to):
                    return try buffer.slice(from, to).asFloat
                case let .bool(buffer, from, _):
                    return buffer.byte(at: from) == ._charT
                case let .string(buffer, from, to):
                    return try buffer.slice(from, to).asUnescapedString
                case let .array(list):
                    return try list.map { try $0.parsed }
                case let .object(fields):
                    return try fields.mapValues { try $0.parsed }
                }
            }
        }

        public var asInt: Int {
            get throws {
                if case let .int(buffer, from, to) = self {
                    return try buffer.slice(from, to).asInt
                }
                throw JSONError.incorrectTypeRequested(requested: "Int", detected: typeName)
            }
        }

        public var asFloat: Float {
            get throws {
                if case let .float(buffer, from, to) = self {
                    return try buffer.slice(from, to).asFloat
                }
                throw JSONError.incorrectTypeRequested(requested: "Float", detected: typeName)
            }
        }

        public var asBool: Bool {
            get throws {
                if case let .bool(buffer, from, _) = self {
                    return buffer.byte(at: from) == ._charT
                }
                throw JSONError.incorrectTypeRequested(requested: "Bool", detected: typeName)
            }
        }

        public var asString: String {
            get throws {
                if case let .string(buffer, from, to) = self {
                    return try buffer.slice(from, to).asUnescapedString
                }
                throw JSONError.incorrectTypeRequested(requested: "String", detected: typeName)
            }
        }

        public subscript(named: String) -> Entry {
            get throws {
                if case let .object(fields) = self {
                    if let entry = fields[named] {
                        return entry
                    }
                    throw JSONError.fieldNotFound(field: named)
                }
                throw JSONError.incorrectTypeRequested(requested: "Object", detected: typeName)
            }
        }

        public subscript(index: Int) -> Entry {
            get throws {
                if case let .array(items) = self, index >= 0, index < items.count {
                    return items[index]
                }
                throw JSONError.incorrectTypeRequested(requested: "Array", detected: typeName)
            }
        }

        public var asArray: [Entry] {
            get throws {
                if case let .array(items) = self {
                    return items
                }
                throw JSONError.incorrectTypeRequested(requested: "Array", detected: typeName)
            }
        }

        public var keys: [String] {
            get throws {
                if case let .object(fields) = self {
                    return Array(fields.keys)
                }
                throw JSONError.incorrectTypeRequested(requested: "Object", detected: typeName)
            }
        }
    }
}
