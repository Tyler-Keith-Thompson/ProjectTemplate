// database:begin
import FluentSQLiteDriver
// database:end
import Vapor

/// Configures `app` to serve ProjectName: its database and its routes.
///
/// The executable calls this before it starts serving, and every test calls it on an application
/// of its own, so a test exercises the same configuration production runs.
///
/// - Parameter app: The application to configure.
// database:begin
/// - Throws: ``MissingDatabasePath`` in production when `DATABASE_PATH` is unset, or the error of a
///   migration that failed.
// database:end
public func configure(_ app: Application) async throws {
    // database:begin
    app.databases.use(.sqlite(try SQLiteConfiguration(environment: app.environment)), as: .sqlite)
    // Write-ahead logging: readers don't wait for the writer, and Litestream replicates from the
    // log. The mode is stored in the database file, so setting it once at startup holds for every
    // connection. Every Fluent SQLite database is an SQLDatabase.
    try await (app.db as! any SQLDatabase).raw("PRAGMA journal_mode=WAL").run()
    app.migrations.add(CreateGreetingRecord())
    try await app.autoMigrate()
    // database:end
    try routes(app)
}
