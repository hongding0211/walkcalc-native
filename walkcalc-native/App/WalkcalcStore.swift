import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

@MainActor
final class WalkcalcStore: ObservableObject {
    @Published var token: String?
    @Published var user: UserProfile?
    @Published var groups: [WalkGroup] = []
    @Published var recordsByGroup: [String: [WalkRecord]] = [:]
    @Published var recordTotals: [String: Int] = [:]
    @Published var isBootstrapping = true
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var themeColorId: String = UserDefaults.standard.string(forKey: "themeColor") ?? "blue"

    let api = APIClient()

    var primaryColor: Color {
        themeColorOptions.first(where: { $0.id == themeColorId })?.color ?? themeColorOptions[0].color
    }

    var primaryUIColor: UIColor {
        themeColorOptions.first(where: { $0.id == themeColorId })?.uiColor ?? themeColorOptions[0].uiColor
    }

    var isLoggedIn: Bool {
        token != nil && user != nil
    }

    init() {
        token = UserDefaults.standard.string(forKey: "walkcalc.token")
    }

    func bootstrap() async {
        defer { isBootstrapping = false }
        guard let token else {
            return
        }
        await loadUser(token: token)
        if user != nil {
            await postUserMeta()
            await refreshHome()
        }
    }

    func setThemeColor(_ id: String) {
        themeColorId = id
        UserDefaults.standard.set(id, forKey: "themeColor")
    }

    func signIn(token: String) async {
        self.token = token
        UserDefaults.standard.set(token, forKey: "walkcalc.token")
        await loadUser(token: token)
        await postUserMeta()
        await refreshHome()
    }

    func logout() {
        token = nil
        user = nil
        groups = []
        recordsByGroup = [:]
        UserDefaults.standard.removeObject(forKey: "walkcalc.token")
    }

    func loadUser(token: String) async {
        do {
            let response = try await api.userInfo(token: token)
            applyRefreshedToken(response)
            if response.success, let data = response.data {
                user = data
            } else {
                logout()
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func postUserMeta() async {
        guard let token else { return }
        let metadata: [String: Any] = [
            "language": L10n.serverLanguageCode,
            "deviceInfo": [
                "os": "ios",
                "version": UIDevice.current.systemVersion
            ],
            "lastOpened": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let response = try? await api.postUserMeta(token: token, metadata: metadata) {
            applyRefreshedToken(response)
        }
    }

    func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func refreshHome() async {
        guard let token else { return }
        do {
            let response = try await api.groups(token: token)
            applyRefreshedToken(response)
            if response.success {
                groups = response.data ?? []
            } else {
                errorMessage = response.message ?? L("Network issues")
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func group(id: String) -> WalkGroup? {
        groups.first(where: { $0.id == id })
    }

    func refreshGroup(_ id: String) async {
        guard let token else { return }
        do {
            async let groupResponse = api.group(code: id, token: token)
            async let recordsResponse = api.records(groupCode: id, page: 1, token: token)
            let (groupResult, recordResult) = try await (groupResponse, recordsResponse)
            applyRefreshedToken(groupResult)
            applyRefreshedToken(recordResult)
            if groupResult.success, let group = groupResult.data {
                replaceGroup(group)
            }
            if recordResult.success {
                recordsByGroup[id] = recordResult.data ?? []
                recordTotals[id] = recordResult.pagination?.total ?? recordResult.data?.count ?? 0
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func loadMoreRecords(groupId: String) async {
        guard let token else { return }
        let current = recordsByGroup[groupId] ?? []
        let total = recordTotals[groupId] ?? current.count
        guard current.count < total else { return }
        let page = current.count / 10 + 1
        do {
            let response = try await api.records(groupCode: groupId, page: page, token: token)
            applyRefreshedToken(response)
            if response.success {
                recordsByGroup[groupId] = current + (response.data ?? [])
                recordTotals[groupId] = response.pagination?.total ?? total
            }
        } catch {
            errorMessage = L("Network issues")
        }
    }

    func createGroup(name: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.createGroup(name: name, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func joinGroup(code: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.joinGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func archiveGroup(_ code: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.archiveGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func unarchiveGroup(_ code: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.unarchiveGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func deleteGroup(_ code: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.deleteGroup(code: code, token: token)
            applyRefreshedToken(response)
            await refreshHome()
            return response.success
        }
    }

    func changeGroupName(_ code: String, name: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.changeGroupName(code: code, name: name, token: token)
            applyRefreshedToken(response)
            await refreshGroup(code)
            return response.success
        }
    }

    func addMembers(groupId: String, users: [UserProfile], tempUsers: [String]) async -> Bool {
        await withLoading {
            guard let token else { return false }
            if !users.isEmpty {
                applyRefreshedToken(try await api.invite(code: groupId, userIds: users.map(\.uuid), token: token))
            }
            for tempUser in tempUsers where !tempUser.isEmpty {
                applyRefreshedToken(try await api.addTempUser(code: groupId, name: tempUser, token: token))
            }
            await refreshGroup(groupId)
            return true
        }
    }

    func searchUsers(name: String) async -> [UserProfile] {
        guard let token, !name.isEmpty else { return [] }
        do {
            let response = try await api.searchUsers(name: name, token: token)
            applyRefreshedToken(response)
            return response.data ?? []
        } catch {
            return []
        }
    }

    func addRecord(groupId: String, who: String, paid: String, forWhom: [String], type: String, text: String, long: String = "", lat: String = "") async -> Bool {
        await withLoading {
            guard let token else { return false }
            let paidMinor = try Money.parseDisplay(paid)
            guard !Money.isZero(paidMinor) else { return false }
            let response = try await api.addRecord(groupCode: groupId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, token: token, long: long, lat: lat)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func editRecord(groupId: String, recordId: String, who: String, paid: String, forWhom: [String], type: String, text: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let paidMinor = try Money.parseDisplay(paid)
            guard !Money.isZero(paidMinor) else { return false }
            let response = try await api.updateRecord(groupCode: groupId, recordId: recordId, who: who, paidMinor: paidMinor, forWhom: forWhom, type: type, text: text, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func deleteRecord(groupId: String, recordId: String) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.dropRecord(groupCode: groupId, recordId: recordId, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func resolveSingle(groupId: String, debt: ResolvedDebt) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let response = try await api.addRecord(
                groupCode: groupId,
                who: debt.from.uuid,
                paidMinor: debt.amountMinor,
                forWhom: [debt.to.uuid],
                type: "debtResolve",
                text: L("Debt Resolve"),
                token: token,
                isDebtResolve: true
            )
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func resolveAll(groupId: String, debts: [ResolvedDebt]) async -> Bool {
        await withLoading {
            guard let token else { return false }
            let transfers = debts.map { ["from": $0.from.uuid, "to": $0.to.uuid, "amountMinor": $0.amountMinor] }
            let response = try await api.resolveDebts(groupCode: groupId, transfers: transfers, token: token)
            applyRefreshedToken(response)
            await refreshGroup(groupId)
            return response.success
        }
    }

    func totalDebtMinor() -> MoneyMinor {
        guard let user else { return "0" }
        return groups.reduce("0") { sum, group in
            let mine = group.membersInfo.first(where: { $0.uuid == user.uuid })?.debtMinor ?? "0"
            return Money.add(sum, mine)
        }
    }

    func resolvedDebts(for group: WalkGroup) -> [ResolvedDebt] {
        var receivers = group.allMembers
            .filter { Money.compare($0.debtMinor, "0") != .orderedAscending }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }
        var payers = group.allMembers
            .filter { Money.compare($0.debtMinor, "0") == .orderedAscending }
            .map { member -> Member in
                var next = member
                next.debtMinor = Money.negate(member.debtMinor)
                return next
            }
            .sorted { Money.compare($0.debtMinor, $1.debtMinor) == .orderedDescending }

        let receiverTotal = receivers.reduce("0") { Money.add($0, $1.debtMinor) }
        let payerTotal = payers.reduce("0") { Money.add($0, $1.debtMinor) }
        guard Money.compare(receiverTotal, payerTotal) == .orderedSame else {
            return []
        }

        var result: [ResolvedDebt] = []
        for receiverIndex in receivers.indices {
            while !Money.isZero(receivers[receiverIndex].debtMinor) {
                var advanced = false
                for payerIndex in payers.indices where !Money.isZero(payers[payerIndex].debtMinor) {
                    advanced = true
                    if Money.compare(receivers[receiverIndex].debtMinor, payers[payerIndex].debtMinor) != .orderedAscending {
                        result.append(ResolvedDebt(from: payers[payerIndex], to: receivers[receiverIndex], amountMinor: payers[payerIndex].debtMinor))
                        receivers[receiverIndex].debtMinor = Money.add(receivers[receiverIndex].debtMinor, Money.negate(payers[payerIndex].debtMinor))
                        payers[payerIndex].debtMinor = "0"
                    } else {
                        result.append(ResolvedDebt(from: payers[payerIndex], to: receivers[receiverIndex], amountMinor: receivers[receiverIndex].debtMinor))
                        payers[payerIndex].debtMinor = Money.add(payers[payerIndex].debtMinor, Money.negate(receivers[receiverIndex].debtMinor))
                        receivers[receiverIndex].debtMinor = "0"
                        break
                    }
                }
                if !advanced {
                    break
                }
            }
        }
        return result
    }

    private func replaceGroup(_ group: WalkGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
    }

    private func applyRefreshedToken<T>(_ response: APIEnvelope<T>) {
        guard let refreshedToken = response.refreshedToken else {
            return
        }
        token = refreshedToken
        UserDefaults.standard.set(refreshedToken, forKey: "walkcalc.token")
    }

    private func withLoading(_ action: () async throws -> Bool) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            return try await action()
        } catch {
            errorMessage = L("Network issues")
            return false
        }
    }
}
