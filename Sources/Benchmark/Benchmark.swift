import Foundation
import TrailerJson

@main
enum Benchmark {
    private static func show(diffs: (avg: TimeInterval, objc: TimeInterval, swift: TimeInterval), label: String) {
        print("* \(label)")
        print("  Totals: JSONSerialization: \(diffs.objc * 1000), \(label): \(diffs.swift * 1000)")

        let ms = diffs.avg * 1000
        if ms < 0 {
            print("  JSONSerialization wins by \(-ms) ms")
        } else {
            print("  \(label) wins by \(ms) ms")
        }
    }

    private static let jsonData = try! Data(contentsOf: Bundle.module.url(forResource: "10mb", withExtension: "json")!)

    private static func main() throws {
        print("!!! Be sure to run this with `-c release` or using the Benchmark scheme in Xcode")

        print("Test data size:", jsonData.count, "bytes")

        print()
        try trailerJson()
        print()
        try typedJson()
        print()
    }

    private static func typedJson() throws {
        let loops = 50

        var times = [TimeInterval]()
        times.reserveCapacity(loops)

        var swiftTimes = [TimeInterval]()
        swiftTimes.reserveCapacity(loops)

        var objCTimes = [TimeInterval]()
        objCTimes.reserveCapacity(loops)

        for _ in 0 ..< loops {
            let start = Date()
            let object = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let objCTime = -start.timeIntervalSinceNow

            let start2 = Date()
            let object2 = try jsonData.asTypedJson()
            let swiftTime = -start2.timeIntervalSinceNow

            times.append(objCTime - swiftTime)
            swiftTimes.append(swiftTime)
            objCTimes.append(objCTime)

            withExtendedLifetime(object) {}
            withExtendedLifetime(object2) {}
        }

        let averageDiff = times.reduce(0, +) / CGFloat(loops)
        let averageObjcDiff = objCTimes.reduce(0, +) / CGFloat(loops)
        let averageSwiftDiff = swiftTimes.reduce(0, +) / CGFloat(loops)
        show(diffs: (averageDiff, averageObjcDiff, averageSwiftDiff), label: "TypedJson")
    }

    private static func trailerJson() throws {
        let loops = 50

        var times = [TimeInterval]()
        times.reserveCapacity(loops)

        var swiftTimes = [TimeInterval]()
        swiftTimes.reserveCapacity(loops)

        var objCTimes = [TimeInterval]()
        objCTimes.reserveCapacity(loops)

        for _ in 0 ..< loops {
            let start = Date()
            let object = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let objCTime = -start.timeIntervalSinceNow

            let start2 = Date()
            let object2 = try jsonData.asJsonObject()
            let swiftTime = -start2.timeIntervalSinceNow

            times.append(objCTime - swiftTime)
            swiftTimes.append(swiftTime)
            objCTimes.append(objCTime)

            withExtendedLifetime(object) {}
            withExtendedLifetime(object2) {}
        }

        let averageDiff = times.reduce(0, +) / CGFloat(loops)
        let averageObjcDiff = objCTimes.reduce(0, +) / CGFloat(loops)
        let averageSwiftDiff = swiftTimes.reduce(0, +) / CGFloat(loops)
        show(diffs: (averageDiff, averageObjcDiff, averageSwiftDiff), label: "TrailerJson")
    }
}
