# ``TrailerJson``

A feather-weight pair of JSON decoders in Swift, with no dependencies.

## Overview

TrailerJson was originally based on a version of Swift.org's open source replacement for the Apple JSONSerialisation framework. It is currently used in [Trailer](https://github.com/ptsochantaris/trailer) and [Trailer-CLI](https://github.com/ptsochantaris/trailer-cli) and has been heavily tested and used in production with GitHub JSON v3 and v4 API payloads.

### Pros and Cons
- 👍 Ideal for parsing stable and known service API responses like GraphQL, or on embedded devices. Self contained with no setup overhead.
- Uses native Swift data types in the results, no bridging overheads
- Supports UTF8 JSON data only
- null objects, fields, or array entries are thrown away, they are not kept
- Floating point numbers are parsed as Float (i.e. not Double)
- Does not support exponent numbers, only integers and floats
- Does little to error-correct if the JSON feed isn't to spec
- 👎 Bad at parsing/verifying potentially broken JSON, APIs which may suddenly include unexpected schema entries, or when you're better served by `Decodable` types.

## Topics

### Eagerly Parsing To A Dictionary
- ``TrailerJson/TrailerJson``
- ``Data/asJson``
- ``Data/asJsonObject``
- ``Data/asJsonArray``

### Scan And Lazy Parsing
- ``TrailerJson/TypedJson``
- ``TypedJson/Entry``
- ``Data/asTypedJson``
