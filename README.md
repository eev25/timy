# Timy

A minimalist, thread-safe telemetry client in Swift. Log named events and durations to a local SQLite database and easily export for debugging and analysis.

## Usage

<img align="right" height="600" src="/timy_demo.png">

```swift
import Timy

let timy = Timy(databaseName: "telemetry.db")
```

**Log an event:**

```swift
timy.log("button_tap")
```

**Measure a duration:**

```swift
let trace = timy.start("network_request")
// ... do work ...
timy.stop(trace)  // records elapsed seconds
```

**Inspect the database:**

```swift
if let url = timy.getDatabaseURL() {
    print(url)  // open with DB Browser for SQLite
}
```

## Installation

Add Timy to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/einargrageda/timy", from: "1.0.0")
],
targets: [
    .target(name: "YourTarget", dependencies: ["Timy"])
]
```

## Schema

Events are stored in a single table:

| Column    | Type    | Description                        |
|-----------|---------|------------------------------------|
| id        | INTEGER | Auto-incrementing primary key      |
| name      | TEXT    | Event name                         |
| value     | REAL    | Numeric value (default 1.0)        |
| timestamp | DATETIME| UTC timestamp of the event         |

