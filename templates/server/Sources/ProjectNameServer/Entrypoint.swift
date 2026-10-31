import App
import Vapor

/// Starts the server. `ProjectNameServer serve --hostname 0.0.0.0 --port 8080` serves; `routes`
/// lists the routes; `--help` lists the rest.
@main
enum Entrypoint {
    static func main() async throws {
        var environment = try Environment.detect()
        try LoggingSystem.bootstrap(from: &environment)
        let app = try await Application.make(environment)
        do {
            try await configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
