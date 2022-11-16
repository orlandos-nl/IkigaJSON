# IkigaJSON

IkigaJSON is a really fast JSON parser. It performed ~4x faster than Foundation in our tests when decoding a type from JSON.

Aside from being more performant, IkigaJSON has a much lower and more stable memory footprint, too! By design, IkigaJSON scales better on larger JSON payloads than most other JSON implementations. All while providing an easy to use API with Codable support.

[Join our Discord](https://discord.gg/H6799jh) for any questions and friendly banter.

[Read the Docs](https://orlandos.nl/docs/ikigajson)

### Server-Side Swift

The above performance statement was tested on Foundation for macOS and iOS. If you're using Swift on Linux with Swift 5.5, your performance is slightly better if you use the new Foundation for Linux. Swift 5.5 does not improve Foundation's JSON performance on macOS or iOS. IkigaJSON performs increasingly better than Linux’ Foundation JSON the bigger your JSON payload gets.

### Adding the dependency

The 1.x versions are reliant on SwiftNIO 1.x, and for SwiftNIO 2.x support use the 2.x versions of IkigaJSON.

SPM:

```swift
// SwiftNIO 1.x
.package(url: "https://github.com/orlandos-nl/IkigaJSON.git", from: "1.0.0"),
// Or, for SwiftNIO 2
.package(url: "https://github.com/orlandos-nl/IkigaJSON.git", from: "2.0.0"),
```

Cocoapods:

```cocoapods
pod 'IkigaJSON', '~> 1.0'
# Or, for SwiftNIO 2
pod 'IkigaJSON', '~> 2.0'
```

### Usage

```swift
import IkigaJSON

struct User: Codable {
    let id: Int
    let name: String
}

let data = Data()
var decoder = IkigaJSONDecoder()
let user = try decoder.decode(User.self, from: data)
```

### In Vapor 4

Conform Ikiga to Vapor 4's protocols like so:

```swift
extension IkigaJSONEncoder: ContentEncoder {
    public func encode<E: Encodable>(
        _ encodable: E,
        to body: inout ByteBuffer,
        headers: inout HTTPHeaders
    ) throws {
        headers.contentType = .json
        try self.encodeAndWrite(encodable, into: &body)
    }
}

extension IkigaJSONDecoder: ContentDecoder {
    public func decode<D: Decodable>(
        _ decodable: D.Type,
        from body: ByteBuffer,
        headers: HTTPHeaders
    ) throws -> D {
        return try self.decode(D.self, from: body)
    }
}
```

Register the encoder/decoder to Vapor like so:

```swift
var decoder = IkigaJSONDecoder()
decoder.settings.dateDecodingStrategy = .iso8601
ContentConfiguration.global.use(decoder: decoder, for: .json)

var encoder = IkigaJSONEncoder()
encoder.settings.dateDecodingStrategy = .iso8601
ContentConfiguration.global.use(encoder: encoder, for: .json)
```

### Raw JSON

IkigaJSON supports raw JSON types (JSONObject and JSONArray) like many other libraries do, alongside the codable API described above. The critical difference is that IkigaJSON edits the JSON inline, so there's no additional conversion overhead from Swift type to JSON.

```swift
var user = JSONObject()
user["username"] = "Joannis"
user["roles"] = ["admin", "moderator", "user"] as JSONArray
user["programmer"] = true

print(user.string)

print(user["username"].string)
// OR
print(user["username"] as? String)
```

### SwiftNIO support

The encoders and decoders support SwiftNIO.

```swift
var user = try JSONObject(buffer: byteBuffer)
print(user["username"].string)
```

We also have added the ability to use the IkigaJSONEncoder and IkigaJSONDecoder with JSON.

```swift
let user = try decoder.decode([User].self, from: byteBuffer)
```

```swift
var buffer: ByteBuffer = ...

try encoder.encodeAndWrite(user, into: &buffer)
```

The above method can be used to stream multiple entities from a source like a database over the socket asynchronously. This can greatly reduce memory usage.

### Performance

By design you can build on top of any data storage as long as it exposes a pointer API. This way, IkigaJSON doesn't (need to) copy any data from your buffer keeping it lightweight. The entire parser can function with only 1 memory allocation and allows for reusing the Decoder to reuse the memory allocation.

This allocation (called the JSONDescription) acts as a filter over the original dataset, indicating to IkigaJSON where keys, values and objects start/end. Therefore IkigaJSON can do really fast inline mutations, and provide objects such as JSONObject/JSONDescription that are extremely performant at reading individual values. This also allows IkigaJSON to decode from its own helper types such as JSONObject and JSONArray, since it doesn't need to regenerate a JSONDescription and has the original buffer at hand.

### Support

- All decoding strategies that Foundation supports
- Unicode
- Codable
- Escaping
- Performance 🚀
- Date/Data _encoding_ strategies
- Raw JSON APIs (non-codable)
- Codable decoding from `JSONObject` and `JSONArray`
- `\u` escaped unicode characters

### Media

[Architecture](https://medium.com/@joannis.orlandos/the-road-to-very-fast-json-parsing-in-swift-4a0225c0313c)
