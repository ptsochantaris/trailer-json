import Foundation
import Testing
@testable import TrailerJson

extension String: @retroactive Error {}

struct TrailerJsonTests {
    @Test
    func gitHubIssueList() throws {
        let url = Bundle.module.url(forResource: "issueList", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let object = try jsonData.withUnsafeBytes {
            try TrailerJson.parse(bytes: $0) as? [String: Sendable]
        }
        guard object?["data"] != nil else {
            throw "No object"
        }
    }

    @Test
    func trickyCharacterDecoding() throws {
        let v1 = "Value with unicode 🙎🏽"
        let v2 = "🙎🏽"
        let v3 = "🙎🏽 Value with unicode"
        let v4 = "<html><tag/>\\🙎🏽weird\\\"\\slash\\🙎🏽\\</html>"
        let v5 = "x"
        let v6 = 123
        let v7: Float = 123.6
        let v8 = -60
        let v9 = "/"

        let testDictionary: [String: Sendable] = [
            "key1": v1,
            "😛": v2,
            "key3": v3,
            "key4": v4,
            "key5": v5,
            "key6": v6,
            "key7": v7,
            "key8": v8,
            "key9": v9,
            "body": "",
            "arrayOfDictionaries": [
                ["a", "b"],
                ["c", "d"]
            ],
            "nestedArray": [
                "1": 1,
                "2": ["x": "y"],
                "3": 3
            ] as [String: Sendable]
        ]

        let data = try JSONSerialization.data(withJSONObject: testDictionary)

        let parsedJson = try data.asJson() as? [String: Sendable]
        #expect(parsedJson?["key1"] as? String == v1)
        #expect(parsedJson?["😛"] as? String == v2)
        #expect(parsedJson?["key3"] as? String == v3)
        #expect(parsedJson?["key4"] as? String == v4)
        #expect(parsedJson?["key5"] as? String == v5)
        #expect(parsedJson?["key6"] as? Int == v6)
        #expect(parsedJson?["key7"] as? Float == v7)
        #expect(parsedJson?["key8"] as? Int == v8)
        #expect(parsedJson?["key9"] as? String == v9)
    }

    @Test
    func invalidPayload() throws {
        func checkThrows(_ string: String?) {
            do {
                let data = string?.data(using: .utf8) ?? Data()
                _ = try data.asJson()
                throw "Invalid content '\(string ?? "<nil>")' did not throw error"
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

    @Test
    func fragmentParsing() throws {
        let data0 = "5".data(using: .utf8)!
        #expect(try data0.asJson() as? Int == 5)

        let data10 = "  5".data(using: .utf8)!
        #expect(try data10.asJson() as? Int == 5)

        let data11 = "  5  ".data(using: .utf8)!
        #expect(try data11.asJson() as? Int == 5)

        let data12 = "5,3".data(using: .utf8)!
        #expect(try data12.asJson() as? Int == 5)

        let data20 = "null".data(using: .utf8)!
        #expect(try data20.asJson() == nil)

        let data21 = "  null".data(using: .utf8)!
        #expect(try data21.asJson() == nil)

        let data22 = "null ".data(using: .utf8)!
        #expect(try data22.asJson() == nil)

        let data23 = " null ".data(using: .utf8)!
        #expect(try data23.asJson() == nil)

        let data30 = "  [4,1234]".data(using: .utf8)!
        #expect(try data30.asJson() as? [Int] == [4, 1234])

        let data31 = "[41,5] ".data(using: .utf8)!
        #expect(try data31.asJson() as? [Int] == [41, 5])

        let data32 = "[-1234,null,5]".data(using: .utf8)!
        #expect(try data32.asJson() as? [Int] == [-1234, 5])

        let data40 = "{ \"a\":\"b\" }   meh  ".data(using: .utf8)!
        let value1 = try (data40.asJson() as? [String: Sendable])?["a"] as? String
        #expect(value1 == "b")

        let data41 = "     { \"a\":\"b\" }".data(using: .utf8)!
        let value2 = try (data41.asJson() as? [String: Sendable])?["a"] as? String
        #expect(value2 == "b")

        let data42 = "     { \"a\":\"b\" }   meh  ".data(using: .utf8)!
        let value3 = try (data42.asJson() as? [String: Sendable])?["a"] as? String
        #expect(value3 == "b")

        let data50 = "  \"a\"".data(using: .utf8)!
        #expect(try data50.asJson() as? String == "a")

        let data51 = "\"a\" ".data(using: .utf8)!
        #expect(try data51.asJson() as? String == "a")

        let data52 = "\"a\"".data(using: .utf8)!
        #expect(try data52.asJson() as? String == "a")
    }

    @Test func unicodeFragment() async throws {
        let data53 = "\"Prefix 🙎🏽 followed by unicode\"".data(using: .utf8)!
        #expect(try data53.asJson() as? String == "Prefix 🙎🏽 followed by unicode")

        let data54 = "\"🙎🏽 Value with unicode\"".data(using: .utf8)!
        #expect(try data54.asJson() as? String == "🙎🏽 Value with unicode")

        let data55 = "\"🙎🏽\"".data(using: .utf8)!
        #expect(try data55.asJson() as? String == "🙎🏽")
    }

    @Test
    func mock() throws {
        let url = Bundle.module.url(forResource: "10mb", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let object = try jsonData.withUnsafeBytes {
            try TrailerJson.parse(bytes: $0) as? [String: Sendable]
        }
        guard let object else {
            throw "No object"
        }

        #expect(object["type"] as? String == "FeatureCollection")

        let features = object["features"] as? [[String: Sendable]]
        guard let features else {
            throw "No features"
        }
        #expect(features.count == 10000)
        guard
            let lastFeature = features.last,
            let properties = lastFeature["properties"] as? [String: Sendable]
        else {
            throw "No properties"
        }

        #expect(properties["BLKLOT"] as? String == "0253A090")

        guard let geometry = lastFeature["geometry"] as? [String: Sendable],
              let coordinates = geometry["coordinates"] as? [Sendable],
              let firstList = coordinates.first as? [Sendable],
              let secondList = firstList.first as? [Sendable],
              let number = secondList.first as? Float
        else {
            throw "No coordinates"
        }

        #expect(number == -122.41356780832439)
    }

    @Test
    func network() async throws {
        let url = URL(string: "http://date.jsontest.com")!
        let data = try await URLSession.shared.data(from: url).0

        if let json = try data.asJsonObject(),
           let timeString = json["time"] as? String {
            NSLog("The time is %@", timeString)
        } else {
            throw "There is no spoon"
        }
    }
}
