import UIKit

// Owned by the wallet, not by a preference-generated card or a view task.
@MainActor
final class WalletHaptics {
    private let pickup = UIImpactFeedbackGenerator(style: .light)
    private let landing = UIImpactFeedbackGenerator(style: .heavy)
    private var landingTask: Task<Void, Never>?

    func pickUp(intensity: Double, enabled: Bool) {
        guard enabled, intensity > 0 else { return }
        pickup.impactOccurred(intensity: min(1, intensity))
        // Contact feedback must not cancel a landing already scheduled by the
        // button action in the same SwiftUI update. Selection/drag owns cancellation.
    }

    func scheduleLanding(after delay: Double, intensity: Double, enabled: Bool) {
        cancelLanding()
        guard enabled, intensity > 0 else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(max(0, delay)))
        landingTask = Task { @MainActor [weak self] in
            do {
                // Prepare shortly before impact, even for slow debug animations.
                try await ContinuousClock().sleep(until: deadline.advanced(by: .milliseconds(-50)))
                guard !Task.isCancelled else { return }
                self?.landing.prepare()
                try await ContinuousClock().sleep(until: deadline)
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.landing.impactOccurred(intensity: min(1, intensity))
            self?.landingTask = nil
        }
    }

    func cancelLanding() {
        landingTask?.cancel()
        landingTask = nil
    }

    deinit { landingTask?.cancel() }
}
