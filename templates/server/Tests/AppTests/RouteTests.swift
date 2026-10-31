import App
import Testing
import VaporTesting

@Suite("Routes")
struct RouteTests {
    @Test("GET /health answers ok")
    func health() async throws {
        let expected: String = "ok"
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "health") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == expected)
            }
        }
    }

    @Test("GET /hello/:name answers a formal, punctuated greeting of the name")
    func hello() async throws {
        let expected: String = "Good day, Ada!"
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello/Ada") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == expected)
            }
        }
    }

    @Test("GET /hello without a name is not found")
    func helloWithoutName() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello") { response async in
                #expect(response.status == .notFound)
            }
        }
    }
    // database:begin

    @Test("GET /hello/:name/count counts the greetings of that name only")
    func count() async throws {
        let expected: String = "2"
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello/Ada")
            try await app.testing().test(.GET, "hello/Grace")
            try await app.testing().test(.GET, "hello/Ada")
            try await app.testing().test(.GET, "hello/Ada/count") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == expected)
            }
        }
    }

    @Test("A name never greeted has a count of zero")
    func countNeverGreeted() async throws {
        let expected: String = "0"
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello/Ada/count") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == expected)
            }
        }
    }

    @Test("Each application gets a database of its own")
    func isolatedDatabases() async throws {
        let expected: String = "0"
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello/Ada")
        }
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello/Ada/count") { response async in
                #expect(response.body.string == expected)
            }
        }
    }
    // database:end
}
