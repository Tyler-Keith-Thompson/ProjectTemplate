import Foundation
import IssueReporting
import SnapshotTesting

// Adapted from https://gist.github.com/daltonclaybrook/38bce5fd9b8a150952c924fc1045b12c
//
// SnapshotTesting finds reference images using #filePath. rules_swift compiles sources with paths relative to the
// execroot, and iOS tests run inside the simulator with its data directory as the working directory, so the default
// location ends up somewhere in the simulator rather than in the repo. Disabling the sandbox doesn't change either of
// those things. Instead, references are read from a Snapshots.bundle packaged into the test bundle, recorded into the
// workspace when SNAPSHOT_REFERENCE_ROOT is set (see `just record-snapshots`), and failures are written to the test
// outputs.
public func assertBazelSnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let environment = ProcessInfo.processInfo.environment
    if let outputs = environment["TEST_UNDECLARED_OUTPUTS_DIR"] {
        setenv("SNAPSHOT_ARTIFACTS", outputs, 1)
    }
    let failure = verifySnapshot(
        of: try value(),
        as: snapshotting,
        named: name,
        record: record,
        snapshotDirectory: snapshotDirectory(for: URL(filePath: "\(filePath)"), in: environment),
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
    if let failure {
        reportIssue(failure, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

private func snapshotDirectory(for file: URL, in environment: [String: String]) -> String? {
    let fileName = file.deletingPathExtension().lastPathComponent
    if let root = environment["SNAPSHOT_REFERENCE_ROOT"] {
        return URL(filePath: file.relativePath, relativeTo: URL(filePath: root, directoryHint: .isDirectory))
            .deletingLastPathComponent()
            .appending(path: "__Snapshots__")
            .appending(path: fileName)
            .path()
    }
    guard let snapshots = Bundle(for: CurrentBundleFinder.self).url(forResource: "Snapshots", withExtension: "bundle") else {
        return nil
    }
    let directory = snapshots.appending(path: "__Snapshots__").appending(path: fileName)
    return FileManager.default.fileExists(atPath: directory.path()) ? directory.path() : nil
}

private final class CurrentBundleFinder { }
