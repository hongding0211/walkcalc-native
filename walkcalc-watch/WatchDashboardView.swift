import SwiftUI

struct WatchDashboardView: View {
    @State private var draftAmount = ""
    @State private var selectedGroup = WatchGroup.sampleGroups[0]
    @State private var records = WatchRecord.sampleRecords

    private var monthTotal: Decimal {
        records.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本月支出")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(monthTotal, format: .currency(code: "CNY"))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .contentTransition(.numericText())

                        HStack(spacing: 8) {
                            Label("3 人待结算", systemImage: "person.2.fill")
                            Spacer(minLength: 4)
                            Label("2 组", systemImage: "square.stack.3d.up.fill")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("快速记一笔") {
                    Picker("分组", selection: $selectedGroup) {
                        ForEach(WatchGroup.sampleGroups) { group in
                            Text(group.name).tag(group)
                        }
                    }

                    TextField("金额", text: $draftAmount)

                    Button {
                        addRecord()
                    } label: {
                        Label("保存", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(parsedAmount == nil)
                }

                Section("最近") {
                    ForEach(records.prefix(4)) { record in
                        HStack(spacing: 8) {
                            Image(systemName: record.symbol)
                                .foregroundStyle(record.tint)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(record.groupName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            Text(record.amount, format: .currency(code: "CNY"))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("WalkCalc")
        }
    }

    private var parsedAmount: Decimal? {
        let normalized = draftAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func addRecord() {
        guard let amount = parsedAmount else { return }

        records.insert(
            WatchRecord(
                title: "手表记录",
                groupName: selectedGroup.name,
                amount: amount,
                symbol: "applewatch",
                tint: .green
            ),
            at: 0
        )
        draftAmount = ""
    }
}

private struct WatchGroup: Identifiable, Hashable {
    let id: String
    let name: String

    static let sampleGroups = [
        WatchGroup(id: "trip", name: "杭州周末"),
        WatchGroup(id: "home", name: "家用"),
    ]
}

private struct WatchRecord: Identifiable {
    let id = UUID()
    let title: String
    let groupName: String
    let amount: Decimal
    let symbol: String
    let tint: Color

    static let sampleRecords = [
        WatchRecord(title: "咖啡", groupName: "杭州周末", amount: 42, symbol: "cup.and.saucer.fill", tint: .brown),
        WatchRecord(title: "地铁", groupName: "杭州周末", amount: 16, symbol: "tram.fill", tint: .blue),
        WatchRecord(title: "晚餐", groupName: "家用", amount: 138, symbol: "fork.knife", tint: .orange),
        WatchRecord(title: "超市", groupName: "家用", amount: 86, symbol: "cart.fill", tint: .purple),
    ]
}

#Preview {
    WatchDashboardView()
}
