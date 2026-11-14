#if DEBUG
import SwiftUI

/// Previews the production storyboard and status view, without starting requests.
struct LaunchScreenPlayground: View {
    var phase: StartupPhase = .loading

    var body: some View {
        StartupScreen(phase: phase)
    }
}

// Select iPhone Duo in the canvas device picker to preview its actual dimensions.
#Preview("Loading · Light", traits: .portrait) {
    LaunchScreenPlayground()
        .preferredColorScheme(.light)
}

#Preview("Loading · Dark", traits: .portrait) {
    LaunchScreenPlayground()
        .preferredColorScheme(.dark)
}

#Preview("Loading · Landscape Light", traits: .landscapeLeft) {
    LaunchScreenPlayground()
        .preferredColorScheme(.light)
}

#Preview("Loading · Landscape Dark", traits: .landscapeLeft) {
    LaunchScreenPlayground()
        .preferredColorScheme(.dark)
}

#Preview("Splash · Light", traits: .portrait) {
    LaunchScreenPlayground(phase: .splash)
        .preferredColorScheme(.light)
}

#Preview("Splash · Dark", traits: .portrait) {
    LaunchScreenPlayground(phase: .splash)
        .preferredColorScheme(.dark)
}

#Preview("Sign in · Light", traits: .portrait) {
    LaunchScreenPlayground(phase: .signIn)
        .preferredColorScheme(.light)
}

#Preview("Sign in · Dark", traits: .portrait) {
    LaunchScreenPlayground(phase: .signIn)
        .preferredColorScheme(.dark)
}
#endif
