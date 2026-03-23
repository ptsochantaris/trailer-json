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
    private let needsDealloc: Bool
    private nonisolated(unsafe) let counter: Counter

    /*
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
        counter = Counter(total: bytes.endIndex)
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
        counter = Counter(total: bytesNoCopy.endIndex)
        needsDealloc = false
    }

    deinit {
        if needsDealloc {
            array.deallocate()
        }
    }

    private func sliceValue() throws(JSONError) -> Entry? {
        while counter.hasMore {
            let byte = array[counter.currentIndex]
            counter.increment()

            switch byte {
            case ._quote:
                return sliceString()
            case ._openbrace:
                return try sliceObject()
            case ._openbracket:
                return try sliceArray()
            case ._charF:
                counter.increment(by: 4)
                return .bool(self, from: counter.currentIndex - 5, to: counter.currentIndex)
            case ._charT:
                counter.increment(by: 3)
                return .bool(self, from: counter.currentIndex - 4, to: counter.currentIndex)
            case ._charN:
                counter.increment(by: 3)
                return nil
            case ._minus, ._zero ... ._nine:
                return sliceNumber()
            default:
                throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex)
            }
        }

        throw .unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func sliceArray() throws(JSONError) -> Entry? {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebracket {
            // if the first char after whitespace is a closing bracket, we found an empty array
            counter.increment()
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
                counter.increment()
                return .array(array)

            case ._comma:
                // consume the comma
                counter.increment()
                // consume the whitespace before the next value
                if try consumeWhitespace() == ._closebracket {
                    // the foundation json implementation does support trailing commas
                    counter.increment()
                    return .array(array)
                }

            default:
                throw .unexpectedCharacter(ascii: ascii, characterIndex: counter.currentIndex)
            }
        }
    }

    private func sliceObject() throws(JSONError) -> Entry? {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebrace {
            // if the first char after whitespace is a closing bracket, we found an empty object
            counter.increment()
            return nil
        }

        var map = [String: Entry](minimumCapacity: 8)

        while true {
            counter.increment() // quote
            let key = sliceRawString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw .unexpectedCharacter(ascii: colon, characterIndex: counter.currentIndex)
            }
            counter.increment() // colon
            try consumeWhitespace()
            map[key] = try sliceValue()

            let commaOrBrace = try consumeWhitespace()
            counter.increment()
            switch commaOrBrace {
            case ._closebrace:
                return .object(map)
            case ._comma:
                if try consumeWhitespace() == ._closebrace {
                    // the foundation json implementation does support trailing commas
                    counter.increment()
                    return .object(map)
                }
            default:
                throw .unexpectedCharacter(ascii: commaOrBrace, characterIndex: counter.currentIndex)
            }
        }
    }

    private func sliceString() -> Entry {
        let stringStartIndex = counter.currentIndex
        var inEscape = false

        while counter.hasMore {
            let byte = array[counter.currentIndex]
            if inEscape {
                inEscape = false
            } else {
                switch byte {
                case ._quote:
                    let quoteIndex = counter.currentIndex
                    counter.increment()
                    return .string(self, from: stringStartIndex, to: quoteIndex)

                case ._backslash:
                    inEscape = true

                default:
                    break
                }
            }
            counter.increment()
        }

        return .string(self, from: stringStartIndex, to: counter.currentIndex - 1)
    }

    private func sliceRawString() -> String {
        let stringStartIndex = counter.currentIndex

        while counter.hasMore {
            if array[counter.currentIndex] == ._quote {
                let previousIndex = counter.currentIndex - 1
                if previousIndex >= stringStartIndex, array[previousIndex] != ._backslash {
                    counter.increment()
                    return array[stringStartIndex ... previousIndex].asRawString
                }
            }
            counter.increment()
        }

        return array[stringStartIndex ..< counter.currentIndex - 1].asRawString
    }

    private func sliceNumber() -> Entry? {
        let startIndex = counter.currentIndex - 1
        var float = false

        while counter.hasMore {
            switch array[counter.currentIndex] {
            case ._period:
                float = true
                counter.increment()

            case ._closebrace, ._closebracket, ._comma, ._newline, ._return, ._space, ._tab:
                if float {
                    return .float(self, from: startIndex, to: counter.currentIndex)
                } else {
                    return .int(self, from: startIndex, to: counter.currentIndex)
                }

            default:
                counter.increment()
            }
        }

        if float {
            return .float(self, from: startIndex, to: counter.currentIndex)
        } else {
            return .int(self, from: startIndex, to: counter.currentIndex)
        }
    }

    @discardableResult
    private func consumeWhitespace() throws(JSONError) -> UInt8 {
        while counter.hasMore {
            let ascii = array[counter.currentIndex]
            if ascii > 32 {
                return ascii
            }
            counter.increment()
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
