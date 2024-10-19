import Foundation
@testable import TrailerJson
import XCTest

final class TrailerJsonTests: XCTestCase {
    func testTrickyCharacterDecoding() throws {
        let v1 = "Value with unicode 🙎🏽"
        let v2 = "🙎🏽"
        let v3 = "🙎🏽 Value with unicode"
        let v4 = "<html><tag/>\\🙎🏽weird\\slash\\🙎🏽\\</html>"
        let data = try JSONSerialization.data(withJSONObject: [
            "key1": v1,
            "key2": v2,
            "key3": v3,
            "key4": v4
        ])
        let parsedJson = try data.asJson() as? [String: String]
        XCTAssert(parsedJson?["key1"] as? String == v1)
        XCTAssert(parsedJson?["key2"] as? String == v2)
        XCTAssert(parsedJson?["key3"] as? String == v3)
        XCTAssert(parsedJson?["key4"] as? String == v4)
    }

    func testInvalidPayload() throws {
        func checkThrows(_ string: String?) {
            do {
                let data = string?.data(using: .utf8) ?? Data()
                _ = try data.asJson()
                XCTFail("Invalid content '\(string ?? "<nil>")' did not throw error")
            } catch {
                // good
            }
        }

        checkThrows(nil)
        checkThrows(" ")
        checkThrows(" 5a ")
        checkThrows(" a ")
        checkThrows("   meh  ")
        checkThrows(" wut { \"a\":\"b\" }   meh  ")
    }

    func testFragmentParsing() throws {
        let data0 = "5".data(using: .utf8)!
        XCTAssertEqual(try data0.asJson() as? Int, 5)

        let data10 = "  5".data(using: .utf8)!
        XCTAssert(try data10.asJson() as? Int == 5)

        let data11 = "  5  ".data(using: .utf8)!
        XCTAssert(try data11.asJson() as? Int == 5)

        let data12 = "5,3".data(using: .utf8)!
        XCTAssert(try data12.asJson() as? Int == 5)

        let data20 = "null".data(using: .utf8)!
        XCTAssert(try data20.asJson() == nil)

        let data21 = "  null".data(using: .utf8)!
        XCTAssert(try data21.asJson() == nil)

        let data22 = "null ".data(using: .utf8)!
        XCTAssert(try data22.asJson() == nil)

        let data23 = " null ".data(using: .utf8)!
        XCTAssert(try data23.asJson() == nil)

        let data30 = "  [4,1234]".data(using: .utf8)!
        XCTAssertEqual(try data30.asJson() as? [Int], [4, 1234])

        let data31 = "[41,5] ".data(using: .utf8)!
        XCTAssertEqual(try data31.asJson() as? [Int], [41, 5])

        let data32 = "[-1234,null,5]".data(using: .utf8)!
        XCTAssertEqual(try data32.asJson() as? [Int], [-1234, 5])

        let data40 = "{ \"a\":\"b\" }   meh  ".data(using: .utf8)!
        let value1 = try (data40.asJson() as? [String: Sendable])?["a"] as? String
        XCTAssert(value1 == "b")

        let data41 = "     { \"a\":\"b\" }".data(using: .utf8)!
        let value2 = try (data41.asJson() as? [String: Sendable])?["a"] as? String
        XCTAssert(value2 == "b")

        let data42 = "     { \"a\":\"b\" }   meh  ".data(using: .utf8)!
        let value3 = try (data42.asJson() as? [String: Sendable])?["a"] as? String
        XCTAssert(value3 == "b")

        let data50 = "  \"a\"".data(using: .utf8)!
        XCTAssert(try data50.asJson() as? String == "a")

        let data51 = "\"a\" ".data(using: .utf8)!
        XCTAssert(try data51.asJson() as? String == "a")

        let data52 = "\"a\"".data(using: .utf8)!
        XCTAssert(try data52.asJson() as? String == "a")
    }

    func testMock() throws {
        let url = Bundle.module.url(forResource: "10mb", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let object = try jsonData.withUnsafeBytes {
            try TrailerJson.parse(bytes: $0) as? [String: Sendable]
        }
        guard let object else {
            XCTFail()
            return
        }

        XCTAssert(object["type"] as? String == "FeatureCollection")

        let features = object["features"] as? [[String: Sendable]]
        guard let features else {
            XCTFail()
            return
        }
        XCTAssert(features.count == 10000)
        guard
            let lastFeature = features.last,
            let properties = lastFeature["properties"] as? [String: Sendable]
        else {
            XCTFail()
            return
        }

        XCTAssert(properties["BLKLOT"] as? String == "0253A090")

        guard let geometry = lastFeature["geometry"] as? [String: Sendable],
              let coordinates = geometry["coordinates"] as? [Sendable],
              let firstList = coordinates.first as? [Sendable],
              let secondList = firstList.first as? [Sendable],
              let number = secondList.first as? Float
        else {
            XCTFail()
            return
        }

        XCTAssert(number == -122.41356780832439)
    }

    func testNetwork() async throws {
        let url = URL(string: "http://date.jsontest.com")!
        let data = try await URLSession.shared.data(from: url).0

        if let json = try data.asJsonObject(),
           let timeString = json["time"] as? String {
            NSLog("The time is %@", timeString)
        } else {
            XCTFail("There is no spoon")
        }
    }
}
