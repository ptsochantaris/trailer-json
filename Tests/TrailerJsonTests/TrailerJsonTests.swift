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
        XCTAssertNotNil(object)
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
