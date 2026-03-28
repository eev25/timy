//
//  ContentView.swift
//  SampleTimyApp
//
//  Created by Einar Grageda on 3/27/26.
//

import SwiftUI
import Timy

// MARK: - View Model

/// Wraps the Timy client and maintains an in-session event feed for display.
@Observable
final class TimyDemoViewModel {

    // Single shared Timy instance backed by a named SQLite database.
    let timy = Timy(databaseName: "sample-timy-demo.db")

    /// In-memory log shown in the Event Feed section (most recent first).
    private(set) var recentEvents: [LoggedEvent] = []

    /// Non-nil while a timer is actively running.
    private(set) var activeTimer: ActiveTimer?

    // MARK: Nested types

    struct LoggedEvent: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
        let date: Date
        let isTimer: Bool
    }

    struct ActiveTimer {
        let trace: TimyTrace
        let name: String
        let startedAt: Date
    }

    // MARK: Computed

    /// The URL of the SQLite file; forwarded directly from the Timy client.
    var databaseURL: URL? { timy.getDatabaseURL() }

    // MARK: Actions

    /// Calls `timy.log(_:value:)` and prepends a row to the in-session feed.
    func logEvent(name: String, value: Double) {
        timy.log(name, value: value)
        recentEvents.insert(LoggedEvent(name: name, value: value, date: Date(), isTimer: false), at: 0)
    }

    /// Calls `timy.start(_:)` and stores the returned trace handle.
    func startTimer(name: String) {
        activeTimer = ActiveTimer(trace: timy.start(name), name: name, startedAt: Date())
    }

    /// Calls `timy.stop(_:)` with the stored trace and records the elapsed duration.
    func stopTimer() {
        guard let timer = activeTimer else { return }
        timy.stop(timer.trace)
        let duration = Date().timeIntervalSince(timer.startedAt)
        recentEvents.insert(LoggedEvent(name: timer.name, value: duration, date: Date(), isTimer: true), at: 0)
        activeTimer = nil
    }

    func clearFeed() {
        recentEvents.removeAll()
    }
}

// MARK: - Root View

struct ContentView: View {
    @State private var viewModel = TimyDemoViewModel()
    @State private var eventName = "button_tap"
    @State private var eventValue: Double = 1.0
    @State private var timerName = "network_fetch"
    @State private var urlCopied = false

    var body: some View {
        NavigationStack {
            List {
                logEventSection
                timerSection
                eventFeedSection
                databaseSection
            }
            .navigationTitle("Timy Demo")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Database Section

    private var databaseSection: some View {
        Section {
            if let url = viewModel.databaseURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = url.path
                        withAnimation(.spring(duration: 0.3)) { urlCopied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.spring(duration: 0.3)) { urlCopied = false }
                        }
                    } label: {
                        Label(
                            urlCopied ? "Copied!" : "Copy Path",
                            systemImage: urlCopied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(urlCopied ? .green : .accentColor)
                    .animation(.spring(duration: 0.3), value: urlCopied)
                }
                .padding(.vertical, 2)
            } else {
                Label("Database unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Database Location", systemImage: "cylinder")
        } footer: {
            Text("Returned by timy.getDatabaseURL(). Open this .db file in any SQLite browser to inspect raw events.")
        }
    }

    // MARK: - Log Event Section

    private var logEventSection: some View {
        Section {
            TextField("Event name", text: $eventName)
                .autocorrectionDisabled()

            VStack(alignment: .leading, spacing: 4) {
                Text("Value: \(eventValue, specifier: "%.1f")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Slider(value: $eventValue, in: 0...100, step: 0.5)
            }
            .padding(.vertical, 2)

            Button {
                viewModel.logEvent(name: eventName, value: eventValue)
            } label: {
                Label("Log Event", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(eventName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Label("Log Event  ·  timy.log(_:value:)", systemImage: "pencil")
        }
    }

    // MARK: - Timer Section

    private var timerSection: some View {
        Section {
            TextField("Timer name", text: $timerName)
                .autocorrectionDisabled()
                .disabled(viewModel.activeTimer != nil)

            if let active = viewModel.activeTimer {
                // Live elapsed display while the timer is running
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                    Text("Timing \"\(active.name)\"…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TimelineView(.animation(minimumInterval: 0.05)) { _ in
                        Text("\(Date().timeIntervalSince(active.startedAt), specifier: "%.2f")s")
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }

                Button {
                    viewModel.stopTimer()
                } label: {
                    Label("Stop & Record Duration", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                Button {
                    let name = timerName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    viewModel.startTimer(name: name)
                } label: {
                    Label("Start Timer", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(timerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Label("Measure Duration  ·  timy.start / stop", systemImage: "stopwatch")
        }
    }

    // MARK: - Event Feed Section

    private var eventFeedSection: some View {
        Section {
            if viewModel.recentEvents.isEmpty {
                ContentUnavailableView(
                    "No events yet",
                    systemImage: "tray",
                    description: Text("Log an event or measure a duration above.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.recentEvents) { event in
                    EventRow(event: event)
                }

                Button(role: .destructive) {
                    withAnimation { viewModel.clearFeed() }
                } label: {
                    Label("Clear Feed", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.red)
            }
        } header: {
            HStack {
                Label("In-Session Event Feed", systemImage: "list.bullet.rectangle")
                Spacer()
                if !viewModel.recentEvents.isEmpty {
                    Text("\(viewModel.recentEvents.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("All entries here are also persisted to the SQLite database below.")
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: TimyDemoViewModel.LoggedEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.isTimer ? "stopwatch" : "pencil.circle.fill")
                .foregroundStyle(event.isTimer ? .orange : .accentColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.subheadline.weight(.medium))

                if event.isTimer {
                    Text("\(event.value, specifier: "%.4f") s duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("value: \(event.value, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(event.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
