import FluentSQLiteDriver
import Vapor

/// The error thrown when production starts without `DATABASE_PATH`, rather than keep its data in
/// memory and lose it on the next restart.
public struct MissingDatabasePath: Error, CustomStringConvertible {
    public init() {}

    public var description: String { "DATABASE_PATH must name the SQLite file in production" }
}

extension SQLiteConfiguration {
    /// The database for `environment`: the file at `DATABASE_PATH` when it is set, otherwise a
    /// database in memory, which each application gets a fresh one of.
    ///
    /// - Parameter environment: The environment the application runs in.
    /// - Throws: ``MissingDatabasePath`` when `DATABASE_PATH` is unset in production.
    init(environment: Environment) throws(MissingDatabasePath) {
        if let path = Environment.get("DATABASE_PATH"), !path.isEmpty {
            self.init(storage: .file(path: path))
        } else if environment == .production {
            throw MissingDatabasePath()
        } else {
            self.init(storage: .memory)
        }
    }
}
