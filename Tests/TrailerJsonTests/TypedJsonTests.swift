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
            "key8": v8
        ]
        
        let data = try JSONSerialization.data(withJSONObject: testDictionary)

        guard let entry = try data.asTypedJson() else {
            XCTFail("Nil result")
            return
        }

        XCTAssertEqual(entry["key1"]?.asString, v1)
        XCTAssertEqual(entry["😛"]?.asString, v2)
        XCTAssertEqual(entry["key3"]?.asString, v3)
        XCTAssertEqual(entry["key4"]?.asString, v4)
        XCTAssertEqual(entry["key5"]?.asString, v5)
        XCTAssertEqual(entry["key6"]?.asInt, v6)
        XCTAssertEqual(entry["key7"]?.asFloat, v7)
        XCTAssertEqual(entry["key8"]?.asInt, v8)
        
        if let reconstructed = entry.asJsonValue as? [String: Any] {
            XCTAssert(NSDictionary(dictionary: reconstructed) == NSDictionary(dictionary: testDictionary))
        } else {
            XCTFail()
        }
    }

    func testInvalidPayload() throws {
        func checkThrows(_ string: String?) {
            do {
                let data = string?.data(using: .utf8) ?? Data()
                _ = try data.asTypedJson()
            } catch {
                // good
            }
        }

        checkThrows(nil)
        checkThrows(" ")
        checkThrows("   meh  ")
        checkThrows(" wut { \"a\":\"b\" }   meh  ")
    }

    func testFragmentParsing() throws {
        func parsed(_ string: String, completion: (TypedJson.Entry?) -> Void) throws {
            try completion(string.data(using: .utf8)!.asTypedJson())
        }

        try parsed("5") {
            XCTAssert($0?.asInt == 5)
        }

        try parsed("  5") {
            XCTAssert($0?.asInt == 5)
        }

        try parsed("  5  ") {
            XCTAssert($0?.asInt == 5)
        }

        try parsed("5,3") {
            XCTAssert($0?.asInt == 5)
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
            XCTAssert($0?[0]?.asInt == 4)
            XCTAssert($0?[1]?.asInt == 5)
        }

        try parsed(" [4,5]") {
            XCTAssert($0?[0]?.asInt == 4)
            XCTAssert($0?[1]?.asInt == 5)
        }

        try parsed("[4,5] ") {
            XCTAssert($0?[0]?.asInt == 4)
            XCTAssert($0?[1]?.asInt == 5)
        }

        try parsed(" [4,null ,5]") {
            XCTAssert($0?[0]?.asInt == 4)
            XCTAssert($0?[1]?.asInt == 5)
        }

        try parsed("{ \"a\":\"b\" }   meh  ") {
            XCTAssert($0?["a"]?.asString == "b")
        }

        try parsed("    { \"a\":\"b\" }   meh  ") {
            XCTAssert($0?["a"]?.asString == "b")
        }

        try parsed("    { \"a\":\"b\" }") {
            XCTAssert($0?["a"]?.asString == "b")
        }

        try parsed(" \"a\"") {
            XCTAssert($0?.asString == "a")
        }

        try parsed(" \"a\" ") {
            XCTAssert($0?.asString == "a")
        }

        try parsed("\"a\" ") {
            XCTAssert($0?.asString == "a")
        }

        try parsed("\"a\"") {
            XCTAssert($0?.asString == "a")
        }
    }

    func testMock() throws {
        let url = Bundle.module.url(forResource: "10mb", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)

        guard let object = try jsonData.asTypedJson() else {
            XCTFail("Did not parse root entry")
            return
        }

        XCTAssertEqual(object["type"]?.asString, "FeatureCollection")

        guard let features = object["features"]?.asArray else {
            XCTFail()
            return
        }
        XCTAssert(features.count == 10000)
        guard
            let lastFeature = features.last,
            let properties = lastFeature["properties"]
        else {
            XCTFail()
            return
        }

        XCTAssertEqual(properties["BLKLOT"]?.asString, "0253A090")

        guard let geometry = lastFeature["geometry"],
              let coordinates = geometry["coordinates"],
              let firstList = coordinates[0]?.asArray,
              let secondList = firstList.first,
              let number = secondList[0]?.asFloat
        else {
            XCTFail()
            return
        }

        XCTAssert(number == -122.41356780832439)
    }

    func testNetwork() async throws {
        let url = URL(string: "http://date.jsontest.com")!
        let data = try await URLSession.shared.data(from: url).0

        guard let object = try data.asTypedJson() else {
            XCTFail("Did not parse root entry")
            return
        }

        if let timeString = object["time"]?.asString {
            NSLog("The time is %@", timeString)
        } else {
            XCTFail("There is no spoon")
        }
    }
}
