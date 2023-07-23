import Foundation

public final class TypedJson {
    public enum Entry {
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
            case let .object(map):
                let keys = map.keys
                var dict = [String: Any](minimumCapacity: keys.count)
                for key in keys {
                    dict[key] = self[key]?.parsed
                }
                return dict
            }
        }

        public var asInt: Int? {
            switch self {
            case let .int(buffer, from, to):
                return buffer.slice(from, to).asInt
            default:
                return nil
            }
        }

        public var asFloat: Float? {
            switch self {
            case let .float(buffer, from, to):
                return buffer.slice(from, to).asFloat
            default:
                return nil
            }
        }

        public var asBool: Bool? {
            switch self {
            case let .bool(buffer, from, _):
                return buffer.byte(at: from) == ._charT
            default:
                return nil
            }
        }

        public var asString: String? {
            switch self {
            case let .string(buffer, from, to):
                return buffer.slice(from, to).asUnescapedString
            default:
                return nil
            }
        }

        public subscript(named: String) -> Entry? {
            switch self {
            case let .object(fields):
                return fields[named]
            default:
                return nil
            }
        }

        public subscript(index: Int) -> Entry? {
            switch self {
            case let .array(items):
                if index >= 0, index < items.count {
                    return items[index]
                }
                return nil
            default:
                return nil
            }
        }

        public var asArray: [Entry]? {
            switch self {
            case let .array(items):
                return items
            default:
                return nil
            }
        }

        public var keys: [String]? {
            switch self {
            case let .object(map):
                return Array(map.keys)
            default:
                return nil
            }
        }
    }

    private let array: UnsafeRawBufferPointer
    private let endIndex: Int
    private var readerIndex = 0
    private var needsDealloc: Bool

    func parseRoot() throws -> Entry? {
        try consumeWhitespace()
        return try sliceValue()
    }

    public init(bytes: UnsafeRawBufferPointer) {
        let mutable = UnsafeMutableRawBufferPointer.allocate(byteCount: bytes.count, alignment: 0)
        mutable.copyBytes(from: bytes)
        array = UnsafeRawBufferPointer(mutable)
        endIndex = bytes.endIndex
        needsDealloc = true
    }

    public init(bytesNoCopy: UnsafeRawBufferPointer) {
        array = bytesNoCopy
        endIndex = bytesNoCopy.endIndex
        needsDealloc = false
    }

    deinit {
        if needsDealloc {
            array.deallocate()
        }
    }

    private func sliceValue() throws -> Entry? {
        while readerIndex < endIndex {
            let byte = array[readerIndex]
            readerIndex += 1

            switch byte {
            case ._quote:
                return sliceString()
            case ._openbrace:
                return try sliceObject()
            case ._openbracket:
                return try sliceArray()
            case ._charF:
                try skip(4)
                return .bool(self, from: readerIndex - 5, to: readerIndex)
            case ._charT:
                try skip(3)
                return .bool(self, from: readerIndex - 4, to: readerIndex)
            case ._charN:
                try skip(3)
                return nil
            case ._minus, ._zero ... ._nine:
                return sliceNumber()
            case 0 ... 32: // whitespace
                readerIndex += 1
            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex)
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func sliceArray() throws -> Entry? {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebracket {
            // if the first char after whitespace is a closing bracket, we found an empty array
            readerIndex += 1
            return .array([])
        }

        var array = [Entry]()
        array.reserveCapacity(10)

        while true {
            if let value = try sliceValue() {
                array.append(value)
            }

            // consume the whitespace after the value before the comma
            let ascii = try consumeWhitespace()
            switch ascii {
            case ._closebracket:
                readerIndex += 1
                return .array(array)

            case ._comma:
                // consume the comma
                readerIndex += 1
                // consume the whitespace before the next value
                if try consumeWhitespace() == ._closebracket {
                    // the foundation json implementation does support trailing commas
                    readerIndex += 1
                    return .array(array)
                }

            default:
                throw JSONError.unexpectedCharacter(ascii: ascii, characterIndex: readerIndex)
            }
        }
    }

    private func sliceObject() throws -> Entry? {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebrace {
            // if the first char after whitespace is a closing bracket, we found an empty object
            readerIndex += 1
            return nil
        }

        var map = [String: Entry](minimumCapacity: 20)

        while true {
            readerIndex += 1 // quote
            let key = sliceRawString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw JSONError.unexpectedCharacter(ascii: colon, characterIndex: readerIndex)
            }
            readerIndex += 1 // colon
            try consumeWhitespace()
            map[key] = try sliceValue()

            let commaOrBrace = try consumeWhitespace()
            readerIndex += 1
            switch commaOrBrace {
            case ._closebrace:
                return .object(map)
            case ._comma:
                if try consumeWhitespace() == ._closebrace {
                    // the foundation json implementation does support trailing commas
                    readerIndex += 1
                    return .object(map)
                }
            default:
                throw JSONError.unexpectedCharacter(ascii: commaOrBrace, characterIndex: readerIndex)
            }
        }
    }

    private func sliceString() -> Entry {
        let stringStartIndex = readerIndex

        while readerIndex < endIndex {
            if array[readerIndex] == ._quote {
                if readerIndex == stringStartIndex {
                    readerIndex += 1
                    return .string(self, from: stringStartIndex, to: stringStartIndex)
                }
                let previousIndex = readerIndex - 1
                if previousIndex >= stringStartIndex, array[previousIndex] != ._backslash {
                    readerIndex += 1
                    return .string(self, from: stringStartIndex, to: previousIndex + 1)
                }
            }
            readerIndex += 1
        }

        return .string(self, from: stringStartIndex, to: readerIndex - 1)
    }

    private func sliceRawString() -> String {
        let stringStartIndex = readerIndex

        while readerIndex < endIndex {
            if array[readerIndex] == ._quote {
                let previousIndex = readerIndex - 1
                if previousIndex >= stringStartIndex, array[previousIndex] != ._backslash {
                    readerIndex += 1
                    return array[stringStartIndex ... previousIndex].asRawString
                }
            }
            readerIndex += 1
        }

        return array[stringStartIndex ..< readerIndex - 1].asRawString
    }

    private func sliceNumber() -> Entry? {
        let startIndex = readerIndex - 1
        var float = false

        while readerIndex < endIndex {
            switch array[readerIndex] {
            case ._period:
                float = true
                readerIndex += 1

            case ._closebrace, ._closebracket, ._comma, ._newline, ._return, ._space, ._tab:
                if float {
                    return .float(self, from: startIndex, to: readerIndex)
                } else {
                    return .int(self, from: startIndex, to: readerIndex)
                }

            default:
                readerIndex += 1
            }
        }

        if float {
            return .float(self, from: startIndex, to: readerIndex)
        } else {
            return .int(self, from: startIndex, to: readerIndex)
        }
    }

    @discardableResult
    private func consumeWhitespace() throws -> UInt8 {
        while readerIndex < endIndex {
            let ascii = array[readerIndex]
            if ascii > 32 {
                return ascii
            }
            readerIndex += 1
        }

        throw JSONError.unexpectedEndOfFile
    }

    @inline(__always)
    private func skip(_ num: Int) throws {
        readerIndex += num

        guard readerIndex <= endIndex else {
            throw JSONError.unexpectedEndOfFile
        }
    }

    private func byte(at index: Int) -> UInt8 {
        array[index]
    }

    private func slice(_ from: Int, _ to: Int) -> Slice<UnsafeRawBufferPointer> {
        array[from ..< to]
    }
}
