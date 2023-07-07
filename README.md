# TrailerJson

A feather-weight JSON decoder in Swift, roughly based on a version of Swift.org's open source replacement for the Apple JSONSerialisation framework.

It is currently used in [Trailer](https://github.com/ptsochantaris/trailer) and [Trailer-CLI](https://github.com/ptsochantaris/trailer-cli) and has been heavily tested and used in production with GitHub JSON v3 and v4 API payloads.

#### Compared to JSONSerialisation (when running optimised)
It performs almost equivalently _BUT!_ the results are all native Swift types, so using those results incurs no bridging or copying costs, which is a major performance bonus.

#### Compared to Swift.org's version
Because it heavily trades features for decode-only performance, and that it returns native Swift types without the need to bridge them to ObjC for compatibility, it is by definition faster than the Swift.org version.

#### TL;DR

👍 Ideal for parsing stable and known service API responses like GraphQL, or on embedded devices. Self contained with no setup overhead.

👎 Bad at parsing/verifying potentially broken JSON, or APIs which may suddenly include unexpected schema entries.

#### Example
```
        let url = URL(string: "http://date.jsontest.com")!
        let data = try await URLSession.shared.data(from: url).0
        
        if let json = try data.asJsonObject(),
           let timeString = json["time"] as? String {
            NSLog("The time is %@", timeString)
        } else {
            XCTFail("There is no spoon")
        }
```

#### Notes
- Supports UTF8 JSON data only
- Uses native Swift data types in the results, no bridging overheads
- null objects, fields, or array entries are thrown away, they are not kept
- Floating point numbers are parsed as Float (i.e. not Double)
- Does not support exponent numbers, only integers and floats
- Does little to error-correct if the JSON feed isn't to spec

#### License
Copyright (c) 2023 Paul Tsochantaris. [Licensed under Apache License v2.0 with Runtime Library Exception](https://www.apache.org/licenses/LICENSE-2.0.html), as per the [open source material it is based on](https://github.com/apple/swift-corelibs-foundation/blob/bafd3d0f800397a15a3d092979ee7e788082feee/Sources/Foundation/JSONSerialization.swift)
