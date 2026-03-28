import Foundation
import SQLite3

// SQLITE_TRANSIENT is a C macro (-1 cast to a function pointer) that tells SQLite
// to copy string/blob data immediately. It is not automatically bridged to Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A lightweight handle returned by ``Timy/start(_:)`` that carries the event name
/// and the monotonic start time. Pass it to ``Timy/stop(_:)`` to record the elapsed duration.
public struct TimyTrace: Sendable {
    /// The name of the timed event.
    public let name: String
    /// The point in time when the trace was started.
    internal let startTime: Date

    internal init(name: String, startTime: Date) {
        self.name = name
        self.startTime = startTime
    }
}

/// A minimalist, thread-safe telemetry client that persists events to a local SQLite database.
///
/// ## Usage
/// ```swift
/// let timy = Timy(databaseName: "telemetry.db")
///
/// // Log a discrete event
/// timy.log("button_tap")
///
/// // Measure a duration
/// let trace = timy.start("network_request")
/// // … do work …
/// timy.stop(trace)
/// ```
///
/// All database writes are dispatched asynchronously on a private serial queue so callers
/// are never blocked. Use ``getDatabaseURL()`` to locate the `.db` file for offline analysis.
public final class Timy: @unchecked Sendable {

    // MARK: - Private state

    private let queue: DispatchQueue
    private var db: OpaquePointer?
    private let _databaseURL: URL?

    // MARK: - Initialisation

    /// Creates a new ``Timy`` instance backed by a SQLite database stored in the
    /// Application Support directory.
    ///
    /// - Parameter databaseName: The filename for the SQLite database (e.g. `"telemetry.db"`).
    ///   The file is created automatically if it does not already exist.
    public init(databaseName: String) {
        queue = DispatchQueue(label: "dev.timy.dbqueue", qos: .utility)

        // Resolve Application Support directory
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first

        let url = appSupport?.appendingPathComponent(databaseName)
        _databaseURL = url

        // Ensure the directory exists
        if let dir = appSupport {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Open (or create) the database
        if let path = url?.path {
            sqlite3_open(path, &db)
        }

        // Create the events table
        let createSQL = """
            CREATE TABLE IF NOT EXISTS events (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                name      TEXT,
                value     REAL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """
        sqlite3_exec(db, createSQL, nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    /// Records a named telemetry event with an optional numeric value.
    ///
    /// The write is performed asynchronously; this method returns immediately.
    ///
    /// - Parameters:
    ///   - name: A short identifier for the event (e.g. `"app_launch"`, `"purchase"`).
    ///   - value: An arbitrary numeric measurement associated with the event. Defaults to `1.0`.
    public func log(_ name: String, value: Double = 1.0) {
        queue.async {
            self.insertEvent(name: name, value: value)
        }
    }

    /// Starts a named timer and returns a ``TimyTrace`` handle.
    ///
    /// No database write occurs at this point. Call ``stop(_:)`` with the returned handle
    /// to record the elapsed duration.
    ///
    /// - Parameter name: A short identifier for the timed operation (e.g. `"image_decode"`).
    /// - Returns: A ``TimyTrace`` that captures the start time and event name.
    public func start(_ name: String) -> TimyTrace {
        TimyTrace(name: name, startTime: Date())
    }

    /// Stops a timer and records its elapsed duration (in seconds) to the database.
    ///
    /// The write is performed asynchronously; this method returns immediately.
    ///
    /// - Parameter trace: The ``TimyTrace`` returned by a previous call to ``start(_:)``.
    public func stop(_ trace: TimyTrace) {
        let duration = Date().timeIntervalSince(trace.startTime)
        queue.async {
            self.insertEvent(name: trace.name, value: duration)
        }
    }

    /// Returns the URL of the SQLite database file, or `nil` if the Application Support
    /// directory could not be resolved on this device.
    ///
    /// You can open the returned file with any SQLite browser (e.g. DB Browser for SQLite)
    /// to inspect raw event data.
    public func getDatabaseURL() -> URL? {
        _databaseURL
    }

    // MARK: - Internal / Test Helpers

    /// Blocks until all previously enqueued async database writes have completed.
    ///
    /// This is intentionally `internal` — it exists only to make unit tests deterministic.
    func flush() {
        queue.sync {}
    }

    // MARK: - Private helpers

    /// Inserts a single row into the `events` table.
    ///
    /// Must always be called from within the serial `queue`.
    private func insertEvent(name: String, value: Double) {
        let sql = "INSERT INTO events (name, value) VALUES (?, ?);"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return
        }

        // SQLITE_TRANSIENT causes SQLite to copy the string immediately,
        // so it is safe even after the Swift String is deallocated.
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, value)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
}
