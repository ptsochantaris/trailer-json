<img src="https://ptsochantaris.github.io/trailer/TrailerJsonLogo.webp" alt="Logo" width=256 align="right">

# TrailerJson

A feather-weight JSON decoder in Swift with no dependencies. Is is roughly based on a version of Swift.org's open source replacement for the Apple JSONSerialisation framework.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fptsochantaris%2Ftrailer-json%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ptsochantaris/trailer-json) [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fptsochantaris%2Ftrailer-json%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ptsochantaris/trailer-json)

Currently used in
- [Trailer](https://github.com/ptsochantaris/trailer)
- [Trailer-CLI](https://github.com/ptsochantaris/trailer-cli)
- Heavily tested and used in production with GitHub JSON v3 and v4 API payloads.

Detailed docs [can be found here](https://swiftpackageindex.com/ptsochantaris/trailer-json/documentation)

### The parsers
There are two parsers in this package:
- `TrailerJson` will parse the entire data blob in one go, producing a dictionary much like JSONSerialization does.
- `TypedJson` will quickly scan the data blob and provide results of type `Entry`, which have typed access (`asInt`, `asFloat`, `asBool`, `asString`, etc) and parses that data only when accessed.

### Compared to JSONSerialisation (when running optimised)
The `TrailerJson` parser performs almost equivalently _BUT!_ the results are all native Swift types, so using those results incurs no bridging or copying costs, which is a major performance bonus.

The `TypedJson` parser is much faster, and ideal if you are only accessing a subset of the JSON data. It also makes it possible to parallelise the subsequent parsing in threads if needed.

### Compared to Swift.org's version
Because it heavily trades features for decode-only performance, and that it returns native Swift types without the need to bridge them to ObjC for compatibility, it is by definition faster than the Swift.org version.

### TL;DR
👍 Ideal for parsing stable and known service API responses like GraphQL, or on embedded devices. Self contained with no setup overhead.

👎 Bad at parsing/verifying potentially broken JSON, APIs which may suddenly include unexpected schema entries, or when you're better served by `Decodable` types.

### Examples
```
let url = URL(string: "http://date.jsontest.com")!
let data = try await URLSession.shared.data(from: url).0
```

```
// TrailerJson - parse in one go to [String: Any]
if let json = try data.asJsonObject(),      // parse as dictionary
   let timeField = json["time"],
   let timeString = timeField as? String {
   
    print("The time is", timeString)
}
```

```
// TypedJson - scan the data and only parse 'time' as a String
if let json = try data.asTypedJson(),         // scan data
   let timeField = try? json["time"],
   let timeString = try? timeField.asString { // parse field
   
    print("The time is", timeString)
}
```

TrailerJson works directly with raw bytes so it can accept data from any type that exposes a raw byte buffer, such as NIO's ByteBuffer, without expensive casting or copies in-between:

```
let byteBuffer: ByteBuffer = ...
```

```
// TrailerJson
let jsonArray = try byteBuffer.withVeryUnsafeBytes { 
    try TrailerJson.parse(bytes: $0) as? [Any]
}
let number = jsonArray[1] as? Int
print(number)
```

```        
// TypedJson
let jsonArray = try byteBuffer.withVeryUnsafeBytes { 
    try TypedJson.parse(bytes: $0)
}
let number = try jsonArray[1].asInt
print(number)
```

```        
// TypedJson - using bytesNoCopy, lazy parsing (max performance, but with caveats!)
let number = try byteBuffer.withVeryUnsafeBytes { 

    // jsonArray and any Entry from it must not be accessed outside the closure 
    let jsonArray = try TypedJson.parse(bytesNoCopy: $0)

    // `secondEntry` reads from the original bytes, so it can't escape 
    let secondEntry = try jsonArray[1]

    // but parsed values can escape
    return try secondEntry.asInt
}
print(number)        
```

If you need to pass a TypedJson entry into a method that needs an untyped dictionary, you can eagerly parse a chunk by using the `parse` method - but beware that this can be slow for large sets of data, so it is best used for very specific cases!

```
// TypedJson - eager parsing (slowest performance)
let numberArray = try byteBuffer.withVeryUnsafeBytes { 

    // numbers and any Entry from it must not be accessed outside the closure 
    let numbers = try TypedJson.parse(bytes: $0)

    // but parsed value can escape - note that parsing the whole document would be 
    // very slow, so for cases like these the `TrailerJson` parser is 10x faster!
    return try numbers.parsed as! [Int]
}
let number = numberArray[1]
print(number)        
```

### Notes
- Supports UTF8 JSON data only
- Uses native Swift data types in the results, no bridging overheads
- null objects, fields, or array entries are thrown away, they are not kept
- Floating point numbers are parsed as Float (i.e. not Double)
- Does not support exponent numbers, only integers and floats
- Does little to error-correct if the JSON feed isn't to spec

## License
Copyright (c) 2023 Paul Tsochantaris. [Licensed under Apache License v2.0 with Runtime Library Exception](https://www.apache.org/licenses/LICENSE-2.0.html), as per the [open source material it is based on](https://github.com/apple/swift-corelibs-foundation/blob/bafd3d0f800397a15a3d092979ee7e788082feee/Sources/Foundation/JSONSerialization.swift)
