# IkigaJSON

IkigaJSON is a really fast JSON parser. It performed ~4x faster in our tests when decoding a type from JSON.

### Adding the dependency

SPM:

```swift
.package(url: "https://github.com/Ikiga/IkigaJSON.git", from: "1.0.0"),
```

Cocoapods:

```swift
pod 'IkigaJSON', '~> 1.0'
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

### Performance

By design you can build on top of any data storage as long as it exposes a pointer API. This way, IkigaJSON doesn't (need to) copy any data from your buffer keeping it lightweight. The entire parser can function with only 1 memory allocation and allows for reusing the Decoder to reuse the memory allocation.

### Support

- All decoding strategies that Foundation supports
- Unicode
- Codable
- Escaping
- Performance 🚀

TODO:

- Date/Data _encoding_ strategies
- Raw JSON APIs (non-codable)
- `\u` escaped unicode characters

### Media

[Architecture](https://medium.com/@joannis.orlandos/the-road-to-very-fast-json-parsing-in-swift-4a0225c0313c)
