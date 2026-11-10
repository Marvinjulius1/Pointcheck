import Foundation
import PadelStats
import SwiftData
import WatchConnectivity

/// Sends finished matches, edits and deletions to the iPhone app.
///
/// Uses `transferUserInfo`, which is queued by the system and delivered even if the
/// iPhone app is not running or the phone is out of range right now.
@MainActor
final class PhoneSync: NSObject {
    static let shared = PhoneSync()

    private var session: WCSession?
    /// Payloads created before the session finished activating.
    private var pending: [[String: Any]] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// Creates or updates these matches on the iPhone.
    func send(_ matches: [MatchSummary]) {
        let finished = matches.filter(\.isCompleted)
        guard !finished.isEmpty, let data = try? MatchSummary.encodeList(finished) else { return }
        enqueue([SyncMessage.typeKey: SyncMessage.upsert, SyncMessage.matchesKey: data])
    }

    func sendDeletion(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        enqueue([SyncMessage.typeKey: SyncMessage.delete, SyncMessage.idsKey: ids.map(\.uuidString)])
    }

    /// Sends the whole finished history (requested by the iPhone, e.g. on first launch).
    func sendAll() {
        let context = AppEnvironment.container.mainContext
        let records = (try? context.fetch(FetchDescriptor<MatchRecord>())) ?? []
        send(records.map(\.summary))
    }

    private func enqueue(_ payload: [String: Any]) {
        guard let session, session.activationState == .activated else {
            pending.append(payload)
            return
        }
        session.transferUserInfo(payload)
    }

    private func flushPending() {
        guard let session, session.activationState == .activated else { return }
        pending.forEach { session.transferUserInfo($0) }
        pending.removeAll()
    }
}

extension PhoneSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error { print("WatchConnectivity activation failed: \(error)") }
        Task { @MainActor in self.flushPending() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[SyncMessage.typeKey] as? String == SyncMessage.requestAll else { return }
        Task { @MainActor in self.sendAll() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo[SyncMessage.typeKey] as? String == SyncMessage.requestAll else { return }
        Task { @MainActor in self.sendAll() }
    }
}
