import Foundation
import UIKit

extension Notification.Name {
    static let walkcalcAPNsTokenDidChange = Notification.Name("walkcalcAPNsTokenDidChange")
}

final class WalkcalcAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .walkcalcAPNsTokenDidChange, object: token)
    }
}
