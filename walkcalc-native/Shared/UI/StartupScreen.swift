import SwiftUI
import UIKit

enum StartupPhase {
    case splash
    case loading
    case signIn
}

/// The system launch snapshot and the app use the same storyboard and assets.
/// Only the reserved status slot changes after the app has started.
struct StartupScreen: View {
    var phase: StartupPhase = .loading

    var body: some View {
        StartupStoryboard(phase: phase)
            .ignoresSafeArea()
    }
}

private struct StartupStoryboard: UIViewControllerRepresentable {
    let phase: StartupPhase

    func makeUIViewController(context: Context) -> StartupViewController {
        StartupViewController(phase: phase)
    }

    func updateUIViewController(_ controller: StartupViewController, context: Context) {
        controller.phase = phase
    }
}

final class StartupViewController: UIViewController {
    var phase: StartupPhase {
        didSet { updateStatus() }
    }

    private var scaleReference: UIView?
    private var statusHost: UIHostingController<StartupStatus>?
    private var statusScale: CGFloat = 1

    init(phase: StartupPhase) {
        self.phase = phase
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(phase:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let scene = UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController() else {
            preconditionFailure("LaunchScreen must have an initial view controller")
        }
        addChild(scene)
        view.addSubview(scene.view)
        pin(scene.view, to: view)
        scene.didMove(toParent: self)

        // These are plain UIKit tags, not custom classes, outlets or runtime attributes.
        guard let slot = scene.view.viewWithTag(701),
              let scaleReference = scene.view.viewWithTag(702) else {
            preconditionFailure("LaunchScreen is missing its status slot or scale reference")
        }
        self.scaleReference = scaleReference
        scene.view.viewWithTag(703)?.accessibilityLabel = "Walking Calculator"
        scene.view.viewWithTag(703)?.isAccessibilityElement = true

        let host = UIHostingController(rootView: StartupStatus(phase: phase, scale: statusScale))
        host.view.backgroundColor = .clear
        addChild(host)
        slot.addSubview(host.view)
        pin(host.view, to: slot)
        host.didMove(toParent: self)
        statusHost = host
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let scaleReference else { return }
        // Contained controllers may lay out after the parent's callback. Resolve
        // the storyboard first so status text uses the current orientation's scale.
        scaleReference.superview?.layoutIfNeeded()
        let scale = scaleReference.bounds.width / 390
        guard scale > 0, abs(scale - statusScale) > 0.0001 else { return }
        statusScale = scale
        updateStatus()
    }

    private func updateStatus() {
        statusHost?.rootView = StartupStatus(phase: phase, scale: statusScale)
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

private struct StartupStatus: View {
    let phase: StartupPhase
    let scale: CGFloat

    var body: some View {
        Group {
            switch phase {
            case .splash:
                Color.clear.accessibilityHidden(true)
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(Color("StartupSecondaryText"))
                    .accessibilityLabel(Text(L("Loading")))
            case .signIn:
                Text(L("Sign in to continue"))
                    .font(.custom("PingFangSC-Medium", size: 15 * scale))
                    .foregroundStyle(Color("StartupSecondaryText"))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
