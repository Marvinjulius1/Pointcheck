import PadelScoring
import WatchKit

/// Haptic language of the app: light tick per point, stronger for games/sets/match.
enum Haptics {
    private static var device: WKInterfaceDevice { .current() }

    static func play(for outcome: PointOutcome) {
        switch outcome {
        case .point:
            device.play(.click)
        case .game:
            device.play(.directionUp)
        case .set:
            device.play(.success)
        case .match:
            device.play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                device.play(.notification)
            }
        }
    }

    static func undo() {
        device.play(.directionDown)
    }

    static func rejected() {
        device.play(.failure)
    }

    static func newMatch() {
        device.play(.start)
    }
}
