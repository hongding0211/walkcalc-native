import SwiftUI
import UIKit

// NavigationSplitView can leave its detail navigation controller's toolbar
// hidden after moving between a collapsed stack and side-by-side columns.
// Restore the existing system toolbar, without rebuilding the detail view or
// losing its search, scroll position, filters, or presented sheet.
struct RecordToolbarVisibility: UIViewControllerRepresentable {
    var isSearching: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isSearching = isSearching
        controller.restoreToolbar()
    }

    final class Controller: UIViewController {
        var isSearching = false

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreToolbar()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            restoreToolbar()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.restoreToolbar()
            }
        }

        func restoreToolbar() {
            guard !isSearching, isViewLoaded, view.window != nil,
                  let navigationController, navigationController.isToolbarHidden,
                  // UIKit may activate search before SwiftUI updates its binding.
                  navigationController.topViewController?.navigationItem.searchController?.isActive != true else { return }
            navigationController.setToolbarHidden(false, animated: false)
        }
    }
}
