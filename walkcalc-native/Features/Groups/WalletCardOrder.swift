import Foundation

// Back-to-front positions are independent of each currency's identity/artwork.
struct WalletCardOrder: Codable, Equatable {
    private var ids: [String] = []

    func resolved(in available: [String]) -> [String] {
        guard !ids.isEmpty else {
            // The default currency starts selected, in the front pocket slot.
            guard let first = available.first else { return [] }
            return Array(available.dropFirst()) + [first]
        }
        // Newly encountered currencies enter at the back, keeping the saved
        // front card/selection intact. Hidden currencies remain in stored ids.
        return available.filter { !ids.contains($0) } + ids.filter { available.contains($0) }
    }

    mutating func bringToFront(_ id: String, available: [String]) {
        guard available.contains(id) else { return }
        if ids.isEmpty {
            ids = resolved(in: available)
        } else {
            ids = available.filter { !ids.contains($0) } + ids
        }
        ids = ids.filter { $0 != id } + [id]
    }

    mutating func reconcile(available: [String]) {
        ids = resolved(in: available)
    }
}

// Device-only view preferences. Never included in group or ledger API payloads.
struct WalletCardPosition: Codable, Equatable {
    var order = WalletCardOrder()
    var selectedID: String?

    static func storageKey(groupID: String, participantID: String?) -> String {
        let scope = (try? JSONEncoder().encode([groupID, participantID ?? ""])) ?? Data()
        return "currencyWallet.position.v1." + scope.base64EncodedString()
    }

    static func decode(_ data: Data) -> Self {
        (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    mutating func select(_ id: String, available: [String]) {
        guard available.contains(id) else { return }
        order.bringToFront(id, available: available)
        selectedID = id
    }
}
