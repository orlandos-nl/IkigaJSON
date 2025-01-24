let json = """
{
    "name": "John",
    "age": 30,
    "city": "New York"
}
""".data(using: .utf8)!

struct Person: Codable {
    let name: String
    let age: Int
    let city: String
}

import IkigaJSON

// Decode JSON to a struct, like JSONDecoder from Foundation
let decoder = IkigaJSONDecoder()
let person = try decoder.decode(Person.self, from: json)

print(person)

// Decode JSON to a JSONObject, like JSONSerialization from Foundation
// This is a more flexible way to work with JSON, as you can access the raw JSON data
// and manipulate it as needed.
// This approach is also much more efficient, as it avoids the overhead of the Codable protocol.
// and it doesn't copy the data out of the buffer until you need it.
// Therefore it's more efficient than JSONSerialization as well.
var personObject = try JSONObject(data: json)
print(personObject)

// You can subscript the JSONObject to get the value of a key
print(personObject["name"])
personObject["name"] = "Jane"
print(personObject["name"])