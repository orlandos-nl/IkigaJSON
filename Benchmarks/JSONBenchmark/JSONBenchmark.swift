import Benchmark
import Foundation
import IkigaJSON

#if canImport(FoundationEssentials)
  import FoundationEssentials
#endif

// MARK: - Test Data Structures

struct SmallUser: Codable {
  let id: Int
  let name: String
  let email: String
  let active: Bool
}

struct MediumUser: Codable {
  let id: Int
  let username: String
  let email: String
  let firstName: String
  let lastName: String
  let age: Int
  let isActive: Bool
  let createdAt: String
  let roles: [String]
  let settings: Settings

  struct Settings: Codable {
    let theme: String
    let notifications: Bool
    let language: String
  }
}

struct LargePayload: Codable {
  let users: [MediumUser]
  let metadata: Metadata
  let tags: [String]

  struct Metadata: Codable {
    let total: Int
    let page: Int
    let perPage: Int
    let totalPages: Int
  }
}

// MARK: - Sample JSON Data

let smallJSON = """
  {
      "id": 12345,
      "name": "John Doe",
      "email": "john.doe@example.com",
      "active": true
  }
  """.data(using: .utf8)!

let mediumJSON = """
  {
      "id": 12345,
      "username": "johndoe",
      "email": "john.doe@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "age": 32,
      "isActive": true,
      "createdAt": "2024-01-15T10:30:00Z",
      "roles": ["admin", "user", "moderator"],
      "settings": {
          "theme": "dark",
          "notifications": true,
          "language": "en-US"
      }
  }
  """.data(using: .utf8)!

let largeJSON: Data = {
  let users = (0..<100).map { i in
    """
    {
        "id": \(i),
        "username": "user\(i)",
        "email": "user\(i)@example.com",
        "firstName": "First\(i)",
        "lastName": "Last\(i)",
        "age": \(20 + (i % 50)),
        "isActive": \(i % 2 == 0),
        "createdAt": "2024-01-15T10:30:00Z",
        "roles": ["user", "member"],
        "settings": {
            "theme": "light",
            "notifications": false,
            "language": "en-US"
        }
    }
    """
  }.joined(separator: ",\n")

  return """
    {
        "users": [\(users)],
        "metadata": {
            "total": 100,
            "page": 1,
            "perPage": 100,
            "totalPages": 1
        },
        "tags": ["api", "users", "export", "batch", "data"]
    }
    """.data(using: .utf8)!
}()

// Pre-create encoded data for encoding benchmarks
let smallUser = SmallUser(id: 12345, name: "John Doe", email: "john.doe@example.com", active: true)
let mediumUser = MediumUser(
  id: 12345,
  username: "johndoe",
  email: "john.doe@example.com",
  firstName: "John",
  lastName: "Doe",
  age: 32,
  isActive: true,
  createdAt: "2024-01-15T10:30:00Z",
  roles: ["admin", "user", "moderator"],
  settings: .init(theme: "dark", notifications: true, language: "en-US")
)

let largePayload: LargePayload = {
  let users = (0..<100).map { i in
    MediumUser(
      id: i,
      username: "user\(i)",
      email: "user\(i)@example.com",
      firstName: "First\(i)",
      lastName: "Last\(i)",
      age: 20 + (i % 50),
      isActive: i % 2 == 0,
      createdAt: "2024-01-15T10:30:00Z",
      roles: ["user", "member"],
      settings: .init(theme: "light", notifications: false, language: "en-US")
    )
  }
  return LargePayload(
    users: users,
    metadata: .init(total: 100, page: 1, perPage: 100, totalPages: 1),
    tags: ["api", "users", "export", "batch", "data"]
  )
}()

// MARK: - Benchmarks

let benchmarks: @Sendable () -> Void = {
  // ============================================
  // DECODING BENCHMARKS
  // ============================================

  Benchmark.defaultConfiguration = .init(
    metrics: [
      .cpuTotal,
      .wallClock,
      .throughput,
      .peakMemoryResident,
      .mallocCountTotal,
    ],
    warmupIterations: 10
  )

  // --- Small Payload Decoding ---

  Benchmark("Decode Small - Foundation") { benchmark in
    let decoder = JSONDecoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! decoder.decode(SmallUser.self, from: smallJSON))
    }
  }

  Benchmark("Decode Small - IkigaJSON") { benchmark in
    let decoder = IkigaJSONDecoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! decoder.decode(SmallUser.self, from: smallJSON))
    }
  }

  // --- Medium Payload Decoding ---

  Benchmark("Decode Medium - Foundation") { benchmark in
    let decoder = JSONDecoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! decoder.decode(MediumUser.self, from: mediumJSON))
    }
  }

  Benchmark("Decode Medium - IkigaJSON") { benchmark in
    let decoder = IkigaJSONDecoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! decoder.decode(MediumUser.self, from: mediumJSON))
    }
  }

  // --- Large Payload Decoding ---

  Benchmark("Decode Large - Foundation") { benchmark in
    let decoder = JSONDecoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! decoder.decode(LargePayload.self, from: largeJSON))
    }
  }

  Benchmark("Decode Large - IkigaJSON") { benchmark in
    let decoder = IkigaJSONDecoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! decoder.decode(LargePayload.self, from: largeJSON))
    }
  }

  // ============================================
  // ENCODING BENCHMARKS
  // ============================================

  // --- Small Payload Encoding ---

  Benchmark("Encode Small - Foundation") { benchmark in
    let encoder = JSONEncoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! encoder.encode(smallUser))
    }
  }

  Benchmark("Encode Small - IkigaJSON") { benchmark in
    let encoder = IkigaJSONEncoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! encoder.encode(smallUser))
    }
  }

  // --- Medium Payload Encoding ---

  Benchmark("Encode Medium - Foundation") { benchmark in
    let encoder = JSONEncoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! encoder.encode(mediumUser))
    }
  }

  Benchmark("Encode Medium - IkigaJSON") { benchmark in
    let encoder = IkigaJSONEncoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! encoder.encode(mediumUser))
    }
  }

  // --- Large Payload Encoding ---

  Benchmark("Encode Large - Foundation") { benchmark in
    let encoder = JSONEncoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! encoder.encode(largePayload))
    }
  }

  Benchmark("Encode Large - IkigaJSON") { benchmark in
    let encoder = IkigaJSONEncoder()
    for _ in benchmark.scaledIterations {
      blackHole(try! encoder.encode(largePayload))
    }
  }

  // ============================================
  // ROUND-TRIP BENCHMARKS
  // ============================================

  Benchmark("Round-trip Medium - Foundation") { benchmark in
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for _ in benchmark.scaledIterations {
      let data = try! encoder.encode(mediumUser)
      blackHole(try! decoder.decode(MediumUser.self, from: data))
    }
  }

  Benchmark("Round-trip Medium - IkigaJSON") { benchmark in
    let encoder = IkigaJSONEncoder()
    let decoder = IkigaJSONDecoder()
    for _ in benchmark.scaledIterations {
      let data = try! encoder.encode(mediumUser)
      blackHole(try! decoder.decode(MediumUser.self, from: data))
    }
  }
}
