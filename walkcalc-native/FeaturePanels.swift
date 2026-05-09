import MapKit
import SwiftUI

struct RecordEditorView: View {
    @EnvironmentObject private var store: WalkcalcStore
    var groupId: String
    var record: WalkRecord?
    var onDone: () -> Void

    @State private var paid: String
    @State private var who: String
    @State private var forWhom: Set<String>
    @State private var type: String
    @State private var text: String
    @State private var message: String?
    @State private var locationService = LocationService()

    init(groupId: String, record: WalkRecord? = nil, onDone: @escaping () -> Void) {
        self.groupId = groupId
        self.record = record
        self.onDone = onDone
        _paid = State(initialValue: record.map { Money.display($0.paidMinor) } ?? "")
        _who = State(initialValue: record?.who ?? "")
        _forWhom = State(initialValue: Set(record?.forWhom ?? []))
        _type = State(initialValue: record?.type ?? "food")
        _text = State(initialValue: record?.text ?? "")
    }

    var members: [Member] {
        store.group(id: groupId)?.allMembers ?? []
    }

    private var canSubmit: Bool {
        !paid.isEmpty && !who.isEmpty && !forWhom.isEmpty
    }

    private var submitTitle: String {
        record == nil ? L("添加", "Add") : L("编辑", "Edit")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("0.00", text: $paid)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 42, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                Picker(L("谁支付的", "Who paid"), selection: $who) {
                    ForEach(members) { member in
                        Text(member.name).tag(member.uuid)
                    }
                }
                .pickerStyle(.menu)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("为谁支付", "For whom")).font(.headline)
                        Spacer()
                        Button(L("选择所有", "Select all")) {
                            if forWhom.count == members.count {
                                forWhom.removeAll()
                            } else {
                                forWhom = Set(members.map(\.uuid))
                            }
                        }
                        .font(.caption)
                    }
                    ForEach(members) { member in
                        Toggle(member.name, isOn: Binding(
                            get: { forWhom.contains(member.uuid) },
                            set: { selected in
                                if selected { forWhom.insert(member.uuid) } else { forWhom.remove(member.uuid) }
                            }
                        ))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("类别", "Category")).font(.headline)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(44), spacing: 10), count: 5),
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(categoryEmoji.keys.sorted(), id: \.self) { key in
                            Button {
                                type = key
                            } label: {
                                Text(categoryEmoji[key] ?? "")
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(type == key ? store.primaryColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                TextField(L("备注", "Remark"), text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button(submitTitle) {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!canSubmit)
            }
        }
        .onAppear {
            if who.isEmpty {
                who = store.user?.uuid ?? members.first?.uuid ?? ""
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(submitTitle) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
            }
        }
    }

    private func submit() async {
        do {
            _ = try Money.parseDisplay(paid)
        } catch {
            message = L("请输入最多 2 位小数的有效金额", "Enter a valid amount with up to 2 decimal places")
            return
        }
        guard !forWhom.isEmpty else {
            message = L("至少选择一个被付款的人", "Select at least one people.")
            return
        }
        let success: Bool
        if let record {
            success = await store.editRecord(groupId: groupId, recordId: record.recordId, who: who, paid: paid, forWhom: Array(forWhom), type: type, text: text)
        } else {
            let location = await locationService.currentLocation()
            success = await store.addRecord(
                groupId: groupId,
                who: who,
                paid: paid,
                forWhom: Array(forWhom),
                type: type,
                text: text,
                long: location.map { "\($0.coordinate.longitude)" } ?? "",
                lat: location.map { "\($0.coordinate.latitude)" } ?? ""
            )
        }
        if success {
            onDone()
        } else {
            message = record == nil ? L("添加失败", "Add fail") : L("编辑失败", "Edit fail")
        }
    }
}

struct RecordDetailView: View {
    var record: WalkRecord
    var group: WalkGroup?
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(categoryEmoji[record.type] ?? "🍎")
                    .font(.title2)
                Divider().frame(height: 34)
                VStack(alignment: .leading) {
                    Text(DateFormatter.walkDate.string(from: record.createdAt.walkDate))
                        .font(.caption)
                    Text(record.createdAt.walkDate, style: .time)
                        .font(.headline)
                }
                Spacer()
                Label("\(record.forWhom.count)", systemImage: "person.fill")
                    .foregroundStyle(.tint)
            }
            Divider()
            DetailUserRow(title: L("谁支付的", "Who paid"), member: member(record.who), amount: record.paidMinor)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(L("为谁支付", "For whom"))(\(record.forWhom.count))")
                    .font(.headline)
                ForEach(record.forWhom, id: \.self) { id in
                    DetailUserRow(member: member(id), amount: Money.splitFirst(record.paidMinor, count: record.forWhom.count))
                    Divider()
                }
            }
            if !record.text.isEmpty {
                Text("\(L("备注", "Remark")): \(record.text)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let coordinate {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 500))) {
                    Marker(member(record.who)?.name ?? L("位置", "Location"), coordinate: coordinate)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !record.isDebtResolve {
                Button(L("编辑记录", "Edit Record"), systemImage: "square.and.pencil", action: onEdit)
                    .font(.caption.weight(.medium))
            }
            Button(L("删除", "Delete"), role: .destructive) { confirmDelete = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .alert(L("确认删除？", "Confirm delete?"), isPresented: $confirmDelete) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("确认", "Confirm"), role: .destructive, action: onDelete)
        }
    }

    private func member(_ id: String) -> Member? {
        group?.allMembers.first(where: { $0.uuid == id })
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(record.lat),
              let longitude = Double(record.long) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct DetailUserRow: View {
    var title: String?
    var member: Member?
    var amount: MoneyMinor

    init(title: String? = nil, member: Member?, amount: MoneyMinor) {
        self.title = title
        self.member = member
        self.amount = amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline)
            }
            HStack {
                AvatarView(member: member, size: 24)
                Text(member?.name ?? "")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Money.display(amount))
                    .font(.headline)
            }
        }
    }
}

struct DebtDetailView: View {
    @EnvironmentObject private var store: WalkcalcStore
    var group: WalkGroup
    @State private var confirmAll = false
    @State private var singleDebt: ResolvedDebt?

    var debts: [ResolvedDebt] {
        store.resolvedDebts(for: group)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle("\(L("债务详情", "Debt detail"))(\(group.allMembers.count))")
                VStack(spacing: 12) {
                    ForEach(group.allMembers) { member in
                        HStack {
                            AvatarView(member: member, size: 24)
                            Text(member.name)
                            Spacer()
                            Text("\(Money.isNegative(member.debtMinor) ? "" : "+")\(Money.display(member.debtMinor))")
                                .foregroundStyle(Money.isNegative(member.debtMinor) ? .red : .green)
                        }
                    }
                }
                SectionTitle("\(L("和解所有债务", "Resolve all debt"))(\(debts.count))")
                VStack(spacing: 14) {
                    ForEach(debts) { debt in
                        VStack(spacing: 6) {
                            HStack {
                                Label(debt.from.name, systemImage: "person.crop.circle")
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Label(debt.to.name, systemImage: "person.crop.circle")
                            }
                            HStack {
                                Text(Money.display(debt.amountMinor))
                                    .font(.headline)
                                Spacer()
                                Button {
                                    singleDebt = debt
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                }
                            }
                        }
                        Divider()
                    }
                }
                Button(L("和解所有债务", "Resolve all debt"), role: .destructive) { confirmAll = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(debts.isEmpty)
            }
        }
        .alert(L("确认和解所有债务吗?", "Confirm resolve all debts?"), isPresented: $confirmAll) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("确认", "Confirm"), role: .destructive) {
                Task { _ = await store.resolveAll(groupId: group.id, debts: debts) }
            }
        }
        .alert(L("确认和解单笔债务吗?", "Confirm resolve single debt?"), isPresented: Binding(get: { singleDebt != nil }, set: { if !$0 { singleDebt = nil } })) {
            Button(L("取消", "Cancel"), role: .cancel) { singleDebt = nil }
            Button(L("确认", "Confirm"), role: .destructive) {
                if let singleDebt {
                    Task { _ = await store.resolveSingle(groupId: group.id, debt: singleDebt) }
                }
                singleDebt = nil
            }
        }
    }
}

struct AddMemberView: View {
    @EnvironmentObject private var store: WalkcalcStore
    var group: WalkGroup
    var onDone: () -> Void
    @State private var search = ""
    @State private var results: [UserProfile] = []
    @State private var users: [UserProfile] = []
    @State private var tempUsers: [String] = []
    @State private var tempName = ""
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(L("通过用户名搜索", "Search by user name"), text: $search)
                .textFieldStyle(.roundedBorder)
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(results) { user in
                Button {
                    guard !group.membersInfo.contains(where: { $0.uuid == user.uuid }),
                          !users.contains(user) else { return }
                    users.append(user)
                } label: {
                    HStack {
                        AvatarView(user: user, size: 24)
                        Text(user.name)
                    }
                }
            }
            if group.isOwner {
                HStack {
                    TextField(L("输入名字", "Enter name"), text: $tempName)
                        .textFieldStyle(.roundedBorder)
                    Button(L("添加临时成员", "Add temporary user")) {
                        guard !tempName.isEmpty, !tempUsers.contains(tempName) else { return }
                        tempUsers.append(tempName)
                        tempName = ""
                    }
                }
            }
            SectionTitle(L("新增成员", "New member"))
            FlowTags(values: users.map(\.name) + tempUsers)
            Spacer()
            Button(L("确认", "Confirm")) {
                Task {
                    if await store.addMembers(groupId: group.id, users: users, tempUsers: tempUsers) {
                        onDone()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .task(id: search) {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                results = []
                isSearching = false
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = await store.searchUsers(name: query)
            isSearching = false
        }
    }
}

struct GroupSettingsPanel: View {
    @EnvironmentObject private var store: WalkcalcStore
    var group: WalkGroup
    var recordCount: Int
    var onDismiss: () -> Void
    @State private var name: String
    @State private var confirmDismiss = false

    init(group: WalkGroup, recordCount: Int, onDismiss: @escaping () -> Void) {
        self.group = group
        self.recordCount = recordCount
        self.onDismiss = onDismiss
        _name = State(initialValue: group.name)
    }

    var body: some View {
        VStack(spacing: 18) {
            TextField(L("群组名称", "Group name"), text: $name)
                .textFieldStyle(.roundedBorder)
            Button(L("修改群组名称", "Modify group name")) {
                Task { _ = await store.changeGroupName(group.id, name: name) }
            }
            .buttonStyle(.bordered)
            LabeledContent(L("群组 ID", "Group ID"), value: group.id)
            LabeledContent(L("记录条数", "Record count"), value: "\(recordCount)")
            LabeledContent(L("人均", "Average cost"), value: averageCost)
            Button(L("解散群组", "Dismiss group"), role: .destructive) { confirmDismiss = true }
                .buttonStyle(.borderedProminent)
        }
        .alert(L("确认解散群组", "Confirm dismiss group?"), isPresented: $confirmDismiss) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("确认", "Confirm"), role: .destructive, action: onDismiss)
        }
    }

    private var averageCost: String {
        let total = group.allMembers.reduce("0") { Money.add($0, $1.costMinor) }
        return Money.display(Money.splitFirst(total, count: max(group.allMembers.count, 1)))
    }
}

struct ShareGroupView: View {
    var groupId: String
    var value: String {
        "walkingcalc://group/\(groupId)"
    }

    var body: some View {
        VStack(spacing: 20) {
            QRCodeImage(value: value)
                .frame(width: 150, height: 150)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
            Text(groupId)
                .font(.title2.monospaced().bold())
            Text(L("邀请朋友加入群组 🥳", "Invite friends to join the group 🥳"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ShareLink(item: value) {
                Label(L("邀请朋友加入群组 🥳", "Invite friends to join the group 🥳"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SSOProfileView: View {
    @Environment(\.dismiss) private var dismiss
    var url: URL
    var token: String?

    var body: some View {
        NavigationStack {
            WebView(url: url, token: token, injectAuthCookie: true, onToken: nil)
                .navigationTitle(L("我的资料", "My Profile"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("取消", "Cancel")) { dismiss() }
                    }
                }
        }
    }
}

struct SectionTitle: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowTags: View {
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5), in: Capsule())
            }
        }
    }
}
