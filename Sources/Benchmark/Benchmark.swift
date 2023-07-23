import Foundation
import TrailerJson

@main
enum Benchmark {
    private static func show(diff: TimeInterval, label: String) {
        let ms = diff * 1000
        if ms < 0 {
            print("JSONSerialization wins by \(-ms) ms")
        } else {
            print("\(label) wins by \(ms) ms")
        }
    }

    private static let jsonData = try! Data(contentsOf: Bundle.module.url(forResource: "10mb", withExtension: "json")!)

    private static func main() throws {
        print("!!! Be sure to run this with `-c release` or using the Benchmark scheme in Xcode")

        print("Test data size:", jsonData.count, "bytes")

        try trailerJson()
        print()
        print()
        try typedJson()
    }

    private static func typedJson() throws {
        let loops = 50
        var times = [TimeInterval]()
        times.reserveCapacity(loops)

        for _ in 0 ..< loops {
            let start = Date()
            let object = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let objCTime = -start.timeIntervalSinceNow

            let start2 = Date()
            let object2 = try jsonData.asTypedJson()
            let swiftTime = -start2.timeIntervalSinceNow

            let diff = objCTime - swiftTime
            show(diff: diff, label: "TypedJson")
            times.append(diff)

            withExtendedLifetime(object) { }
            withExtendedLifetime(object2) { }
        }

        print()
        print("Concluded; on average ", terminator: "")

        let averageDiff = times.reduce(0, +) / CGFloat(loops)
        show(diff: averageDiff, label: "TypedJson")
    }

    private static func trailerJson() throws {
        let loops = 50
        var times = [TimeInterval]()
        times.reserveCapacity(loops)

        for _ in 0 ..< loops {
            let start = Date()
            let object = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let objCTime = -start.timeIntervalSinceNow

            let start2 = Date()
            let object2 = try jsonData.asJsonObject()
            let swiftTime = -start2.timeIntervalSinceNow

            let diff = objCTime - swiftTime
            show(diff: diff, label: "TrailerJson")
            times.append(diff)

            withExtendedLifetime(object) { }
            withExtendedLifetime(object2) { }
        }

        print()
        print("Concluded; on average ", terminator: "")

        let averageDiff = times.reduce(0, +) / CGFloat(loops)
        show(diff: averageDiff, label: "TrailerJson")
    }
}
