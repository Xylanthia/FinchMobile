import Foundation
import Observation

/// MVVM-C coordinator for the ARIA module, sitting alongside the existing coordinators.
/// Owns the client, connection manager, discovered action registry, and the latest session
/// snapshot. All band ViewModels read from here so every screen shares one source of truth
/// and one last-successful-poll timestamp (spec §2, §1.5, §1.6).
@MainActor
@Observable
final class ARIACoordinator {
    let client: ARIAClient
    let connection: ARIAConnectionManager

    private(set) var modes: [ARIAMode] = []
    private(set) var session: ARIASessionExport = .empty
    private(set) var summary: ARIASessionSummary?
    private(set) var overview = ARIAOverviewCatalog()
    private(set) var overviewError: String?
    private(set) var lastError: String?
    private(set) var isPolling: Bool = false

    /// Current-boot record of everything the handheld reported (backfilled from /api/log, kept
    /// current by /api/stream). Lists, counts and the export read from here, not `session`.
    let history = ARIAHistory()
    /// Decoded per-frame intelligence from the handheld's evidence rings.
    let evidence = ARIAEvidence()
    private var lastEvidenceRefresh = Date.distantPast
    private var lastToolsFetch = Date.distantPast
    /// The handheld's reply to the last control fired from the app.
    private(set) var lastFireOutput: String?
    private(set) var streamConnected = false
    private(set) var historyError: String?

    /// Snapshot cadence. With /api/stream up, deltas arrive as they happen and the snapshot
    /// only refreshes the full live rows; without it, this is the only update path.
    var pollInterval: TimeInterval { streamConnected ? 20 : 7 }

    private var geotagger = ARIAObservationGeotagger()
    private(set) var exportData = Data()

    private var pollTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var backfillAgain = false
    private var lastEventID: String?
    private var streamBoot: Int?
    private(set) var isExporting = false

    init(client: ARIAClient = ARIAClient(),
         connection: ARIAConnectionManager = ARIAConnectionManager()) {
        self.client = client
        self.connection = connection

    }

    func start() {
        connection.start()
        PhoneLocation.startIfNeeded()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in await self?.pollLoop() }
        streamTask = Task { [weak self] in await self?.streamLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        streamTask?.cancel()
        streamTask = nil
        streamConnected = false
        backfillTask?.cancel()
        backfillTask = nil
        connection.stop()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    /// One reconcile cycle: re-check reachability, then (if connected) pull fresh state.
    /// Never shows stale data as live — on a non-connected state we keep the banner honest
    /// and leave the last snapshot tagged with its real timestamp.
    func refresh() async {
        guard !isPolling, !isExporting else { return }
        connection.start()
        isPolling = true
        defer { isPolling = false }

        await connection.evaluate(using: client)
        guard connection.state.isConnected else { return }

        do {
            let stats = try await client.logStats()
            try await acceptBoot(stats)
            let boot = history.bootID
            let snapshot = try await client.fetchSessionExport()
            let after = try await client.logStats()
            guard ARIAHistoryCodec.int(after["boot"]) == boot else {
                try await acceptBoot(after)
                throw ARIAClient.Failure(message: "ARIA rebooted; loading the new boot session.", statusCode: nil)
            }
            history.setHandheldStats(after)
            let fix = ObservationLocation.capture()
            exportData = try ARIAExportJSON.data(geotagger.annotate(snapshot.raw, fix: fix))
            session = snapshot
            if !snapshot.modes.isEmpty { modes = snapshot.modes }
            summary = snapshot.summary
            lastError = snapshot.warnings.isEmpty ? nil : snapshot.warnings.joined(separator: " · ")
            await history.ingestLive(snapshot)
            mergeOverviewHistory()
            overviewError = nil
            if modes.isEmpty || Date().timeIntervalSince(lastToolsFetch) > 300 {
                lastToolsFetch = Date()
                if let tools = try? await client.fetchTools(), !tools.isEmpty { modes = tools }
            }
            if Date().timeIntervalSince(lastEvidenceRefresh) > 30 {
                lastEvidenceRefresh = Date()
                Task { await self.refreshEvidence() }
            }
        } catch {
            lastError = error.localizedDescription
        }
        // First connect (and any time history is not complete): pull the handheld's full log.
        requestBackfill()
    }

    private func acceptBoot(_ stats: [String: Any]) async throws {
        guard let boot = ARIAHistoryCodec.int(stats["boot"]), boot > 0 else {
            throw ARIAClient.Failure(message: "Current ARIA boot identity unavailable; previous captures are excluded.", statusCode: nil)
        }
        if history.bootID != boot {
            backfillTask?.cancel()
            if let task = backfillTask { await task.value }
            backfillTask = nil; backfillAgain = false
            overview = ARIAOverviewCatalog()
            session = .empty; summary = nil; exportData = Data()
            lastEventID = nil; historyError = nil; overviewError = nil
            geotagger = ARIAObservationGeotagger()
            evidence.reset()
            lastEvidenceRefresh = .distantPast
            await history.beginSession(boot: boot)
        }
        history.setHandheldStats(stats)
        let sources = stats["sources"] as? [String: Any] ?? [:]
        for source in ARIALogSource.allCases {
            if let value = sources[source.rawValue] as? [String: Any] { history.seedCursor(source, stats: value) }
        }
    }

    func refreshEvidence() async {
        guard connection.state.isConnected, let boot = history.bootID else { return }
        await evidence.refresh(using: client, boot: boot)
    }

    // MARK: - History backfill (/api/log) and live stream (/api/stream)

    /// Coalesces requests: one backfill at a time, re-run once if asked again meanwhile.
    func requestBackfill() {
        guard !isExporting, history.bootID != nil else { return }
        guard backfillTask == nil else { backfillAgain = true; return }
        backfillTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.backfillAgain = false
                await self.backfill()
            } while self.backfillAgain && !Task.isCancelled
            self.backfillTask = nil
        }
    }

    private func backfill() async {
        guard connection.state.isConnected, let boot = history.bootID, !Task.isCancelled else { return }
        do {
            let stats = try await client.logStats()
            guard !Task.isCancelled, ARIAHistoryCodec.int(stats["boot"]) == boot, history.bootID == boot else { return }
            history.setHandheldStats(stats)
            guard stats["ready"] as? Bool == true else {
                let reason = (stats["mount_error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "starting"
                for source in ARIALogSource.allCases { history.setBackfill(source, .unavailable("handheld log not ready: \(reason)")) }
                return
            }
            let sources = stats["sources"] as? [String: Any] ?? [:]
            for source in ARIALogSource.allCases {
                guard let s = sources[source.rawValue] as? [String: Any] else {
                    history.setBackfill(source, .unavailable("handheld does not log \(source.label)"))
                    continue
                }
                try await page(source, stats: s, boot: boot)
            }
            historyError = nil
            mergeOverviewHistory()
        } catch {
            guard !Task.isCancelled, history.bootID == boot else { return }
            historyError = "Session: \(error.localizedDescription)"
            for source in ARIALogSource.allCases where history.backfill[source] != .complete {
                history.setBackfill(source, .unavailable(error.localizedDescription))
            }
        }
    }

    /// Recover the current boot from its first sequence, including captures before app connection.
    /// Never infer a boot from epoch: firmware intentionally retains epochs across reboots.
    private func page(_ source: ARIALogSource, stats: [String: Any], boot: Int, through target: Int? = nil) async throws {
        let epoch = stats["epoch"] as? String ?? ""
        history.seedCursor(source, stats: stats)
        let floor = ARIAHistory.bootFloor(stats)
        let lastSeq = target ?? ARIAHistoryCodec.int(stats["last_seq"]) ?? 0
        let total = max(0, lastSeq - floor)
        var retries = 0
        while (history.cursors[source]?.lastSeq ?? floor) < lastSeq {
            try Task.checkCancellation()
            guard history.bootID == boot else { throw ARIAClient.Failure(message: "ARIA boot changed during session recovery.", statusCode: nil) }
            let since = history.cursors[source]?.lastSeq ?? floor
            history.setBackfill(source, .loading(loaded: max(0, since - floor), total: total))
            let result = try await client.logPage(source, sinceSeq: since, limit: source.pageLimit)
            try Task.checkCancellation()
            guard history.bootID == boot, result["epoch"] as? String == epoch else {
                throw ARIAClient.Failure(message: "Capture log changed during session recovery.", statusCode: nil)
            }
            guard (ARIAHistoryCodec.int(result["corrupt_lines_skipped"]) ?? 0) == 0 else {
                throw ARIAClient.Failure(message: "Handheld reported corrupt capture records; session recovery is incomplete.", statusCode: nil)
            }
            let records = (result["records"] as? [[String: Any]] ?? []).filter {
                (ARIAHistoryCodec.int($0["seq"]) ?? 0) <= lastSeq
            }
            if records.contains(where: { ARIAHistoryCodec.int($0["boot"]) != boot }) {
                throw ARIAClient.Failure(message: "Handheld rebooted while reading captures; retry the current session.", statusCode: nil)
            }
            await history.ingestLog(source, epoch: epoch, records: records, requireContiguous: true)
            if (history.cursors[source]?.lastSeq ?? floor) <= since {
                retries += 1
                guard retries < 8 else { throw ARIAClient.Failure(message: "Waiting for complete \(source.label) captures from the handheld. Retry export.", statusCode: nil) }
                try await Task.sleep(nanoseconds: 500_000_000)
            } else { retries = 0 }
        }
        history.setBackfill(source, .complete)
    }

    private func streamLoop() async {
        while !Task.isCancelled {
            if connection.state.isConnected {
                do {
                    for try await event in client.events(lastEventID: lastEventID) {
                        streamConnected = true
                        if let id = event.id { lastEventID = id }
                        await handle(event)
                    }
                } catch {
                    // dropped: fall through, reconnect, and let hello trigger a re-page
                }
                streamConnected = false
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func handle(_ event: ARIAClient.StreamEvent) async {
        guard let data = event.data.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        guard !isExporting else { return }
        switch event.event {
        case "hello", "resync":
            let stats = object["stats"] as? [String: Any] ?? object
            streamBoot = ARIAHistoryCodec.int(stats["boot"])
            if streamBoot == history.bootID { requestBackfill() }
            else { Task { await self.refresh() } }
        case "live", "snapshot":
            guard streamBoot == history.bootID else { return }
            history.applyLiveUpdates(object)
        case "record":
            guard ARIAHistoryCodec.int(object["boot"]) == history.bootID, history.bootID != nil else { return }
            guard let name = object["source"] as? String, let source = ARIALogSource(rawValue: name),
                  let captureID = object["capture_id"] as? String else { return }
            // capture_id = "<source>-<epoch>-<seq>"
            let parts = captureID.split(separator: "-")
            guard parts.count >= 3 else { return }
            let epoch = String(parts[parts.count - 2])
            let contiguous = await history.ingestLog(source, epoch: epoch, records: [object], requireContiguous: true)
            if !contiguous { requestBackfill() }
            mergeOverviewHistory()
        default:
            break   // ping
        }
    }

    // MARK: - Overview category projection

    /// One classification projection for every category, from the current-boot capture store.
    private func mergeOverviewHistory() {
        overview = history.overviewCatalog()
    }

    // MARK: - Export the complete current boot through an explicit capture boundary

    func exportSession() async throws -> (URL, [ARIALogSource: Int]) {
        guard connection.state.isConnected, !isExporting else {
            throw ARIAClient.Failure(message: "Connect to ARIA before exporting its current boot session.", statusCode: nil)
        }
        isExporting = true
        defer { isExporting = false }
        while isPolling { try await Task.sleep(nanoseconds: 50_000_000) }
        backfillTask?.cancel()
        if let task = backfillTask { await task.value }
        backfillTask = nil
        let stats = try await client.logStats()
        try await acceptBoot(stats)
        guard stats["ready"] as? Bool == true, let boot = history.bootID else {
            throw ARIAClient.Failure(message: "Handheld capture log is not ready; a boot-to-export session cannot be recovered yet.", statusCode: nil)
        }
        // Include the latest device state, then establish one boundary for each source.
        let current = try await client.fetchSessionExport()
        let cut = try await client.logStats()
        guard ARIAHistoryCodec.int(cut["boot"]) == boot else {
            try await acceptBoot(cut)
            throw ARIAClient.Failure(message: "ARIA rebooted during export. Export the new session again.", statusCode: nil)
        }
        await history.ingestLive(current)
        let sources = cut["sources"] as? [String: Any] ?? [:]
        var boundaries: [String: Int] = [:]
        for source in ARIALogSource.allCases {
            guard let s = sources[source.rawValue] as? [String: Any] else {
                throw ARIAClient.Failure(message: "Missing \(source.label) boot log; cannot produce a complete session.", statusCode: nil)
            }
            let target = (ARIAHistoryCodec.int(s["last_seq"]) ?? 0) + (ARIAHistoryCodec.int(s["pending_unflushed"]) ?? 0)
            boundaries[source.rawValue] = target
            try await page(source, stats: s, boot: boot, through: target)
        }
        let after = try await client.logStats()
        guard ARIAHistoryCodec.int(after["boot"]) == boot else {
            try await acceptBoot(after)
            throw ARIAClient.Failure(message: "ARIA rebooted during export. Export the new session again.", statusCode: nil)
        }
        history.setHandheldStats(cut)
        mergeOverviewHistory()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aria-boot-\(boot)-\(stamp).json")
        let metadata: [String: Any] = [
            "start_uptime_ms": 0,
            "export_uptime_seconds": current.summary?.uptimeSeconds as Any? ?? NSNull(),
            "through_sequence": boundaries,
            "capture_log": cut,
            "capture_scope": "All available current-boot log observations plus current device and capture state. Radio/flash loss counters remain in capture_log.",
        ]
        let counts = try await history.writeExport(to: url, metadata: metadata)
        return (url, counts)
    }

    // MARK: - Control firing (§1.5 / §1.6)

    enum FireOutcome: Equatable {
        case success
        case unknown(String)     // AP dropped mid-flight: outcome genuinely unknown
        case failed(String)
    }

    func fire(_ action: ARIAAction) async -> FireOutcome {
        guard connection.state.isConnected else {
            return .failed("not connected to ARIA-Setup")
        }
        do {
            let reply = try await client.fire(action)
            let object = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
            lastFireOutput = object?["output"] as? String ?? String(decoding: reply.prefix(2000), as: UTF8.self)
            // Reconcile from the device rather than assuming our command is current truth.
            await refresh()
            return .success
        } catch let f as ARIAClient.Failure where f.statusCode == nil {
            return .unknown(f.message)   // transport-level: could have fired, result unknown
        } catch {
            return .failed("\(error)")
        }
    }

    /// Step 1: ask the handheld to pin this capture for replay. Nothing is transmitted.
    func prepareReplay(_ capture: ARIASubGHzCapture) async -> Result<ARIAClient.ReplayPreparation, ReplayError> {
        guard connection.state.isConnected else { return .failure(ReplayError("not connected to ARIA-Setup")) }
        do {
            let prep = try await client.prepareSubGHzReplay(sequence: capture.sequence)
            // Sequence numbers are per boot: make sure the handheld pinned the capture we're showing.
            let freqMismatch = zip2(prep.frequencyMHz, capture.frequencyMHz).map { abs($0.0 - $0.1) > 0.01 } ?? false
            let pulseMismatch = zip2(prep.pulseCount, capture.pulseCount).map { $0.0 != $0.1 } ?? false
            if freqMismatch || pulseMismatch {
                await client.cancelSubGHzReplay()
                return .failure(ReplayError("handheld's sequence \(capture.sequence) is a different capture (it has rebooted since). Nothing transmitted."))
            }
            return .success(prep)
        } catch let f as ARIAClient.Failure {
            return .failure(ReplayError(Self.replayMessage(f.message)))
        } catch {
            return .failure(ReplayError("\(error)"))
        }
    }

    /// Step 2: transmit the prepared sample once (handheld enforces the 60 s token window).
    func confirmReplay(_ prep: ARIAClient.ReplayPreparation) async -> FireOutcome {
        guard connection.state.isConnected else { return .failed("not connected to ARIA-Setup") }
        do {
            lastFireOutput = try await client.confirmSubGHzReplay(token: prep.token)
            return .success
        } catch let f as ARIAClient.Failure where f.statusCode == nil {
            return .unknown(f.message)   // AP dropped mid-flight: it may have transmitted
        } catch let f as ARIAClient.Failure {
            return .failed(Self.replayMessage(f.message))
        } catch {
            return .failed("\(error)")
        }
    }

    func cancelReplay() async { await client.cancelSubGHzReplay() }

    struct ReplayError: Error { let message: String; init(_ m: String) { message = m } }

    private static func replayMessage(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "ERROR: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("Capture unavailable") { return "capture no longer in handheld memory (evicted, cleared, or rebooted)" }
        if text.contains("Replay requires") { return "this capture can't be replayed: it's incomplete or lossy (needs complete OOK/2-FSK timing)" }
        return text
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
