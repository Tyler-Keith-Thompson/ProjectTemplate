import Fluent
import Foundation

/// One greeting served: the name greeted and when. An example model; replace it with the first
/// real one.
///
/// Fluent models are classes, so this is the one place the value-type rule gives way.
final class GreetingRecord: Model, @unchecked Sendable {
    static let schema = "greetings"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(name: String) {
        self.name = name
    }
}

/// Creates the `greetings` table.
struct CreateGreetingRecord: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(GreetingRecord.schema)
            .id()
            .field("name", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(GreetingRecord.schema).delete()
    }
}
