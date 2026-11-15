#if DEBUG
import SwiftUI

struct WalletPaletteEntry: Codable, Equatable, Identifiable {
    var id: String
    var color: WalletRGB

    // The renderer still accepts pairs; a palette entry now supplies one solid color.
    var colors: WalletColorPair { WalletColorPair(first: color, second: color) }

    init(id: String, color: WalletRGB) {
        self.id = id
        self.color = color
    }

    private enum CodingKeys: String, CodingKey { case id, color, colors }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        if let primary = try values.decodeIfPresent(WalletRGB.self, forKey: .color) {
            color = primary
        } else {
            // Preserve the primary color, IDs, and ordering of existing on-device palettes.
            color = try values.decode(WalletColorPair.self, forKey: .colors).first
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(color, forKey: .color)
    }
}

struct WalletPalette: Codable, Equatable {
    var entries: [WalletPaletteEntry]

    static let storageKey = "debug.currencyWallet.palette.v1"
    static let defaults = Self(entries: WalletColorPair.defaultPalette.map { entry in
        WalletPaletteEntry(id: entry.id, color: WalletRGB(hex: entry.hex))
    })

    static func decode(_ data: Data) -> Self {
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              !value.entries.isEmpty,
              Set(value.entries.map(\.id)).count == value.entries.count else { return .defaults }
        return value
    }

    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    var parameterSummary: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    // Keep stable row identities when the tuning binding edits colors.
    mutating func replaceColors(_ pairs: [WalletColorPair]) {
        guard !pairs.isEmpty else { return }
        entries = pairs.enumerated().map { index, pair in
            var entry = index < entries.count ? entries[index]
                : WalletPaletteEntry(id: UUID().uuidString, color: pair.first)
            entry.color = pair.first
            return entry
        }
    }
}

@propertyWrapper
struct WalletPaletteSettings: DynamicProperty {
    @AppStorage(WalletPalette.storageKey) private var data = Data()

    var wrappedValue: WalletPalette {
        get { WalletPalette.decode(data) }
        nonmutating set {
            guard !newValue.entries.isEmpty else { return }
            data = newValue.encoded
        }
    }

    var projectedValue: Binding<WalletPalette> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
#endif
