import Testing
import Foundation
import SQLite3
@testable import Timy

// SQLITE_TRANSIENT is a C macro not automatically bridged to Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Test helpers

/// Opens the database at `url` read-only and counts rows in `events` with the given `name`.
private func rowCount(at url: URL, name: String) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw TimyTestError.cannotOpenDatabase
    }
    defer { sqlite3_close(db) }

    let sql = "SELECT COUNT(*) FROM events WHERE name = ?;"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw TimyTestError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
    guard sqlite3_step(stmt) == SQLITE_ROW else {
        throw TimyTestError.stepFailed
    }
    return Int(sqlite3_column_int(stmt, 0))
}

/// Opens the database at `url` read-only and returns the `value` of the first row whose `name` matches.
private func firstValue(at url: URL, name: String) throws -> Double {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw TimyTestError.cannotOpenDatabase
    }
    defer { sqlite3_close(db) }

    let sql = "SELECT value FROM events WHERE name = ? LIMIT 1;"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw TimyTestError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
    guard sqlite3_step(stmt) == SQLITE_ROW else {
        throw TimyTestError.stepFailed
    }
    return sqlite3_column_double(stmt, 0)
}

private enum TimyTestError: Error {
    case cannotOpenDatabase
    case prepareFailed
    case stepFailed
}

/// Returns a unique database name for each test to prevent state pollution.
private func uniqueDBName() -> String {
    "timy-test-\(UUID().uuidString).db"
}

// MARK: - Tests

/// Verifies that `log()` persists a row to the database with the expected name.
@Test func logInsertsRow() throws {
    let dbName = uniqueDBName()
    // Explicit type annotation resolves `Timy` to the class, not the module.
    let timy: Timy = .init(databaseName: dbName)

    timy.log("pageview", value: 1.0)
    timy.flush()

    let url = try #require(timy.getDatabaseURL())
    let count = try rowCount(at: url, name: "pageview")
    #expect(count == 1)
}

/// Verifies that `start()` / `stop()` inserts a row with a non-negative duration.
@Test func startStopInsertsDuration() throws {
    let timy: Timy = .init(databaseName: uniqueDBName())

    let trace = timy.start("loadTime")
    timy.stop(trace)
    timy.flush()

    let url = try #require(timy.getDatabaseURL())
    let count = try rowCount(at: url, name: "loadTime")
    #expect(count == 1)

    let value = try firstValue(at: url, name: "loadTime")
    #expect(value >= 0.0)
}

/// Verifies that `getDatabaseURL()` returns a non-nil URL.
@Test func databaseURLIsNonNil() {
    let timy: Timy = .init(databaseName: uniqueDBName())
    #expect(timy.getDatabaseURL() != nil)
}

/// Verifies that 100 concurrent `log()` calls complete without a crash or data race.
@Test func concurrentLogDoesNotCrash() async throws {
    let timy: Timy = .init(databaseName: uniqueDBName())

    await withTaskGroup(of: Void.self) { group in
        for i in 0..<100 {
            group.addTask {
                timy.log("event\(i)")
            }
        }
    }

    timy.flush()

    // All 100 rows must have been written
    let url = try #require(timy.getDatabaseURL())
    var total = 0
    for i in 0..<100 {
        total += try rowCount(at: url, name: "event\(i)")
    }
    #expect(total == 100)
}

/// Verifies that the database filename matches the `databaseName` passed to `init`.
@Test func databaseNameMapsToFilename() {
    let name = uniqueDBName()
    let timy: Timy = .init(databaseName: name)
    #expect(timy.getDatabaseURL()?.lastPathComponent == name)
}
