// database:begin
import Fluent
// database:end
import Greetings
import Vapor

/// Registers every route.
func routes(_ app: Application) throws {
    // The health check Fly.io (fly.toml) and Docker poll.
    app.get("health") { _ in
        "ok"
    }

    // A formal greeting of the name in the path: GET /hello/Ada answers "Good day, Ada!".
    app.get("hello", ":name") { request async throws in
        let name = try request.parameters.require("name")
        let greeting = Greeting(name: name).formal().punctuated(with: "!")
        // database:begin
        try await GreetingRecord(name: name).save(on: request.db)
        // database:end
        return greeting.text
    }
    // database:begin

    // How many times the name in the path has been greeted.
    app.get("hello", ":name", "count") { request async throws in
        let name = try request.parameters.require("name")
        return String(try await GreetingRecord.query(on: request.db).filter(\.$name == name).count())
    }
    // database:end
}
