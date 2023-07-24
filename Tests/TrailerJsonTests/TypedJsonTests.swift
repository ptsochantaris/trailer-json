import Foundation
@testable import TrailerJson
import XCTest

final class TypedJsonTests: XCTestCase {
    func testTrickyCharacterDecoding() throws {
        let v1 = "Value with unicode 🙎🏽"
        let v2 = "🙎🏽"
        let v3 = "🙎🏽 Value with unicode"
        let v4 = "<html><tag/>\\🙎🏽weird\\\"\\slash\\🙎🏽\\</html>"
        let v5 = "x"
        let v6 = 123
        let v7: Float = 123.6
        let v8 = -60

        let testDictionary: [String: Any] = [
            "key1": v1,
            "😛": v2,
            "key3": v3,
            "key4": v4,
            "key5": v5,
            "key6": v6,
            "key7": v7,
            "key8": v8,
            "body": "",
            "arrayOfDictionaries": [
                ["a", "b"],
                ["c", "d"]
            ],
            "nestedArray": [
                "1": 1,
                "2": ["x": "y"],
                "3": 3
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: testDictionary)

        guard let entry = try data.asTypedJson() else {
            XCTFail("Nil result")
            return
        }

        try XCTAssertEqual(entry["key1"].asString, v1)
        try XCTAssertEqual(entry["😛"].asString, v2)
        try XCTAssertEqual(entry["key3"].asString, v3)
        try XCTAssertEqual(entry["key4"].asString, v4)
        try XCTAssertEqual(entry["key5"].asString, v5)
        try XCTAssertEqual(entry["key6"].asInt, v6)
        try XCTAssertEqual(entry["key7"].asFloat, v7)
        try XCTAssertEqual(entry["key8"].asInt, v8)

        if let reconstructed = try entry.parsed as? [String: Any] {
            XCTAssert(NSDictionary(dictionary: reconstructed) == NSDictionary(dictionary: testDictionary))
        } else {
            XCTFail()
        }
    }

    func testEmptyStringValue() throws {
        let testDictionary: [String: Any] = ["body": ""]

        let data = try JSONSerialization.data(withJSONObject: testDictionary)

        guard let entry = try data.asTypedJson() else {
            XCTFail("Nil result")
            return
        }

        try XCTAssertEqual(entry["body"].asString, "")

        if let reconstructed = try entry.parsed as? [String: Any] {
            XCTAssert(NSDictionary(dictionary: reconstructed) == NSDictionary(dictionary: testDictionary))
        } else {
            XCTFail()
        }
    }

    func testInvalidPayload() throws {
        func checkThrows(_ string: String?) {
            do {
                let data = string?.data(using: .utf8) ?? Data()
                _ = try data.asTypedJson()?.parsed
            } catch {
                // good
            }
        }

        checkThrows(nil)
        checkThrows(" ")
        checkThrows("   meh  ")
        checkThrows(" wut { \"a\":\"b\" }   meh  ")
        
        let test = "[5, 5.5, \"a\",[1,2],{\"a\":\"b\"}]".data(using: .utf8)!
        let json = try! test.asTypedJson()!
        
        func checkTypeError(shouldThrow: Bool, block: () throws -> Void) throws {
            do {
                try block()
                if shouldThrow {
                    XCTFail()
                }
            } catch let error as JSONError {
                if case .incorrectTypeRequested = error {
                    if !shouldThrow {
                        XCTFail()
                    }
                } else {
                    throw error
                }
            }
        }
        
        for i in 0 ..< 4 {
            try checkTypeError(shouldThrow: i != 0) {
                try _ = json[i].asInt
            }
            try checkTypeError(shouldThrow: i != 1) {
                try _ = json[i].asFloat
            }
            try checkTypeError(shouldThrow: i != 2) {
                try _ = json[i].asString
            }
            try checkTypeError(shouldThrow: i != 3) {
                try _ = json[i].asArray
            }
            try checkTypeError(shouldThrow: i != 4) {
                try _ = json[i].keys
            }
        }
    }

    func testFragmentParsing() throws {
        func parsed(_ string: String, completion: (TypedJson.Entry?) throws -> Void) throws {
            try completion(string.data(using: .utf8)!.asTypedJson())
        }

        try parsed("5") {
            try XCTAssert($0?.asInt == 5)
        }

        try parsed("  5") {
            try XCTAssert($0?.asInt == 5)
        }

        try parsed("  5  ") {
            try XCTAssert($0?.asInt == 5)
        }

        try parsed("5,3") {
            try XCTAssert($0?.asInt == 5)
        }

        try parsed("null") {
            XCTAssertNil($0)
        }

        try parsed(" null") {
            XCTAssertNil($0)
        }

        try parsed("null ") {
            XCTAssertNil($0)
        }

        try parsed("  [4,5]") {
            try XCTAssert($0?[0].asInt == 4)
            try XCTAssert($0?[1].asInt == 5)
        }

        try parsed(" [4,5]") {
            try XCTAssert($0?[0].asInt == 4)
            try XCTAssert($0?[1].asInt == 5)
        }

        try parsed("[4,5] ") {
            try XCTAssert($0?[0].asInt == 4)
            try XCTAssert($0?[1].asInt == 5)
        }

        try parsed(" [  4,null ,5  ]") {
            try XCTAssert($0?[0].asInt == 4)
            try XCTAssert($0?[1].asInt == 5)
        }

        try parsed("{ \"a\":\"b\" }   meh  ") {
            try XCTAssert($0?["a"].asString == "b")
        }

        try parsed("    { \"a\":\"b\" }   meh  ") {
            try XCTAssert($0?["a"].asString == "b")
        }

        try parsed("    { \"a\":\"b\" }") {
            try XCTAssert($0?["a"].asString == "b")
        }

        try parsed(" { \"a\"  :  \" b \"}}\"") {
            try XCTAssert($0?["a"].asString == " b ")
        }

        try parsed(" \"a\"") {
            try XCTAssert($0?.asString == "a")
        }

        try parsed(" \"a\" ") {
            try XCTAssert($0?.asString == "a")
        }

        try parsed("\"a\" ") {
            try XCTAssert($0?.asString == "a")
        }

        try parsed("\"a\"") {
            try XCTAssert($0?.asString == "a")
        }
    }

    func testMock() throws {
        let url = Bundle.module.url(forResource: "10mb", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)

        guard let object = try jsonData.asTypedJson() else {
            XCTFail("Did not parse root entry")
            return
        }

        try XCTAssertEqual(object["type"].asString, "FeatureCollection")

        let features = try object["features"].asArray
        XCTAssert(features.count == 10000)
        guard let lastFeature = features.last else {
            XCTFail()
            return
        }

        let properties = try lastFeature["properties"]
        try XCTAssertEqual(properties["BLKLOT"].asString, "0253A090")

        guard let geometry = try? lastFeature["geometry"],
              let coordinates = try? geometry["coordinates"],
              let secondList = try coordinates[0].asArray.first
        else {
            XCTFail()
            return
        }

        let number = try secondList[0].asFloat
        XCTAssert(number == -122.41356780832439)
    }

    func testNetwork() async throws {
        let url = URL(string: "http://date.jsontest.com")!
        let data = try await URLSession.shared.data(from: url).0

        guard let object = try data.asTypedJson() else {
            XCTFail("Did not parse root entry")
            return
        }

        let timeString = try object["time"].asString
        NSLog("The time is %@", timeString)
    }
}
