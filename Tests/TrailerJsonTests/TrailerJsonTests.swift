import Foundation
@testable import TrailerJson
import XCTest

final class TrailerJsonTests: XCTestCase {
    func testMock() throws {
        let url = Bundle.module.url(forResource: "10mb", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let object = try jsonData.withUnsafeBytes {
            try TrailerJson.parse(bytes: $0) as? [String: Any]
        }
        guard let object else {
            XCTFail()
            return
        }

        XCTAssert(object["type"] as? String == "FeatureCollection")

        let features = object["features"] as? [[String : Any]]
        guard let features else {
            XCTFail()
            return
        }
        XCTAssert(features.count == 10000)
        guard
            let lastFeature = features.last,
            let properties = lastFeature["properties"] as? [String: Any]
        else {
            XCTFail()
            return
        }

        XCTAssert(properties["BLKLOT"] as? String == "0253A090")

        guard let geometry = lastFeature["geometry"] as? [String: Any],
              let coordinates = geometry["coordinates"] as? [Any],
              let firstList = coordinates.first as? [Any],
              let secondList = firstList.first as? [Any],
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
