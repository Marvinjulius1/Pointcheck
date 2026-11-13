import CoreLocation
import Observation

/// Rough position of the phone (about 1–10 km, "Ungefährer Standort") for "Hallen in der Nähe"
/// and for showing ads of nearby halls. The position is never stored on the server – it is
/// only sent with those requests, and the server rounds it to ~1 km.
@Observable
@MainActor
final class CoarseLocation: NSObject {
    static let shared = CoarseLocation()

    private(set) var authorization: CLAuthorizationStatus
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiting: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    @ObservationIgnored private var lastFix: (coordinate: CLLocationCoordinate2D, date: Date)?

    override private init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// The current rough position. Asks for permission only when `ask` is true
    /// (after the player tapped "In meiner Nähe"); otherwise returns `nil` without permission.
    func coordinate(ask: Bool = false) async -> CLLocationCoordinate2D? {
        if let lastFix, Date.now.timeIntervalSince(lastFix.date) < 15 * 60 {
            return lastFix.coordinate
        }
        if authorization == .notDetermined {
            guard ask else { return nil }
            manager.requestWhenInUseAuthorization()
        } else if !isAuthorized {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if isAuthorized { manager.requestLocation() }
            // Never hang: give up after 10 seconds (only if nobody answered meanwhile).
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, !self.waiting.isEmpty else { return }
                self.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        if let coordinate { lastFix = (coordinate, .now) }
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume(returning: coordinate) }
    }
}

extension CoarseLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized, !self.waiting.isEmpty {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
