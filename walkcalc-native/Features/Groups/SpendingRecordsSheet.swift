import SwiftUI

struct SpendingRecordsSheet: View {
    @EnvironmentObject private var store: WalkcalcStore
    @Environment(\.groupSheetContentMaxWidth) private var contentMaxWidth

    let group: WalkGroup
    let title: String
    let filter: SpendingRecordsFilter
    let currencyCode: String
    let onRecordsChanged: () -> Void

    @State private var records: [WalkRecord] = []
    @State private var pendingPage: PageRequest? = PageRequest(number: 1)
    @State private var nextPage: Int?
    @State private var failedPage: Int?
    @State private var selectedRecord: WalkRecord?
    @State private var deleteCandidate: WalkRecord?

    private var currentGroup: WalkGroup { store.group(id: group.id) ?? group }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !records.isEmpty {
                        GroupExpensesSection(
                            group: currentGroup, records: records, sort: GroupRecordSort(),
                            isLoadingMore: pendingPage != nil,
                            onDelete: { deleteCandidate = $0 },
                            onEdit: { selectedRecord = $0 }
                        )
                    } else if pendingPage != nil {
                        ProgressView()
                            .softLedgerProgressTint()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if failedPage == nil {
                        ContentUnavailableView(L("No records yet"), systemImage: "tray")
                    }

                    if let failedPage {
                        ContentUnavailableView {
                            Label(L("Could not load records"), systemImage: "exclamationmark.circle")
                        } actions: {
                            Button(L("Retry")) {
                                self.failedPage = nil
                                pendingPage = PageRequest(number: failedPage)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY
            } action: { _, remaining in
                guard remaining < 160, let nextPage, pendingPage == nil else { return }
                self.nextPage = nil
                pendingPage = PageRequest(number: nextPage)
            }
            .background { SoftLedgerBackground() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: pendingPage) { [pendingPage] in
                if let pendingPage { await load(pendingPage) }
            }
            .navigationDestination(item: $selectedRecord) { record in
                RecordEditorView(groupId: group.id, record: record, onDone: refreshAfterChange)
            }
            .recordDeleteConfirmation(groupId: group.id, record: $deleteCandidate) { _ in
                refreshAfterChange()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func load(_ request: PageRequest) async {
        let result = await store.spendingRecords(
            for: currentGroup, filter: filter,
            currencyCode: currencyCode, page: request.number
        )
        guard !Task.isCancelled, pendingPage == request else { return }
        pendingPage = nil
        switch result {
        case .success(let page):
            var seen = Set(records.map(\.id))
            records += page.items.filter { seen.insert($0.id).inserted }
            if let pagination = page.pagination, !page.items.isEmpty,
               pagination.page * pagination.size < pagination.total {
                nextPage = request.number + 1
            }
        case .failure:
            failedPage = request.number
        }
    }

    private func refreshAfterChange() {
        records = []
        nextPage = nil
        failedPage = nil
        pendingPage = PageRequest(number: 1)
        onRecordsChanged()
    }

    private struct PageRequest: Hashable {
        let number: Int
        let id = UUID()
    }
}
