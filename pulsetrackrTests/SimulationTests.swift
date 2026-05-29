//
//  SimulationTests.swift
//  pulsetrackrTests
//
//  Stress-tests IncidentStore at three scales: 100 / 1,000 / 10,000 simultaneous incidents.
//  Each simulation runs five phases and prints a timing report to the console.
//

import Testing
import MapKit
@testable import pulsetrackr

// MARK: - Simulation helpers

private let simCategories  = IncidentCategory.allCases
private let simSeverities  = IncidentSeverity.allCases
private let simSubtypes    = IncidentSubtype.allCases
private let simNeighborhoods = [
    "Lagos Island", "Victoria Island", "Yaba", "Surulere",
    "Lekki", "Ikeja", "Apapa", "Ikorodu", "Mushin", "Agege"
]

/// Builds a store pre-loaded with `count` varied incidents.
@MainActor
private func makeStore(count: Int) -> IncidentStore {
    let store = IncidentStore()
    for i in 0..<count {
        let cat      = simCategories[i % simCategories.count]
        let subtype  = simSubtypes.first { $0.category == cat } ?? .localWarning
        let severity = simSeverities[i % simSeverities.count]
        // Spread coordinates within Lagos metro area
        let lat = 6.4500 + Double(i % 200) * 0.0005
        let lon = 3.2000 + Double(i % 200) * 0.0005
        store.addIncident(
            title: "Incident \(i + 1) — \(cat.label)",
            summary: "Simulation entry for load testing.",
            category: cat,
            subtype: subtype,
            severity: severity,
            neighborhood: simNeighborhoods[i % simNeighborhoods.count],
            reporterCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
    }
    return store
}

private func fmt(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1_000
              + Double(d.components.attoseconds) / 1e15
    return String(format: "%.2f ms", ms)
}

// MARK: - Simulation suite

@Suite("Volume Simulation")
struct SimulationTests {

    /// Core simulation: runs all phases for a given scale and returns a report string.
    @MainActor
    private func simulate(scale: Int) -> String {
        let clock = ContinuousClock()
        var lines: [String] = []
        lines.append("")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("  SIMULATION: \(scale) incidents")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // ── Phase 1: Ingestion ──────────────────────────────────────────────
        var store: IncidentStore!
        let ingestionTime = clock.measure { store = makeStore(count: scale) }
        // Production store starts empty (seed data is DEBUG-only), so the total
        // is exactly the number of incidents we ingested.
        let total = store.incidents.count
        lines.append("  Phase 1 — Ingestion (\(scale) added = \(total) total)")
        lines.append("            \(fmt(ingestionTime))")
        #expect(total == scale)

        // ── Phase 2: Feed render (filter + sort) ───────────────────────────
        var active: [Incident] = []
        let feedTime = clock.measure { active = store.activeIncidents }
        lines.append("  Phase 2 — Feed render (\(active.count) active)")
        lines.append("            \(fmt(feedTime))")
        #expect(!active.isEmpty)

        // ── Phase 3: Signal storm — one .seen per active incident ──────────
        // This exercises firstIndex(of:) which is O(N) per call → O(N²) total.
        let stormTime = clock.measure {
            for incident in active {
                store.record(.seen, for: incident)
            }
        }
        lines.append("  Phase 3 — Signal storm (\(active.count) × .seen)")
        lines.append("            \(fmt(stormTime))")

        // ── Phase 4: Confidence distribution ──────────────────────────────
        let activeAfterStorm = store.activeIncidents
        var dist: [String: Int] = [:]
        for inc in activeAfterStorm {
            let key = "\(inc.confidence.rawValue)"
            dist[key, default: 0] += 1
        }
        lines.append("  Phase 4 — Confidence after storm")
        for (label, count) in dist.sorted(by: { $0.key < $1.key }) {
            let bar = String(repeating: "▪", count: min(count * 20 / (activeAfterStorm.count + 1) + 1, 20))
            lines.append("            \(bar) \(label): \(count)")
        }

        // ── Phase 5: Bulk clear via 3× .cleared signals ────────────────────
        // Each cleared signal requires firstIndex(of:) → same O(N²) pattern.
        var snapshot = store.activeIncidents
        let resolveTime = clock.measure {
            for _ in 0..<3 {
                for incident in snapshot {
                    store.record(.cleared, for: incident)
                }
                snapshot = store.activeIncidents
            }
        }
        let remaining = store.activeIncidents.count
        lines.append("  Phase 5 — Bulk resolve (3× .cleared signal rounds)")
        lines.append("            \(fmt(resolveTime)) → \(remaining) still active")
        #expect(remaining == 0, "All incidents should resolve after 3 cleared rounds")

        // ── Phase 6: Post-resolve feed ─────────────────────────────────────
        var empty: [Incident] = []
        let emptyFeedTime = clock.measure { empty = store.activeIncidents }
        lines.append("  Phase 6 — Post-resolve feed render (\(empty.count) active)")
        lines.append("            \(fmt(emptyFeedTime))")
        #expect(empty.isEmpty)

        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func writeReport(_ text: String, scale: Int) {
        let path = "/tmp/pulsetrackr_sim_\(scale).txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: Scale: 100

    @Test("100 simultaneous incidents")
    @MainActor func simulate100() {
        let report = simulate(scale: 100)
        print(report)
        writeReport(report, scale: 100)
    }

    // MARK: Scale: 1,000

    @Test("1,000 simultaneous incidents")
    @MainActor func simulate1000() {
        let report = simulate(scale: 1_000)
        print(report)
        writeReport(report, scale: 1_000)
    }

    // MARK: Scale: 10,000

    @Test("10,000 simultaneous incidents")
    @MainActor func simulate10000() {
        let report = simulate(scale: 10_000)
        print(report)
        writeReport(report, scale: 10_000)
    }
}
