import Foundation

public extension TypedJson {
    /// A node object  that contains the scanned JSON elements at that level.
    enum Entry {
        /// This entry is delimiting an integer
        case int(TypedJson, from: Int, to: Int)
        /// This entry is delimiting a float
        case float(TypedJson, from: Int, to: Int)
        /// This entry is delimiting a boolean
        case bool(TypedJson, from: Int, to: Int)
        /// This entry is delimiting a string
        case string(TypedJson, from: Int, to: Int)
        /// This entry is delimiting a JSON object
        case object([String: Entry])
        /// This entry is delimiting a JSON array
        case array([Entry])

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

        /// The type that the parsed value is expected to be
        var type: Any.Type {
            switch self {
            case .int:
                return Int.self
            case .float:
                return Float.self
            case .bool:
                return Bool.self
            case .string:
                return String.self
            case .object:
                return [String: Any].self
            case .array:
                return [Any].self
            }
        }

        /**
          Returns a parsed version of this item, depending on the type that was parsed. Note that calling this on large object or array values can be slow.
          - Throws: If the value could not be parsed by using its type-specific logic.
         ```
             let numberArray = try byteBuffer.withVeryUnsafeBytes {

                 let numbers = try TypedJson.parse(bytes: $0)

                 // very slow; for cases like these the `TrailerJson` parser is 10x faster!
                 return try numbers.parsed as! [Int]
             }
             let number = numberArray[1]
             print(number)
         ```
         */
        public var parsed: Any {
            get throws {
                switch self {
                case let .int(buffer, from, to):
                    return buffer.slice(from, to).asInt
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

        /// Get an integer.
        /// - Throws: If the parsed value is not this type.
        public var asInt: Int {
            get throws {
                if case let .int(buffer, from, to) = self {
                    return buffer.slice(from, to).asInt
                }
                throw JSONError.incorrectTypeRequested(requested: "Int", detected: typeName)
            }
        }

        /// Get a float.
        /// - Throws: If the parsed value is not this type.
        public var asFloat: Float {
            get throws {
                if case let .float(buffer, from, to) = self {
                    return try buffer.slice(from, to).asFloat
                }
                throw JSONError.incorrectTypeRequested(requested: "Float", detected: typeName)
            }
        }

        /// Get a bool.
        /// - Throws: If the parsed value is not this type.
        public var asBool: Bool {
            get throws {
                if case let .bool(buffer, from, _) = self {
                    return buffer.byte(at: from) == ._charT
                }
                throw JSONError.incorrectTypeRequested(requested: "Bool", detected: typeName)
            }
        }

        /// Get a string.
        /// - Throws: If the parsed value is not this type.
        public var asString: String {
            get throws {
                if case let .string(buffer, from, to) = self {
                    return try buffer.slice(from, to).asUnescapedString
                }
                throw JSONError.incorrectTypeRequested(requested: "String", detected: typeName)
            }
        }

        /// Get an entry for a field.
        /// - Throws: If the parsed item is not an object, or the field does not exist.
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

        /// Get an entry at an array index.
        /// - Throws: If the parsed item is not an array, or the index is out of range.
        public subscript(index: Int) -> Entry {
            get throws {
                if case let .array(items) = self, index >= 0, index < items.count {
                    return items[index]
                }
                throw JSONError.incorrectTypeRequested(requested: "Array", detected: typeName)
            }
        }

        /// Get an array of entries.
        /// - Throws: If the parsed value is not an array.
        public var asArray: [Entry] {
            get throws {
                if case let .array(items) = self {
                    return items
                }
                throw JSONError.incorrectTypeRequested(requested: "Array", detected: typeName)
            }
        }

        /// Get the names of the keys for this object.
        /// - Throws: If the parsed item is not an object, or the field does not exist.
        public var keys: [String] {
            get throws {
                if case let .object(fields) = self {
                    return Array(fields.keys)
                }
                throw JSONError.incorrectTypeRequested(requested: "Object", detected: typeName)
            }
        }

        /// Get an integer.
        /// - Throws: If the parsed value is not this type.
        public var potentialInt: Int? {
            if case let .int(buffer, from, to) = self {
                return buffer.slice(from, to).asInt
            }
            return nil
        }

        /// Get a float, or `nil` if the entry could not be retrieved.
        public var potentialFloat: Float? {
            if case let .float(buffer, from, to) = self {
                return try? buffer.slice(from, to).asFloat
            }
            return nil
        }

        /// Get a bool, or `nil` if the entry could not be retrieved.
        public var potentialBool: Bool? {
            if case let .bool(buffer, from, _) = self {
                return buffer.byte(at: from) == ._charT
            }
            return nil
        }

        /// Get a string, or `nil` if the entry could not be retrieved.
        public var potentialString: String? {
            if case let .string(buffer, from, to) = self {
                return try? buffer.slice(from, to).asUnescapedString
            }
            return nil
        }

        /// Get an entry for a field, or `nil` if the entry could not be retrieved.
        public func potentialObject(named: String) -> Entry? {
            if case let .object(fields) = self, let entry = fields[named] {
                return entry
            }
            return nil
        }

        /// Get an entry at an array index, or `nil` if the entry could not be retrieved.
        public func potentialObject(at index: Int) -> Entry? {
            if case let .array(items) = self, index >= 0, index < items.count {
                return items[index]
            }
            return nil
        }

        /// Get an array of entries, or `nil` if the entry could not be retrieved.
        public var potentialArray: [Entry]? {
            if case let .array(items) = self {
                return items
            }
            return nil
        }
    }
}
