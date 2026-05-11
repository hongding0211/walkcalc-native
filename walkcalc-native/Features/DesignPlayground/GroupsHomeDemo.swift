#if DEBUG
import SwiftUI
import UIKit

struct SoftLedgerGroupHomePlayground: View {
    @State private var isShowingCreateGroup = false
    @State private var isShowingJoinGroup = false
    @State private var isShowingHomeSettings = false
    @State private var joinGroupID = ""

    private let groups: [GroupHomeMockGroup]

    private var canJoinGroup: Bool {
        !joinGroupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        self.groups = GroupHomeMockGroup.samples
    }

    fileprivate init(groups: [GroupHomeMockGroup]) {
        self.groups = groups
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GroupHomeTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if groups.isEmpty {
                            GroupHomeEmptyState(
                                onCreateGroup: {
                                    isShowingCreateGroup = true
                                },
                                onJoinGroup: {
                                    isShowingJoinGroup = true
                                }
                            )
                        } else {
                            GroupHomeBalanceCard()
                            GroupHomeSectionHeader()
                            LazyVStack(spacing: 16) {
                                ForEach(groups) { group in
                                    GroupHomeRow(group: group)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingCreateGroup = true
                        } label: {
                            Label("Create group", systemImage: "person.2")
                        }

                        Button {
                            isShowingJoinGroup = true
                        } label: {
                            Label("Join group", systemImage: "person.2.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add group")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingHomeSettings = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingCreateGroup) {
                NavigationStack {
                    GroupHomeCreateGroupSheet()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingHomeSettings) {
                NavigationStack {
                    GroupHomeSettingsSheet()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Join group", isPresented: $isShowingJoinGroup) {
                TextField("Group ID", text: $joinGroupID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("Cancel", role: .cancel) {
                    joinGroupID = ""
                }

                Button("Join") {
                    joinGroupID = ""
                }
                .disabled(!canJoinGroup)
            } message: {
                Text("Enter the Group ID shared by another member.")
            }
        }
    }
}

private struct GroupHomeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingProfileNotice = false

    private let currentUserName = "Hong"
    private let archivedGroups = GroupHomeMockGroup.archivedSamples

    var body: some View {
        Form {
            Section("Account") {
                HStack(spacing: 12) {
                    GroupHomeAvatar(initial: String(currentUserName.prefix(1)), size: 44)

                    Text(currentUserName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GroupHomeTheme.ink)

                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signed in as \(currentUserName)")

                Button {
                    isShowingProfileNotice = true
                } label: {
                    Text("Edit profile")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(GroupHomeTheme.paper)

            Section("Groups") {
                NavigationLink {
                    GroupHomeArchivedGroupsView(groups: archivedGroups)
                } label: {
                    Text("Archived groups")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(GroupHomeTheme.paper)

            Section {
                Button(role: .destructive) {
                    dismiss()
                } label: {
                    Text("Log out")
                }
            }
            .listRowBackground(GroupHomeTheme.paper)
        }
        .scrollContentBackground(.hidden)
        .background(GroupHomeTheme.canvas)
        .tint(GroupHomeTheme.accent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(GroupHomeTheme.accent)
                .accessibilityLabel("Done")
            }
        }
        .alert("Edit profile", isPresented: $isShowingProfileNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This would open the SSO profile page.")
        }
    }
}

private struct GroupHomeArchivedGroupsView: View {
    let groups: [GroupHomeMockGroup]

    var body: some View {
        Form {
            Section {
                if groups.isEmpty {
                    Text("No archived groups")
                        .foregroundStyle(GroupHomeTheme.secondaryInk)
                } else {
                    ForEach(groups) { group in
                        GroupHomeArchivedGroupRow(group: group)
                    }
                }
            }
            .listRowBackground(GroupHomeTheme.paper)
        }
        .scrollContentBackground(.hidden)
        .background(GroupHomeTheme.canvas)
        .navigationTitle("Archived groups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GroupHomeArchivedGroupRow: View {
    let group: GroupHomeMockGroup

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GroupHomeTheme.ink)
                    .lineLimit(1)

                Text(group.updated)
                    .font(.subheadline)
                    .foregroundStyle(GroupHomeTheme.secondaryInk)
            }

            Spacer()

            Text(group.amount)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(GroupHomeTheme.mutedInk)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(group.amount), archived \(group.updatedFull)")
    }
}

private struct GroupHomeEmptyState: View {
    let onCreateGroup: () -> Void
    let onJoinGroup: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(GroupHomeTheme.accent)
                .frame(width: 64, height: 64)
                .background(GroupHomeTheme.paper, in: Circle())
                .overlay {
                    Circle()
                        .stroke(GroupHomeTheme.rule.opacity(0.65), lineWidth: 1)
                }

            VStack(spacing: 6) {
                Text("No groups yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GroupHomeTheme.ink)
                Text("Create a group or join one shared by friends, roommates, or a trip.")
                    .font(.callout)
                    .foregroundStyle(GroupHomeTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    onCreateGroup()
                } label: {
                    Label("Create group", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .accessibilityLabel("Create group")

                Button {
                    onJoinGroup()
                } label: {
                    Label("Join group", systemImage: "person.2.badge.plus")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .accessibilityLabel("Join group")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}

private struct GroupHomeCreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var tempMemberName = ""
    @State private var members = ["Hong"]
    @State private var isShowingAddTemporaryMember = false

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddTempMember: Bool {
        !tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Group") {
                TextField("Name", text: $groupName)
                    .textInputAutocapitalization(.words)
            }
            .listRowBackground(GroupHomeTheme.paper)

            Section("Initial members") {
                GroupHomeInitialMembersRow(members: members)

                NavigationLink {
                    GroupHomeAddMemberSheet(existingMembers: members) { addedMembers in
                        members.append(contentsOf: addedMembers)
                    }
                } label: {
                    Text("Add member")
                        .foregroundStyle(.primary)
                }

                Button {
                    isShowingAddTemporaryMember = true
                } label: {
                    Text("Add temporary member")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(GroupHomeTheme.paper)
        }
        .scrollContentBackground(.hidden)
        .background(GroupHomeTheme.canvas)
        .navigationTitle("Create group")
        .navigationBarTitleDisplayMode(.inline)
        .tint(GroupHomeTheme.accent)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(GroupHomeTheme.accent)
                .disabled(!canCreate)
                .accessibilityLabel("Create")
            }
        }
        .alert("Add temporary member", isPresented: $isShowingAddTemporaryMember) {
            TextField("Name", text: $tempMemberName)

            Button("Cancel", role: .cancel) {
                tempMemberName = ""
            }

            Button("Add") {
                let name = tempMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    members.append(name)
                }
                tempMemberName = ""
            }
            .disabled(!canAddTempMember)
        } message: {
            Text("Temporary members can participate in expenses without an account.")
        }
    }
}

private struct GroupHomeInitialMembersRow: View {
    let members: [String]

    var body: some View {
        HStack {
            Text("Members")
            Spacer()
            GroupHomeSettingsMemberStack(members: members, visibleCount: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(members.count) members")
    }
}

private struct GroupHomeSettingsMemberStack: View {
    let members: [String]
    let visibleCount: Int

    private var visibleMembers: [String] {
        Array(members.prefix(visibleCount))
    }

    private var hiddenCount: Int {
        max(members.count - visibleMembers.count, 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(visibleMembers, id: \.self) { member in
                    GroupHomeAvatar(initial: String(member.prefix(1)), size: 28)
                        .overlay {
                            Circle().stroke(GroupHomeTheme.paper, lineWidth: 2)
                        }
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GroupHomeTheme.secondaryInk)
                        .frame(width: 28, height: 28)
                        .background(GroupHomeTheme.canvas, in: Circle())
                        .overlay {
                            Circle().stroke(GroupHomeTheme.paper, lineWidth: 2)
                        }
                }
            }

            Text("\(members.count) total")
                .font(.subheadline)
                .foregroundStyle(GroupHomeTheme.secondaryInk)
        }
    }
}

private struct GroupHomeBalanceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GroupHomeTheme.secondaryInk)
                Text("+¥128.40")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GroupHomeTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text("Across 4 groups")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GroupHomeTheme.secondaryInk)
                .lineLimit(1)
        }
        .padding(20)
        .groupHomeLiquidGlass(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(GroupHomeTheme.rule.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: GroupHomeTheme.ink.opacity(0.035), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total balance, plus 128 yuan 40. Across 4 groups.")
    }
}

private struct GroupHomeInlineStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GroupHomeTheme.mutedInk)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GroupHomeSectionHeader: View {
    var body: some View {
        Text("All groups")
            .font(.callout.weight(.semibold))
            .foregroundStyle(GroupHomeTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

private struct GroupHomeRow: View {
    let group: GroupHomeMockGroup

    private var amountColor: Color {
        group.amount == "¥0.00" ? GroupHomeTheme.mutedInk : (group.isPositive ? GroupHomeTheme.positive : GroupHomeTheme.negative)
    }

    var body: some View {
        Button {
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GroupHomeTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        GroupHomeMemberAvatarStack(members: group.members)
                        Text("\(group.members.count) members")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(GroupHomeTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(group.amount)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                    Text(group.updated)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GroupHomeTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GroupHomeTheme.mutedInk.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GroupHomeTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(amountColor.opacity(group.amount == "¥0.00" ? 0.32 : 0.58))
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GroupHomeTheme.rule.opacity(0.62), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.name), \(group.amount), \(group.status), updated \(group.updatedFull)")
        .accessibilityHint("Opens group details")
        .contextMenu {
            Button {
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Button(role: .destructive) {
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct GroupHomeAddMemberSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingMembers: [String]
    let onAdd: ([String]) -> Void

    @State private var searchText = ""
    @State private var selectedMembers: Set<String> = []

    private let candidates = ["Alexandra", "Christopher", "Noah", "Ivy", "Owen", "Tara", "June", "Keith"]

    private var availableCandidates: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { candidate in
            !existingMembers.contains(candidate)
                && (query.isEmpty || candidate.localizedCaseInsensitiveContains(query))
        }
    }

    private var canAdd: Bool {
        !selectedMembers.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Search by name", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .listRowBackground(GroupHomeTheme.paper)

            Section("Results") {
                ForEach(availableCandidates, id: \.self) { member in
                    Button {
                        toggle(member)
                    } label: {
                        HStack(spacing: 12) {
                            GroupHomeAvatar(initial: String(member.prefix(1)), size: 30)

                            Text(member)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedMembers.contains(member) {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(GroupHomeTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(GroupHomeTheme.paper)

            if !selectedMembers.isEmpty {
                Section("Selected") {
                    Text(selectedMembers.sorted().joined(separator: ", "))
                        .foregroundStyle(GroupHomeTheme.secondaryInk)
                }
                .listRowBackground(GroupHomeTheme.paper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GroupHomeTheme.canvas)
        .tint(GroupHomeTheme.accent)
        .navigationTitle("Add member")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onAdd(selectedMembers.sorted())
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(GroupHomeTheme.accent)
                .disabled(!canAdd)
                .accessibilityLabel("Add")
            }
        }
    }

    private func toggle(_ member: String) {
        if selectedMembers.contains(member) {
            selectedMembers.remove(member)
        } else {
            selectedMembers.insert(member)
        }
    }
}

private struct GroupHomeMemberAvatarStack: View {
    let members: [String]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(members.prefix(3).enumerated()), id: \.offset) { _, member in
                GroupHomeAvatar(initial: member, size: 24)
                    .overlay {
                        Circle().stroke(GroupHomeTheme.paper, lineWidth: 2)
                    }
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

private struct GroupHomeAvatar: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(GroupHomeTheme.canvas)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(GroupHomeTheme.secondaryInk)
            }
    }
}

private struct GroupHomeMockGroup: Identifiable {
    let id = UUID()
    let name: String
    let amount: String
    let status: String
    let updatedAt: Date
    let members: [String]
    let isPositive: Bool

    var updated: String {
        TemporalDisplay.string(from: updatedAt, context: .compact, now: Self.sampleNow, calendar: Self.sampleCalendar)
    }

    var updatedFull: String {
        TemporalDisplay.string(from: updatedAt, context: .full, now: Self.sampleNow, calendar: Self.sampleCalendar)
    }

    static let samples: [GroupHomeMockGroup] = [
        .init(
            name: "May Trip",
            amount: "+¥86.20",
            status: "owed to me",
            updatedAt: sampleDate(year: 2026, month: 5, day: 15, hour: 14, minute: 5),
            members: ["H", "L", "M", "Y"],
            isPositive: true
        ),
        .init(
            name: "Studio Lunch",
            amount: "-¥42.00",
            status: "I owe",
            updatedAt: sampleDate(year: 2026, month: 5, day: 14, hour: 14, minute: 5),
            members: ["H", "A", "J"],
            isPositive: false
        ),
        .init(
            name: "Apartment",
            amount: "¥0.00",
            status: "settled",
            updatedAt: sampleDate(year: 2026, month: 5, day: 11, hour: 14, minute: 5),
            members: ["H", "K"],
            isPositive: true
        )
    ]

    static let archivedSamples: [GroupHomeMockGroup] = [
        .init(
            name: "Winter House",
            amount: "¥0.00",
            status: "archived",
            updatedAt: sampleDate(year: 2026, month: 3, day: 2, hour: 14, minute: 5),
            members: ["H", "L", "A"],
            isPositive: true
        ),
        .init(
            name: "Tokyo Weekend",
            amount: "¥0.00",
            status: "archived",
            updatedAt: sampleDate(year: 2025, month: 1, day: 18, hour: 14, minute: 5),
            members: ["H", "M"],
            isPositive: true
        )
    ]

    private static var sampleNow: Date {
        sampleDate(year: 2026, month: 5, day: 15, hour: 16, minute: 30)
    }

    private static var sampleCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    private static func sampleDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        DateComponents(
            calendar: sampleCalendar,
            timeZone: sampleCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date ?? Date(timeIntervalSince1970: 0)
    }
}

private enum GroupHomeTheme {
    static let canvas = groupHomeAdaptive(light: 0xF6F2EA, dark: 0x131416)
    static let paper = groupHomeAdaptive(light: 0xFEFCF6, dark: 0x1D1E20)
    static let ink = groupHomeAdaptive(light: 0x25221D, dark: 0xF1F0EC)
    static let secondaryInk = groupHomeAdaptive(light: 0x746C5D, dark: 0xC7C4BE)
    static let mutedInk = groupHomeAdaptive(light: 0x9D917E, dark: 0x92918C)
    static let rule = groupHomeAdaptive(light: 0xDAD2C0, dark: 0x34363A)
    static let positive = groupHomeAdaptive(light: 0x167454, dark: 0x77C99E)
    static let negative = groupHomeAdaptive(light: 0xAC2F24, dark: 0xF07C6C)
    static let accent = groupHomeAdaptive(light: 0xB15525, dark: 0xE49B63)
}

private func groupHomeAdaptive(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { traitCollection in
        UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
    })
}

private struct GroupHomeLiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(.regular.tint(GroupHomeTheme.paper.opacity(0.32)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular.tint(GroupHomeTheme.paper.opacity(0.26)), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private extension View {
    func groupHomeLiquidGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(GroupHomeLiquidGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

#Preview("Group Home UX") {
    SoftLedgerGroupHomePlayground()
}

#Preview("Group Home Empty") {
    SoftLedgerGroupHomePlayground(groups: [])
}
#endif
