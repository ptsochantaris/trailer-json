import Foundation

/**
 Quickly scan the data blob and provide results of type ``Entry``, which provides typed access and parses that data only when accessed.

 This parser is much faster than `JSONSerialization`, and ideal if you are only accessing a subset of the JSON data. It also makes it possible to parallelise the subsequent parsing in threads if needed.
  ```
  let url = URL(string: "http://date.jsontest.com")!
  let data = try await URLSession.shared.data(from: url).0

  // Scan the data and only parse 'time' as a String
  if let json = try data.asTypedJson(),         // scan data
     let timeField = try? json["time"],
     let timeString = try? timeField.asString { // parse field

      print("The time is", timeString)
  }
  ```
 */
public final class TypedJson: Sendable {
    private nonisolated(unsafe) let array: UnsafeRawBufferPointer
    private let endIndex: Int
    private let needsDealloc: Bool
    private nonisolated(unsafe) var readerIndex = 0

    /**
     Creates a `TypedJson` instance for parsing data.
     - Parameter bytes: A pointer to the data to parse. This initialiser will make a copy of the data so the original can be discarded.
     ```
        let byteBuffer: ByteBuffer = ...
        let jsonArray = try byteBuffer.withVeryUnsafeBytes {
            try TypedJson.parse(bytes: $0)
        }
        let number = try jsonArray[1].asInt
        print(number)
     ```
     */

    public init(bytes: UnsafeRawBufferPointer) {
        let mutable = UnsafeMutableRawBufferPointer.allocate(byteCount: bytes.count, alignment: 0)
        mutable.copyBytes(from: bytes)
        array = UnsafeRawBufferPointer(mutable)
        endIndex = bytes.endIndex
        needsDealloc = true
    }

    /**
     Creates a `TypedJson` instance for parsing data, without copying it in, for speed.
     - Parameter bytesNoCopy: A pointer to the data to parse. This data *must* be retained until all parsed items have been used or the code will crash.
     ```
         // Using bytesNoCopy (max performance, but with caveats!)
         let number = try byteBuffer.withVeryUnsafeBytes {

             // jsonArray and any Entry from it must not be accessed outside the closure
             let jsonArray = try TypedJson.parse(bytesNoCopy: $0)

             // `secondEntry` reads from the original bytes, so it can't escape
             let secondEntry = try jsonArray[1]

             // but parsed values can escape
             return try secondEntry.asInt
         }
         print(number)
     ```
     */
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

    private func sliceValue() throws(JSONError) -> Entry? {
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
                readerIndex += 4
                return .bool(self, from: readerIndex - 5, to: readerIndex)
            case ._charT:
                readerIndex += 3
                return .bool(self, from: readerIndex - 4, to: readerIndex)
            case ._charN:
                readerIndex += 3
                return nil
            case ._minus, ._zero ... ._nine:
                return sliceNumber()
            default:
                throw .unexpectedCharacter(ascii: byte, characterIndex: readerIndex)
            }
        }

        throw .unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func sliceArray() throws(JSONError) -> Entry? {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebracket {
            // if the first char after whitespace is a closing bracket, we found an empty array
            readerIndex += 1
            return .array([])
        }

        var array = [Entry]()
        array.reserveCapacity(6)

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
                throw .unexpectedCharacter(ascii: ascii, characterIndex: readerIndex)
            }
        }
    }

    private func sliceObject() throws(JSONError) -> Entry? {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebrace {
            // if the first char after whitespace is a closing bracket, we found an empty object
            readerIndex += 1
            return nil
        }

        var map = [String: Entry](minimumCapacity: 8)

        while true {
            readerIndex += 1 // quote
            let key = sliceRawString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw .unexpectedCharacter(ascii: colon, characterIndex: readerIndex)
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
                throw .unexpectedCharacter(ascii: commaOrBrace, characterIndex: readerIndex)
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
    private func consumeWhitespace() throws(JSONError) -> UInt8 {
        while readerIndex < endIndex {
            let ascii = array[readerIndex]
            if ascii > 32 {
                return ascii
            }
            readerIndex += 1
        }

        throw .unexpectedEndOfFile
    }

    @inline(__always)
    func byte(at index: Int) -> UInt8 {
        array[index]
    }

    @inline(__always)
    func slice(_ from: Int, _ to: Int) -> Slice<UnsafeRawBufferPointer> {
        array[from ..< to]
    }

    func parseRoot() throws(JSONError) -> Entry? {
        try consumeWhitespace()
        return try sliceValue()
    }
}
