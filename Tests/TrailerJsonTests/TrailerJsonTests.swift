import Foundation
@testable import TrailerJson
import XCTest

final class TrailerJsonTests: XCTestCase {
    func testMock() throws {
        let url = Bundle.module.url(forResource: "10mb", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let object = try jsonData.withUnsafeBytes { buffer in
            try TrailerJson(bytes: buffer).parse()
        }
        XCTAssertNotNil(object)
    }

    func testNetwork() async throws {
        let url = URL(string: "http://date.jsontest.com")!
        let data = try await URLSession.shared.data(from: url).0
        let json = try data.withUnsafeBytes {
            try TrailerJson(bytes: $0).parse() as? JSON
        }
        if let timeString = json?["time"] as? String {
            NSLog("The time is %@", timeString)
        } else {
            XCTFail("There is no spoon")
        }
    }
}
