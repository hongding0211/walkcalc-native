import Combine
import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let walkcalcAPNsTokenDidChange = Notification.Name("walkcalcAPNsTokenDidChange")
}

struct PushNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let groupId: String
}

@MainActor
final class PushNavigationCoordinator: ObservableObject {
    static let shared = PushNavigationCoordinator()

    @Published private(set) var pendingRequest: PushNavigationRequest?

    private init() {}

    func receive(userInfo: [AnyHashable: Any]) {
        guard let groupId = Self.groupId(from: userInfo) else { return }
        pendingRequest = PushNavigationRequest(groupId: groupId)
    }

    func consume(_ request: PushNavigationRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }

    private static func groupId(from userInfo: [AnyHashable: Any]) -> String? {
        let action = userInfo["action"] as? String
        let notificationType = userInfo["notificationType"] as? String
        let schemaVersion = (userInfo["schemaVersion"] as? NSNumber)?.intValue
            ?? Int(userInfo["schemaVersion"] as? String ?? "")

        let isSupportedSchema = schemaVersion == 1
            && action == "open_group"
            && notificationType?.hasPrefix("walkcalc.") == true
        let isLegacyGroupPayload = schemaVersion == nil && action == nil
        guard isSupportedSchema || isLegacyGroupPayload,
              let groupId = userInfo["groupCode"] as? String else {
            return nil
        }

        let normalizedGroupId = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedGroupId.isEmpty ? nil : normalizedGroupId
    }
}

final class WalkcalcAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .walkcalcAPNsTokenDidChange, object: token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            PushNavigationCoordinator.shared.receive(userInfo: userInfo)
        }
    }
}
