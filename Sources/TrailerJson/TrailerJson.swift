import Foundation

private typealias JSON = [String: Sendable]

/**
 This parser processes the entire data blob in one go, producing a dictionary much like `JSONSerialization` does.

 It performs almost equivalently with `JSONSerialization` _BUT!_ the results are all native Swift types, so using those results incurs no bridging or copying costs, which is a major performance bonus.
  ```
      let url = URL(string: "http://date.jsontest.com")!
      let data = try await URLSession.shared.data(from: url).0

      // Parse in one go to [String: Sendable]
      if let json = try data.asJsonObject(),      // parse as dictionary
         let timeField = json["time"],
         let timeString = timeField as? String {

          print("The time is", timeString)
      }
  ```
 */
public struct TrailerJson: Sendable {
    private nonisolated(unsafe) let array: UnsafeRawBufferPointer
    private nonisolated(unsafe) let counter: Counter

    private init(bytes: UnsafeRawBufferPointer) throws(JSONError) {
        array = bytes
        counter = Counter(total: bytes.count)
        try consumeWhitespace()
    }

    /**
     Performs the parsing of the provided data. Once the data is parsed, it can be discarded as everythig has been copied to the parsed items.
     ```
     let byteBuffer: ByteBuffer = ...

     let jsonArray = try byteBuffer.withVeryUnsafeBytes {
     try TrailerJson.parse(bytes: $0) as? [Sendable]
     }
     let number = jsonArray[1] as? Int
     print(number)
     ```
     */
    public static func parse(bytes: UnsafeRawBufferPointer) throws(JSONError) -> Sendable? {
        try TrailerJson(bytes: bytes).parseValue()
    }

    // MARK: Generic Value Parsing

    private func parseValue() throws(JSONError) -> Sendable? {
        while counter.hasMore {
            let byte = array[counter.currentIndex]
            counter.increment()

            switch byte {
            case ._quote:
                return try readString()
            case ._openbrace:
                return try parseObject()
            case ._openbracket:
                return try parseArray()
            case ._charF:
                counter.increment(by: 4)
                return false
            case ._charT:
                counter.increment(by: 3)
                return true
            case ._charN:
                counter.increment(by: 3)
                return nil
            case ._minus:
                return try parseNumber(positive: false)
            case ._zero ... ._nine:
                return try parseNumber(positive: true)
            case 0 ... 32:
                counter.increment()
            default:
                throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex)
            }
        }

        throw .unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func parseArray() throws(JSONError) -> [Sendable] {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebracket {
            // if the first char after whitespace is a closing bracket, we found an empty array
            counter.increment()
            return []
        }

        var array = [Sendable]()
        array.reserveCapacity(6)

        // parse values
        while true {
            if let value = try parseValue() {
                array.append(value)
            }

            // consume the whitespace after the value before the comma
            let ascii = try consumeWhitespace()
            switch ascii {
            case ._closebracket:
                counter.increment()
                return array

            case ._comma:
                // consume the comma
                counter.increment()
                // consume the whitespace before the next value
                if try consumeWhitespace() == ._closebracket {
                    // the foundation json implementation does support trailing commas
                    counter.increment()
                    return array
                }

            default:
                throw .unexpectedCharacter(ascii: ascii, characterIndex: counter.currentIndex)
            }
        }
    }

    // MARK: - Object parsing -

    private func parseObject() throws(JSONError) -> JSON {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebrace {
            // if the first char after whitespace is a closing bracket, we found an empty array
            counter.increment()
            return [:]
        }

        var object = JSON(minimumCapacity: 8)

        while true {
            counter.increment() // quote
            let key = try readString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw .unexpectedCharacter(ascii: colon, characterIndex: counter.currentIndex)
            }
            counter.increment()
            try consumeWhitespace()
            object[key] = try parseValue()

            let commaOrBrace = try consumeWhitespace()
            switch commaOrBrace {
            case ._closebrace:
                counter.increment()
                return object
            case ._comma:
                counter.increment()
                if try consumeWhitespace() == ._closebrace {
                    // the foundation json implementation does support trailing commas
                    counter.increment()
                    return object
                }
                continue
            default:
                throw .unexpectedCharacter(ascii: commaOrBrace, characterIndex: counter.currentIndex)
            }
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

    // MARK: Strings

    private func readString() throws(JSONError) -> String {
        var output: String?
        var segmentStartIndex = counter.currentIndex

        while counter.hasMore {
            let byte = array[counter.currentIndex]

            switch byte {
            case 0 ... 31:
                throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex)

            case ._quote:
                let text = array[segmentStartIndex ..< counter.currentIndex].asRawString
                counter.increment()

                if let output {
                    return output + text
                } else {
                    return text
                }

            case ._backslash:
                if let existing = output {
                    output = existing + array[segmentStartIndex ..< counter.currentIndex].asRawString
                } else {
                    output = array[segmentStartIndex ..< counter.currentIndex].asRawString
                }

                counter.increment()
                let seq = array.parseEscapeSequence(at: counter.currentIndex)
                if let text = seq.1 {
                    if let existing = output {
                        output = existing + text
                    } else {
                        output = text
                    }
                }
                counter.increment(by: seq.0)
                segmentStartIndex = counter.currentIndex

            default:
                counter.increment()
            }
        }

        throw .unexpectedEndOfFile
    }

    // MARK: Numbers

    private func parseNumber(positive: Bool) throws(JSONError) -> Sendable {
        let startIndex = counter.currentIndex - 1

        var pastControlChar: ControlCharacter = .operand
        var numbersSinceControlChar = positive

        while true {
            let byte: UInt8
            if counter.hasMore {
                byte = array[counter.currentIndex]
                counter.increment()
            } else {
                byte = 0
            }

            switch byte {
            case ._zero ... ._nine:
                numbersSinceControlChar = true

            case ._period:
                guard numbersSinceControlChar, pastControlChar == .operand else {
                    throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex - 1)
                }
                pastControlChar = .decimalPoint
                numbersSinceControlChar = false

            case ._charCapitalE, ._charE:
                guard numbersSinceControlChar,
                      pastControlChar == .operand || pastControlChar == .decimalPoint
                else {
                    throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex - 1)
                }
                pastControlChar = .exp
                numbersSinceControlChar = false

            case ._minus, ._plus:
                guard !numbersSinceControlChar, pastControlChar == .exp else {
                    throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex - 1)
                }
                pastControlChar = .expOperator
                numbersSinceControlChar = false

            case ._closebrace, ._closebracket, ._comma, ._newline, ._return, ._space, ._tab, 0:
                if byte == 0 { // end of file, possible fragment
                    guard numbersSinceControlChar else {
                        throw .unexpectedEndOfFile
                    }
                } else {
                    guard numbersSinceControlChar else {
                        throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex - 1)
                    }
                    counter.increment(by: -1)
                }

                switch pastControlChar {
                case .decimalPoint:
                    let stringValue = array[startIndex ..< counter.currentIndex].asRawString
                    guard let result = Float(stringValue) else {
                        throw .numberIsNotRepresentableInSwift(parsed: stringValue)
                    }
                    return result
                case .exp, .expOperator:
                    let stringValue = array[startIndex ..< counter.currentIndex].asRawString
                    throw .numberIsNotRepresentableInSwift(parsed: stringValue)
                case .operand:
                    var total = 0
                    if positive {
                        for index in startIndex ..< counter.currentIndex {
                            total = (total * 10) + Int(array[index] & 15)
                        }
                    } else {
                        for index in startIndex + 1 ..< counter.currentIndex {
                            total = (total * 10) - Int(array[index] & 15)
                        }
                    }
                    return total
                }

            default:
                throw .unexpectedCharacter(ascii: byte, characterIndex: counter.currentIndex - 1)
            }
        }
    }
}
