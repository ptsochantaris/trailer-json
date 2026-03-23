import Foundation
import Testing
@testable import TrailerJson

struct TypedJsonTests {
    @Test
    func `git hub issue list`() throws {
        let url = try #require(Bundle.module.url(forResource: "issueList", withExtension: "json"))
        let jsonData = try Data(contentsOf: url)
        let object = try jsonData.asTypedJson()

        guard object?.potentialObject(named: "data") != nil else {
            throw "No object"
        }
    }

    @Test
    func `tricky character decoding`() throws {
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

        guard let entry = try data.asTypedJson() else {
            throw "Nil result"
        }

        try #expect(entry["key1"].asString == v1)
        try #expect(entry["😛"].asString == v2)
        try #expect(entry["key3"].asString == v3)
        try #expect(entry["key4"].asString == v4)
        try #expect(entry["key5"].asString == v5)
        try #expect(entry["key6"].asInt == v6)
        try #expect(entry["key7"].asFloat == v7)
        try #expect(entry["key8"].asInt == v8)
        try #expect(entry["key9"].asString == v9)

        if let reconstructed = try entry.parsed as? [String: Sendable] {
            #expect(NSDictionary(dictionary: reconstructed) == NSDictionary(dictionary: testDictionary))
        } else {
            throw "Not macthing"
        }
    }

    @Test
    func `empty string value`() throws {
        let testDictionary: [String: Sendable] = ["body": ""]

        let data = try JSONSerialization.data(withJSONObject: testDictionary)

        guard let entry = try data.asTypedJson() else {
            throw "Nil result"
        }

        try #expect(entry["body"].asString == "")

        if let reconstructed = try entry.parsed as? [String: Sendable] {
            #expect(NSDictionary(dictionary: reconstructed) == NSDictionary(dictionary: testDictionary))
        } else {
            throw "Not macthing"
        }
    }

    @Test
    func `invalid payload`() throws {
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
        checkThrows(" 5a ")
        checkThrows(" a ")
        checkThrows("   meh  ")
        checkThrows(" wut { \"a\":\"b\" }   meh  ")

        let test = "[5, 5.5, \"a\",[1,2],{\"a\":\"b\"}]".data(using: .utf8)!
        let typed = try test.asTypedJson()
        let json = try #require(typed)

        func checkTypeError(shouldThrow: Bool, block: () throws -> Void) throws {
            do {
                try block()
                if shouldThrow {
                    throw "Should have thrown"
                }
            } catch let error as JSONError {
                if case .incorrectTypeRequested = error {
                    if !shouldThrow {
                        throw "Should not have thrown"
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

    @Test
    func `fragment parsing`() throws {
        func parsed(_ string: String, completion: (TypedJson.Entry?) throws -> Void) throws {
            let typed = try string.data(using: .utf8)?.asTypedJson()
            try completion(typed)
        }

        try parsed("5") {
            try #expect($0?.asInt == 5)
        }

        try parsed("  5") {
            try #expect($0?.asInt == 5)
        }

        try parsed("  5  ") {
            try #expect($0?.asInt == 5)
        }

        try parsed("5,3") {
            try #expect($0?.asInt == 5)
        }

        try parsed("null") {
            #expect($0 == nil)
        }

        try parsed(" null") {
            #expect($0 == nil)
        }

        try parsed("null ") {
            #expect($0 == nil)
        }

        try parsed("  [14,5]") {
            try #expect($0?[0].asInt == 14)
            try #expect($0?[1].asInt == 5)
        }

        try parsed(" [45,5]") {
            try #expect($0?[0].asInt == 45)
            try #expect($0?[1].asInt == 5)
        }

        try parsed("[4,5] ") {
            try #expect($0?[0].asInt == 4)
            try #expect($0?[1].asInt == 5)
        }

        try parsed(" [  -1234,null ,5, [\"x\", {\"a\": [\"hi\", \"there\"]}]]") {
            try #expect($0?[0].asInt == -1234)
            try #expect($0?[1].asInt == 5)

            #expect($0?.potentialInt(at: 1) == 5)
            #expect($0?.potentialArray(at: 2)?[1].potentialArray(named: "a")?.first?.potentialString == "hi")

            let obj = $0?.potentialObject(at: 1)
            #expect(obj?.potentialInt == 5)
            #expect(obj?.potentialBool == nil)
            #expect(obj?.potentialArray == nil)
            #expect(obj?.potentialObject(at: 1) == nil)
            #expect(obj?.potentialObject(named: "fnord") == nil)
            #expect(obj?.potentialFloat == nil)
        }

        try parsed("{ \"a\":\"b\" }   meh  ") {
            try #expect($0?["a"].asString == "b")
            #expect($0?.potentialString(named: "a") == "b")
            #expect($0?.potentialInt(named: "a") == nil)
            #expect($0?.potentialString(named: "fnord") == nil)
            #expect($0?.potentialString(named: "a") == "b")
        }

        try parsed("    { \"a\":\"b\" }   meh  ") {
            try #expect($0?["a"].asString == "b")
        }

        try parsed("    { \"a\":\"b\" }") {
            try #expect($0?["a"].asString == "b")
        }

        try parsed(" { \"a\"  :  \" b \"}}\"") {
            try #expect($0?["a"].asString == " b ")
        }

        try parsed(" \"a\"") {
            try #expect($0?.asString == "a")
        }

        try parsed(" \"a\" ") {
            try #expect($0?.asString == "a")
        }

        try parsed("\"a\" ") {
            try #expect($0?.asString == "a")
        }

        try parsed("\"a\"") {
            try #expect($0?.asString == "a")
        }
    }

    @Test
    func `escaped quote ending`() throws {
        let json = "{ \"data\": \"1\\\\2\\\\\" }"
        let typed = try json.data(using: .utf8)?.asTypedJson()
        let object = try #require(typed)
        #expect(object.potentialString(named: "data") == "1\\2\\")
    }

    @Test
    func mock() throws {
        let url = try #require(Bundle.module.url(forResource: "10mb", withExtension: "json"))
        let jsonData = try Data(contentsOf: url)

        guard let object = try jsonData.asTypedJson() else {
            throw "Did not parse root entry"
        }

        try #expect(object["type"].asString == "FeatureCollection")

        let features = try object["features"].asArray
        #expect(features.count == 10000)
        guard let lastFeature = features.last else {
            throw "Did not parse features"
        }

        let properties = try lastFeature["properties"]
        try #expect(properties["BLKLOT"].asString == "0253A090")

        guard let geometry = try? lastFeature["geometry"],
              let coordinates = try? geometry["coordinates"],
              let secondList = try coordinates[0].asArray.first
        else {
            throw "Did not parse geometry"
        }

        let number = try secondList[0].asFloat
        #expect(number == -122.41356780832439)
    }

    @Test
    func network() async throws {
        let url = try #require(URL(string: "https://timeapi.io/api/v1/time/current/coordinate?latitude=38.9&longitude=-77.03"))
        let data = try await URLSession.shared.data(from: url).0

        guard let object = try data.asTypedJson() else {
            throw "Did not parse root entry"
        }

        #expect(try object["timezone"].asString == "America/New_York")

        let timeString = try object["time"].asString
        NSLog("The time is %@", timeString)
    }
}
