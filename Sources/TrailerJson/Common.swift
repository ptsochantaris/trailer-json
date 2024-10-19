import Foundation

extension UInt8 {
    static let _space = UInt8(ascii: " ")
    static let _return = UInt8(ascii: "\r")
    static let _newline = UInt8(ascii: "\n")
    static let _tab = UInt8(ascii: "\t")

    static let _colon = UInt8(ascii: ":")
    static let _comma = UInt8(ascii: ",")
    static let _period = UInt8(ascii: ".")

    static let _openbrace = UInt8(ascii: "{")
    static let _closebrace = UInt8(ascii: "}")

    static let _openbracket = UInt8(ascii: "[")
    static let _closebracket = UInt8(ascii: "]")

    static let _quote = UInt8(ascii: "\"")
    static let _backslash = UInt8(ascii: "\\")

    static let _minus = UInt8(ascii: "-")
    static let _plus = UInt8(ascii: "+")

    static let _zero = UInt8(ascii: "0")
    static let _one = UInt8(ascii: "1")
    static let _nine = UInt8(ascii: "9")

    static let _charF = UInt8(ascii: "f")
    static let _charA = UInt8(ascii: "a")
    static let _charL = UInt8(ascii: "l")
    static let _charS = UInt8(ascii: "s")
    static let _charE = UInt8(ascii: "e")

    static let _charR = UInt8(ascii: "r")
    static let _charU = UInt8(ascii: "u")
    static let _charT = UInt8(ascii: "t")
    static let _charN = UInt8(ascii: "n")
    static let _charCapitalE = UInt8(ascii: "E")
}

public enum EscapedSequenceError: Swift.Error {
    case expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: Int)
    case unexpectedEscapedCharacter(ascii: UInt8, index: Int)
    case couldNotCreateUnicodeScalarFromUInt32(index: Int, unicodeScalarValue: UInt32)
}

public enum JSONError: Error {
    case unexpectedCharacter(ascii: UInt8, characterIndex: Int)
    case unexpectedEndOfFile
    case faultyEscapeSequence(EscapedSequenceError, in: String)
    case invalidHexDigitSequence(String, index: Int)
    case unescapedControlCharacterInString(ascii: UInt8, in: String, index: Int)
    case numberIsNotRepresentableInSwift(parsed: String)
    case invalidUTF8Sequence(Data, characterIndex: Int)
    case incorrectTypeRequested(requested: String, detected: String)
    case fieldNotFound(field: String)

    var localizedDescription: String {
        switch self {
        case let .faultyEscapeSequence(error, text):
            switch error {
            case .couldNotCreateUnicodeScalarFromUInt32:
                "Unable to convert hex escape sequence (no high character) to UTF8-encoded character. Text: \(text)"
            case .expectedLowSurrogateUTF8SequenceAfterHighSurrogate:
                "Unexpected end of file during string parse (expected low-surrogate code point but did not find one). Text: \(text)"
            case .unexpectedEscapedCharacter:
                "Invalid escape sequence. Text: \(text)"
            }
        case let .incorrectTypeRequested(requested, detected):
            "Type requested ('\(requested)') did not match the type detected by the parser for this value ('\(detected)')."
        case let .fieldNotFound(field):
            "Field '\(field)' not found in this object."
        case .unexpectedEndOfFile:
            "Unexpected end of file during JSON parse."
        case let .unexpectedCharacter(_, characterIndex):
            "Invalid value around character \(characterIndex)."
        case let .invalidHexDigitSequence(string, index: index):
            #"Invalid hex encoded sequence in "\#(string)" at \#(index)."#
        case .unescapedControlCharacterInString(ascii: let ascii, in: _, index: let index) where ascii == UInt8._backslash:
            #"Invalid escape sequence around character \#(index)."#
        case .unescapedControlCharacterInString(ascii: _, in: _, index: let index):
            #"Unescaped control character around character \#(index)."#
        case let .numberIsNotRepresentableInSwift(parsed: parsed):
            #"Number \#(parsed) is not representable in Swift."#
        case let .invalidUTF8Sequence(data, characterIndex: index):
            #"Invalid UTF-8 sequence \#(data) starting from character \#(index)."#
        }
    }
}

enum ControlCharacter {
    case operand
    case decimalPoint
    case exp
    case expOperator
}

extension Slice<UnsafeRawBufferPointer> {
    var asRawString: String {
        String(unsafeUninitializedCapacity: count) { pointer in
            _ = pointer.initialize(fromContentsOf: self)
            return count
        }
    }

    var asUnescapedString: String {
        get throws(JSONError) {
            var output: String?
            var readerIndex = startIndex
            let end = endIndex

            guard readerIndex < end else {
                return ""
            }

            var segmentStartIndex = readerIndex

            while readerIndex < end {
                let byte = self[readerIndex]

                switch byte {
                case 0 ... 31:
                    throw .unexpectedCharacter(ascii: byte, characterIndex: readerIndex)

                case ._backslash:
                    if let existing = output {
                        output = existing + self[segmentStartIndex ..< readerIndex].asRawString
                    } else {
                        output = self[segmentStartIndex ..< readerIndex].asRawString
                    }

                    readerIndex += 1
                    let seq = parseEscapeSequence(at: readerIndex)
                    if let text = seq.1 {
                        if let existing = output {
                            output = existing + text
                        } else {
                            output = text
                        }
                    }
                    readerIndex += seq.0
                    segmentStartIndex = readerIndex

                default:
                    readerIndex += 1
                }
            }

            if let output {
                return output + self[segmentStartIndex ..< readerIndex].asRawString
            } else {
                return self[segmentStartIndex ..< readerIndex].asRawString
            }
        }
    }

    private func parseEscapeSequence(at readerIndex: Int) -> (Int, String?) {
        guard readerIndex < endIndex else {
            return (0, nil)
        }

        switch self[readerIndex] {
        case 0x22:
            return (1, "\"")
        case 0x5C:
            return (1, "\\")
        case 0x2F:
            return (1, "/")
        case 0x62:
            return (1, "\u{08}") // \b
        case 0x66:
            return (1, "\u{0C}") // \f
        case 0x6E:
            return (1, "\u{0A}") // \n
        case 0x72:
            return (1, "\u{0D}") // \r
        case 0x74:
            return (1, "\u{09}") // \t
        case 0x75:
            let (count, scalar) = parseUnicodeSequence(at: readerIndex + 1)
            if let scalar {
                return (count, String(scalar))
            } else {
                return (count, nil)
            }
        default:
            return (0, nil)
        }
    }

    private func parseUnicodeSequence(at readerIndex: Int) -> (Int, Unicode.Scalar?) {
        // we build this for utf8 only for now.
        guard let bitPattern = parseUnicodeHexSequence(at: readerIndex) else {
            return (-1, nil)
        }

        // check if high surrogate
        let isFirstByteHighSurrogate = bitPattern & 0xFC00 // nil everything except first six bits
        guard isFirstByteHighSurrogate == 0xD800 else {
            return (4, Unicode.Scalar(bitPattern))
        }

        let readerIndex = readerIndex + 4

        // if we have a high surrogate we expect a low surrogate next
        let highSurrogateBitPattern = bitPattern
        guard readerIndex < endIndex - 2 else {
            return (4, nil)
        }

        let escapeChar = self[readerIndex]
        let uChar = self[readerIndex + 1]

        guard escapeChar == ._backslash,
              uChar == ._charU,
              let lowSurrogateBitBattern = parseUnicodeHexSequence(at: readerIndex + 2)
        else {
            return (6, nil)
        }

        let isSecondByteLowSurrogate = lowSurrogateBitBattern & 0xFC00 // nil everything except first six bits
        guard isSecondByteLowSurrogate == 0xDC00 else {
            // we are in an escaped sequence. for this reason an output string must have been initialized
            return (10, nil)
        }

        let highValue = UInt32(highSurrogateBitPattern - 0xD800) * 0x400
        let lowValue = UInt32(lowSurrogateBitBattern - 0xDC00)
        let unicodeValue = highValue + lowValue + 0x10000
        guard let unicode = Unicode.Scalar(unicodeValue) else {
            return (10, nil)
        }
        return (10, unicode)
    }

    private func parseUnicodeHexSequence(at readerIndex: Int) -> UInt16? {
        guard readerIndex < endIndex - 4 else {
            return nil
        }

        guard let first = hexAsciiTo4Bits(self[readerIndex]),
              let second = hexAsciiTo4Bits(self[readerIndex + 1]),
              let third = hexAsciiTo4Bits(self[readerIndex + 2]),
              let forth = hexAsciiTo4Bits(self[readerIndex + 3])
        else {
            return nil
        }

        let firstByte = UInt16(first) << 4 | UInt16(second)
        let secondByte = UInt16(third) << 4 | UInt16(forth)
        return UInt16(firstByte) << 8 | UInt16(secondByte)
    }

    var asInt: Int {
        var total = 0
        if self[startIndex] == ._minus {
            for index in startIndex + 1 ..< endIndex {
                total = (total * 10) - Int(self[index] & 15)
            }
        } else {
            for index in startIndex ..< endIndex {
                total = (total * 10) + Int(self[index] & 15)
            }
        }
        return total
    }

    var asFloat: Float {
        get throws(JSONError) {
            let str = self[startIndex ..< endIndex].asRawString
            if let value = Float(str) {
                return value
            }
            throw .numberIsNotRepresentableInSwift(parsed: str)
        }
    }
}

func hexAsciiTo4Bits(_ ascii: UInt8) -> UInt8? {
    switch ascii {
    case 48 ... 57:
        ascii - 48
    case 65 ... 70:
        // uppercase letters
        ascii - 55
    case 97 ... 102:
        // lowercase letters
        ascii - 87
    default:
        nil
    }
}

public extension Data {
    /// Parse this data into a dictionary, array, or instance of Swift types.
    /// - Returns: An object that represents the JSON in the data. This could be a single instance, an array, or a dictionary. It can also return `nil` if, for instance, the JSON is a single `null`
    /// - Throws: If the data could not be parsed
    func asJson() throws -> Sendable? {
        try withUnsafeBytes { try TrailerJson.parse(bytes: $0) }
    }

    /// Convenience method, same as calling `try asJson() as? [String: Sendable]`
    func asJsonObject() throws -> [String: Sendable]? {
        try asJson() as? [String: Sendable]
    }

    /// Convenience method, same as calling `try asJson() as? [[String: Sendable]]`
    func asJsonArray() throws -> [[String: Sendable]]? {
        try asJson() as? [[String: Sendable]]
    }

    /// Parse this data into a root entry which can be further queried.
    /// - Returns: A ``TypedJson/Entry`` that represents the root of the data.
    /// - Throws: If the data could not be scanned. Note that this only scans the outlines of the entry and its children. Accessing the individual entries can still potentially throw.
    func asTypedJson() throws -> TypedJson.Entry? {
        try withUnsafeBytes { try TypedJson(bytes: $0).parseRoot() }
    }
}
