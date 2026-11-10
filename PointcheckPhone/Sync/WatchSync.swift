import Foundation
import Observation
import PadelStats
import WatchConnectivity

/// Receives matches from the Apple Watch app.
@Observable
@MainActor
final class WatchSync: NSObject {
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var lastReceived: Date?

    @ObservationIgnored private let store: MatchStore
    @ObservationIgnored private var session: WCSession?
    private static let initialSyncKey = "sync.didRequestInitialHistory"

    init(store: MatchStore) {
        self.store = store
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// Asks the watch to send its whole history (first launch or pull-to-refresh).
    func requestAll() {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        let message = [SyncMessage.typeKey: SyncMessage.requestAll]
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                // Not reachable after all – fall back to the queued channel.
                session.transferUserInfo(message)
            }
        } else {
            session.transferUserInfo(message)
        }
    }

    fileprivate func handle(_ payload: [String: Any]) {
        switch payload[SyncMessage.typeKey] as? String {
        case SyncMessage.upsert:
            guard let data = payload[SyncMessage.matchesKey] as? Data,
                  let matches = try? MatchSummary.decodeList(data) else { return }
            store.upsert(matches)
            lastReceived = .now
        case SyncMessage.delete:
            let ids = (payload[SyncMessage.idsKey] as? [String] ?? []).compactMap(UUID.init(uuidString:))
            store.delete(ids: ids)
            lastReceived = .now
        default:
            break
        }
    }

    fileprivate func updateState(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        if isWatchAppInstalled, !UserDefaults.standard.bool(forKey: Self.initialSyncKey) {
            UserDefaults.standard.set(true, forKey: Self.initialSyncKey)
            requestAll()
        }
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error { print("WatchConnectivity activation failed: \(error)") }
        Task { @MainActor in self.updateState(session) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateState(session) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = SendablePayload(userInfo)
        Task { @MainActor in self.handle(payload.value) }
    }
}

/// WatchConnectivity dictionaries only contain property-list values (Data, String, arrays).
private struct SendablePayload: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
