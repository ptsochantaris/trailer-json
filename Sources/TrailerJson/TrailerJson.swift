import Foundation

private typealias JSON = [String: Any]

/**
 This parser processes the entire data blob in one go, producing a dictionary much like `JSONSerialization` does.

 It performs almost equivalently with `JSONSerialization` _BUT!_ the results are all native Swift types, so using those results incurs no bridging or copying costs, which is a major performance bonus.
  ```
      let url = URL(string: "http://date.jsontest.com")!
      let data = try await URLSession.shared.data(from: url).0

      // Parse in one go to [String: Any]
      if let json = try data.asJsonObject(),      // parse as dictionary
         let timeField = json["time"],
         let timeString = timeField as? String {

          print("The time is", timeString)
      }
  ```
 */
public final class TrailerJson {
    private let array: UnsafeRawBufferPointer
    private let endIndex: Int
    private var readerIndex = 0

    private init(bytes: UnsafeRawBufferPointer) throws {
        array = bytes
        endIndex = bytes.endIndex
        try consumeWhitespace()
    }

    /**
     Performs the parsing of the provided data. Once the data is parsed, it can be discarded as everythig has been copied to the parsed items.
     ```
         let byteBuffer: ByteBuffer = ...

         let jsonArray = try byteBuffer.withVeryUnsafeBytes {
             try TrailerJson.parse(bytes: $0) as? [Any]
         }
         let number = jsonArray[1] as? Int
         print(number)
     ```
     */
    public static func parse(bytes: UnsafeRawBufferPointer) throws -> Any? {
        try TrailerJson(bytes: bytes).parseValue()
    }

    // MARK: Generic Value Parsing

    private func parseValue() throws -> Any? {
        while let byte = read() {
            switch byte {
            case ._quote:
                return try readString()
            case ._openbrace:
                return try parseObject()
            case ._openbracket:
                return try parseArray()
            case ._charF:
                try skip(4)
                return false
            case ._charT:
                try skip(3)
                return true
            case ._charN:
                try skip(3)
                return nil
            case ._minus:
                return try parseNumber(positive: false)
            case ._zero ... ._nine:
                return try parseNumber(positive: true)
            case 0 ... 32:
                readerIndex += 1
            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex)
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func parseArray() throws -> [Any] {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebracket {
            // if the first char after whitespace is a closing bracket, we found an empty array
            readerIndex += 1
            return []
        }

        var array = [Any]()
        array.reserveCapacity(10)

        // parse values
        while true {
            if let value = try parseValue() {
                array.append(value)
            }

            // consume the whitespace after the value before the comma
            let ascii = try consumeWhitespace()
            switch ascii {
            case ._closebracket:
                readerIndex += 1
                return array

            case ._comma:
                // consume the comma
                readerIndex += 1
                // consume the whitespace before the next value
                if try consumeWhitespace() == ._closebracket {
                    // the foundation json implementation does support trailing commas
                    readerIndex += 1
                    return array
                }

            default:
                throw JSONError.unexpectedCharacter(ascii: ascii, characterIndex: readerIndex)
            }
        }
    }

    // MARK: - Object parsing -

    private func parseObject() throws -> JSON {
        // parse first value or end immediatly
        if try consumeWhitespace() == ._closebrace {
            // if the first char after whitespace is a closing bracket, we found an empty array
            readerIndex += 1
            return [:]
        }

        var object = JSON(minimumCapacity: 20)

        while true {
            readerIndex += 1 // quote
            let key = try readString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw JSONError.unexpectedCharacter(ascii: colon, characterIndex: readerIndex)
            }
            readerIndex += 1
            try consumeWhitespace()
            object[key] = try parseValue()

            let commaOrBrace = try consumeWhitespace()
            switch commaOrBrace {
            case ._closebrace:
                readerIndex += 1
                return object
            case ._comma:
                readerIndex += 1
                if try consumeWhitespace() == ._closebrace {
                    // the foundation json implementation does support trailing commas
                    readerIndex += 1
                    return object
                }
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: commaOrBrace, characterIndex: readerIndex)
            }
        }
    }

    // document reading

    private func read() -> UInt8? {
        guard readerIndex < endIndex else {
            readerIndex = endIndex
            return nil
        }
        defer {
            readerIndex += 1
        }
        return array[readerIndex]
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

    // MARK: String

    private func readString() throws -> String {
        var stringStartIndex = readerIndex
        var output: String?

        while let byte = read() {
            switch byte {
            case ._quote:
                let currentCharIndex = readerIndex - 1
                if let output {
                    return output + array[stringStartIndex ..< currentCharIndex].asRawString
                } else {
                    return array[stringStartIndex ..< currentCharIndex].asRawString
                }

            case 0 ... 31:
                let currentCharIndex = readerIndex - 1
                // All Unicode characters may be placed within the
                // quotation marks, except for the characters that must be escaped:
                // quotation mark, reverse solidus, and the control characters (U+0000
                // through U+001F).
                let string: String
                if let output {
                    string = output + array[stringStartIndex ... currentCharIndex].asRawString
                } else {
                    string = array[stringStartIndex ... currentCharIndex].asRawString
                }
                throw JSONError.unescapedControlCharacterInString(ascii: byte, in: string, index: currentCharIndex)

            case ._backslash:
                let currentCharIndex = readerIndex - 1
                if let existing = output {
                    output = existing + array[stringStartIndex ..< currentCharIndex].asRawString
                } else {
                    output = array[stringStartIndex ..< currentCharIndex].asRawString
                }

                do {
                    if let existing = output {
                        output = try existing + parseEscapeSequence()
                    } else {
                        output = try parseEscapeSequence()
                    }
                    stringStartIndex = readerIndex

                } catch let error as EscapedSequenceError {
                    output! += array[currentCharIndex ..< readerIndex].asRawString
                    throw JSONError.faultyEscapeSequence(error, in: output!)
                }

            default:
                break
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    private func parseEscapeSequence() throws -> String {
        guard let ascii = read() else {
            throw JSONError.unexpectedEndOfFile
        }

        switch ascii {
        case 0x22: return "\""
        case 0x5C: return "\\"
        case 0x2F: return "/"
        case 0x62: return "\u{08}" // \b
        case 0x66: return "\u{0C}" // \f
        case 0x6E: return "\u{0A}" // \n
        case 0x72: return "\u{0D}" // \r
        case 0x74: return "\u{09}" // \t
        case 0x75:
            let character = try parseUnicodeSequence()
            return String(character)
        default:
            throw EscapedSequenceError.unexpectedEscapedCharacter(ascii: ascii, index: readerIndex - 1)
        }
    }

    private func parseUnicodeSequence() throws -> Unicode.Scalar {
        // we build this for utf8 only for now.
        let bitPattern = try parseUnicodeHexSequence()

        // check if high surrogate
        let isFirstByteHighSurrogate = bitPattern & 0xFC00 // nil everything except first six bits
        if isFirstByteHighSurrogate == 0xD800 {
            // if we have a high surrogate we expect a low surrogate next
            let highSurrogateBitPattern = bitPattern
            guard let escapeChar = read(),
                  let uChar = read()
            else {
                throw JSONError.unexpectedEndOfFile
            }

            guard escapeChar == UInt8(ascii: #"\"#), uChar == UInt8(ascii: "u") else {
                throw EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: readerIndex - 1)
            }

            let lowSurrogateBitBattern = try parseUnicodeHexSequence()
            let isSecondByteLowSurrogate = lowSurrogateBitBattern & 0xFC00 // nil everything except first six bits
            guard isSecondByteLowSurrogate == 0xDC00 else {
                // we are in an escaped sequence. for this reason an output string must have
                // been initialized
                throw EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: readerIndex - 1)
            }

            let highValue = UInt32(highSurrogateBitPattern - 0xD800) * 0x400
            let lowValue = UInt32(lowSurrogateBitBattern - 0xDC00)
            let unicodeValue = highValue + lowValue + 0x10000
            guard let unicode = Unicode.Scalar(unicodeValue) else {
                throw EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(index: readerIndex, unicodeScalarValue: unicodeValue)
            }
            return unicode
        }

        guard let unicode = Unicode.Scalar(bitPattern) else {
            throw EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(index: readerIndex, unicodeScalarValue: UInt32(bitPattern))
        }
        return unicode
    }

    private func parseUnicodeHexSequence() throws -> UInt16 {
        // As stated in RFC-8259 an escaped unicode character is 4 HEXDIGITs long
        // https://tools.ietf.org/html/rfc8259#section-7
        let startIndex = readerIndex
        guard let firstHex = read(),
              let secondHex = read(),
              let thirdHex = read(),
              let forthHex = read()
        else {
            throw JSONError.unexpectedEndOfFile
        }

        guard let first = hexAsciiTo4Bits(firstHex),
              let second = hexAsciiTo4Bits(secondHex),
              let third = hexAsciiTo4Bits(thirdHex),
              let forth = hexAsciiTo4Bits(forthHex)
        else {
            let hexString = String(decoding: [firstHex, secondHex, thirdHex, forthHex], as: Unicode.UTF8.self)
            throw JSONError.invalidHexDigitSequence(hexString, index: startIndex)
        }
        let firstByte = UInt16(first) << 4 | UInt16(second)
        let secondByte = UInt16(third) << 4 | UInt16(forth)

        let bitPattern = UInt16(firstByte) << 8 | UInt16(secondByte)

        return bitPattern
    }

    // MARK: Numbers

    private func parseNumber(positive: Bool) throws -> Any {
        let startIndex = readerIndex - 1

        var pastControlChar: ControlCharacter = .operand
        var numbersSinceControlChar = positive

        while true {
            let byte = read() ?? 0
            switch byte {
            case ._zero ... ._nine:
                numbersSinceControlChar = true

            case ._period:
                guard numbersSinceControlChar, pastControlChar == .operand else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }
                pastControlChar = .decimalPoint
                numbersSinceControlChar = false

            case ._charCapitalE, ._charE:
                guard numbersSinceControlChar,
                      pastControlChar == .operand || pastControlChar == .decimalPoint
                else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }
                pastControlChar = .exp
                numbersSinceControlChar = false

            case ._minus, ._plus:
                guard !numbersSinceControlChar, pastControlChar == .exp else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }
                pastControlChar = .expOperator
                numbersSinceControlChar = false

            case ._closebrace, ._closebracket, ._comma, ._newline, ._return, ._space, ._tab, 0:
                if byte == 0 { // end of file, possible fragment
                    guard numbersSinceControlChar else {
                        throw JSONError.unexpectedEndOfFile
                    }
                } else {
                    guard numbersSinceControlChar else {
                        throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                    }
                    readerIndex -= 1
                }

                switch pastControlChar {
                case .decimalPoint:
                    let stringValue = array[startIndex ..< readerIndex].asRawString
                    guard let result = Float(stringValue) else {
                        throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                    }
                    return result
                case .exp, .expOperator:
                    let stringValue = array[startIndex ..< readerIndex].asRawString
                    throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                case .operand:
                    let numberIndex: Int
                    var dec: Int
                    if positive {
                        numberIndex = startIndex
                        dec = 1
                    } else {
                        numberIndex = startIndex + 1
                        dec = -1
                    }

                    var index = readerIndex
                    var total = 0
                    while index > numberIndex {
                        index -= 1
                        total += Int(array[index] - 48) * dec
                        dec *= 10
                    }
                    return total
                }

            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
            }
        }
    }
}
