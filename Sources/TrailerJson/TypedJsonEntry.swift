import Foundation

public extension TypedJson {
    /// A node object  that contains the scanned JSON elements at that level.
    enum Entry: Sendable {
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
                "Int"
            case .float:
                "Float"
            case .bool:
                "Bool"
            case .string:
                "String"
            case .object:
                "Object"
            case .array:
                "Array"
            }
        }

        /// The type that the parsed value is expected to be
        var type: Sendable.Type {
            switch self {
            case .int:
                Int.self
            case .float:
                Float.self
            case .bool:
                Bool.self
            case .string:
                String.self
            case .object:
                [String: Sendable].self
            case .array:
                [Sendable].self
            }
        }

        /**
          Returns a parsed version of this item, depending on the type that was parsed. Note that calling this to convert an entire large tree to a dictionary is slower than using TrailerJson in the first place. This method's usefulness lies in parsing things like large homogenous arrays of objects in parallel, or parsing only a small branch from a large tree without parsing the rest, etc.
          - Throws: If the value could not be parsed by using its type-specific logic.
         ```
             let numberArray = try byteBuffer.withVeryUnsafeBytes {

                 let numbers = try TypedJson.parse(bytes: $0)

                 return try numbers.parsed as! [Int]
             }
             let number = numberArray[1]
             print(number)
         ```
         */
        public var parsed: Sendable {
            get throws {
                switch self {
                case let .int(buffer, from, to):
                    buffer.slice(from, to).asInt
                case let .float(buffer, from, to):
                    try buffer.slice(from, to).asFloat
                case let .bool(buffer, from, _):
                    buffer.byte(at: from) == ._charT
                case let .string(buffer, from, to):
                    try buffer.slice(from, to).asUnescapedString
                case let .array(list):
                    try list.map { try $0.parsed }
                case let .object(fields):
                    try fields.mapValues { try $0.parsed }
                }
            }
        }

        /// Get an integer.
        /// - Throws: If the parsed value is not this type.
        public var asInt: Int {
            get throws(JSONError) {
                if case let .int(buffer, from, to) = self {
                    return buffer.slice(from, to).asInt
                }
                throw .incorrectTypeRequested(requested: "Int", detected: typeName)
            }
        }

        /// Get a float.
        /// - Throws: If the parsed value is not this type.
        public var asFloat: Float {
            get throws(JSONError) {
                if case let .float(buffer, from, to) = self {
                    return try buffer.slice(from, to).asFloat
                }
                throw .incorrectTypeRequested(requested: "Float", detected: typeName)
            }
        }

        /// Get a bool.
        /// - Throws: If the parsed value is not this type.
        public var asBool: Bool {
            get throws(JSONError) {
                if case let .bool(buffer, from, _) = self {
                    return buffer.byte(at: from) == ._charT
                }
                throw .incorrectTypeRequested(requested: "Bool", detected: typeName)
            }
        }

        /// Get a string.
        /// - Throws: If the parsed value is not this type.
        public var asString: String {
            get throws(JSONError) {
                if case let .string(buffer, from, to) = self {
                    return try buffer.slice(from, to).asUnescapedString
                }
                throw .incorrectTypeRequested(requested: "String", detected: typeName)
            }
        }

        /// Get an entry for a field.
        /// - Throws: If the parsed item is not an object, or the field does not exist.
        public subscript(named: String) -> Entry {
            get throws(JSONError) {
                if case let .object(fields) = self {
                    if let entry = fields[named] {
                        return entry
                    }
                    throw .fieldNotFound(field: named)
                }
                throw .incorrectTypeRequested(requested: "Object", detected: typeName)
            }
        }

        /// Get an entry at an array index.
        /// - Throws: If the parsed item is not an array, or the index is out of range.
        public subscript(index: Int) -> Entry {
            get throws(JSONError) {
                if case let .array(items) = self, index >= 0, index < items.count {
                    return items[index]
                }
                throw .incorrectTypeRequested(requested: "Array", detected: typeName)
            }
        }

        /// Get an array of entries.
        /// - Throws: If the parsed value is not an array.
        public var asArray: [Entry] {
            get throws(JSONError) {
                if case let .array(items) = self {
                    return items
                }
                throw .incorrectTypeRequested(requested: "Array", detected: typeName)
            }
        }

        /// Get the names of the keys for this object.
        /// - Throws: If the parsed item is not an object, or the field does not exist.
        public var keys: [String] {
            get throws(JSONError) {
                if case let .object(fields) = self {
                    return Array(fields.keys)
                }
                throw .incorrectTypeRequested(requested: "Object", detected: typeName)
            }
        }

        /// Get an integer, ot `nil` if the entry could not be retrieved
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

        // Faster and simpler than `potentialObject(named:)?.potentialInt`
        public func potentialInt(named: String) -> Int? {
            guard case let .object(fields) = self, let entry = fields[named], case let .int(buffer, from, to) = entry else {
                return nil
            }
            return buffer.slice(from, to).asInt
        }

        // Faster and simpler than `potentialObject(named:)?.potentialFloat`
        public func potentialFloat(named: String) -> Float? {
            guard case let .object(fields) = self, let entry = fields[named], case let .float(buffer, from, to) = entry else {
                return nil
            }
            return try? buffer.slice(from, to).asFloat
        }

        // Faster and simpler than `potentialObject(named:)?.potentialBool`
        public func potentialBool(named: String) -> Bool? {
            guard case let .object(fields) = self, let entry = fields[named], case let .bool(buffer, from, _) = entry else {
                return nil
            }
            return buffer.byte(at: from) == ._charT
        }

        // Faster and simpler than `potentialObject(named:)?.potentialString`
        public func potentialString(named: String) -> String? {
            guard case let .object(fields) = self, let entry = fields[named], case let .string(buffer, from, to) = entry else {
                return nil
            }
            return try? buffer.slice(from, to).asUnescapedString
        }

        // Faster and simpler than `potentialObject(named:)?.potentialArray`
        public func potentialArray(named: String) -> [Entry]? {
            guard case let .object(fields) = self, let entry = fields[named], case let .array(items) = entry else {
                return nil
            }
            return items
        }

        // Faster and simpler than `potentialArray(named:)?.potentialInt`
        public func potentialInt(at index: Int) -> Int? {
            guard case let .array(items) = self, index >= 0, index < items.count, case let .int(buffer, from, to) = items[index] else {
                return nil
            }
            return buffer.slice(from, to).asInt
        }

        // Faster and simpler than `potentialArray(named:)?.potentialFloat`
        public func potentialFloat(at index: Int) -> Float? {
            guard case let .array(items) = self, index >= 0, index < items.count, case let .float(buffer, from, to) = items[index] else {
                return nil
            }
            return try? buffer.slice(from, to).asFloat
        }

        // Faster and simpler than `potentialArray(named:)?.potentialBool`
        public func potentialBool(at index: Int) -> Bool? {
            guard case let .array(items) = self, index >= 0, index < items.count, case let .bool(buffer, from, _) = items[index] else {
                return nil
            }
            return buffer.byte(at: from) == ._charT
        }

        // Faster and simpler than `potentialArray(named:)?.potentialString`
        public func potentialString(at index: Int) -> String? {
            guard case let .array(items) = self, index >= 0, index < items.count, case let .string(buffer, from, to) = items[index] else {
                return nil
            }
            return try? buffer.slice(from, to).asUnescapedString
        }

        // Faster and simpler than `potentialArray(named:)?.potentialArray`
        public func potentialArray(at index: Int) -> [Entry]? {
            guard case let .array(items) = self, index >= 0, index < items.count, case let .array(items) = items[index] else {
                return nil
            }
            return items
        }
    }
}
