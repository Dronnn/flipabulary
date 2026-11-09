import SwiftUI
import SwiftData
import UIKit
import Combine

struct WordsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: [
        SortDescriptor(\VocabularyStack.sortOrder),
        SortDescriptor(\VocabularyStack.createdAt)
    ]) private var stacks: [VocabularyStack]
    @Query private var records: [DailyAdmissionRecord]

    @State private var searchText = ""
    @State private var now = Date()
    @State private var pendingEndSession: ReviewSession?
    @State private var listIndex = CardListIndex()
    @State private var dueCountCache = 0
    @State private var indexNeedsRefresh = true
    @State private var isVisible = false
    @State private var visibleLimit = 150
    @State private var refreshTask: Task<Void, Never>?
    @State private var dueTask: Task<Void, Never>?
    @State private var isBuildingSnapshot = false

    private var preferences: AppPreferences { app.preferences.preferences }

    private var selectedStack: VocabularyStack? {
        guard let id = preferences.selectedStackID else { return nil }
        return stacks.first(where: { $0.id == id })
    }

    private var dueCount: Int { dueCountCache }

    private var summary: LibrarySummary {
        listIndex.aggregate(stackID: preferences.selectedStackID).summary(due: dueCountCache)
    }

    private var categories: [CategorySummary] {
        listIndex.aggregate(stackID: preferences.selectedStackID).categories
    }

    private var scopeName: String {
        selectedStack?.name ?? "All stacks"
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mode = AppMetrics.LayoutMode.resolve(width: width)
            let effectiveMode: AppMetrics.LayoutMode = dynamicTypeSize.isAccessibilitySize ? .compact : mode
            let cards = listIndex.filter(
                stackID: preferences.selectedStackID,
                filter: preferences.filter,
                search: searchText,
                limit: visibleLimit
            )
            if effectiveMode == .compact {
                compactContent(width: width, cards: cards)
            } else {
                expandedContent(width: width, mode: effectiveMode, cards: cards)
            }
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "End unfinished session?",
            isPresented: Binding(
                get: { pendingEndSession != nil },
                set: { if !$0 { pendingEndSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("End session", role: .destructive) {
                if let session = pendingEndSession {
                    _ = app.review.endSession(session)
                    app.router.showToast("Session ended. Completed ratings were kept.")
                }
                pendingEndSession = nil
            }
            Button("Continue learning", role: .cancel) { pendingEndSession = nil }
        } message: {
            Text("Reviewed answers are kept. Only the ungraded card is discarded.")
        }
        .task {
            isVisible = true
            now = Date()
            refreshListCacheIfNeeded(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
                refreshDueCount()
            }
        }
        .onAppear {
            isVisible = true
            refreshListCacheIfNeeded()
        }
        .onDisappear {
            isVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            indexNeedsRefresh = true
            scheduleRefresh()
        }
        .onChange(of: app.router.reviewLaunch) { _, launch in
            if launch == nil { refreshListCacheIfNeeded() }
        }
        .onChange(of: app.router.editorTarget) { _, target in
            if target == nil { refreshListCacheIfNeeded() }
        }
        .onChange(of: app.router.path) { _, path in
            if path.isEmpty { refreshListCacheIfNeeded() }
        }
        .onChange(of: app.preferences.preferences.rules) { _, _ in
            indexNeedsRefresh = true
            refreshListCacheIfNeeded()
        }
        .onChange(of: preferences.selectedStackID) { _, _ in
            visibleLimit = 150
            refreshDueCount()
        }
        .onChange(of: preferences.filter) { _, _ in
            visibleLimit = 150
        }
        .onChange(of: searchText) { _, _ in
            visibleLimit = 150
        }
    }

    // MARK: Cached library data

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            refreshListCacheIfNeeded()
        }
    }

    private func refreshListCacheIfNeeded(force: Bool = false) {
        guard force || (isVisible && indexNeedsRefresh) else { return }
        guard force || (app.router.reviewLaunch == nil
            && app.router.editorTarget == nil
            && !app.router.supportVisible
            && app.router.path.isEmpty) else { return }
        guard !isBuildingSnapshot else {
            if !force { indexNeedsRefresh = true }
            return
        }
        refreshListCache()
    }

    private func refreshListCache() {
        guard !isBuildingSnapshot else {
            indexNeedsRefresh = true
            return
        }
        isBuildingSnapshot = true
        indexNeedsRefresh = false
        let scopeID = preferences.selectedStackID
        let rules = preferences.rules
        let now = Date()
        let calendar = app.maintenance.calendar
        Task { @MainActor in
            let snapshot = await app.library.buildListSnapshot(
                scopeID: scopeID,
                rules: rules,
                now: now,
                calendar: calendar
            )
            isBuildingSnapshot = false
            if let snapshot {
                listIndex = snapshot.index
                if preferences.selectedStackID == scopeID {
                    dueCountCache = snapshot.dueCount
                } else {
                    refreshDueCount()
                }
            }
            if indexNeedsRefresh {
                refreshListCacheIfNeeded()
            }
        }
    }

    private func refreshDueCount() {
        guard !indexNeedsRefresh else { return }
        dueTask?.cancel()
        let scopeID = preferences.selectedStackID
        let rules = preferences.rules
        let now = Date()
        let calendar = app.maintenance.calendar
        dueTask = Task { @MainActor in
            let due = await app.library.computeDueCount(
                scopeID: scopeID,
                rules: rules,
                now: now,
                calendar: calendar
            )
            guard !Task.isCancelled, preferences.selectedStackID == scopeID else { return }
            dueCountCache = due
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Words")
                    .font(AppFont.largeTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Menu {
                    Button {
                        selectScope(nil)
                    } label: {
                        if preferences.selectedStackID == nil {
                            Label("All stacks", systemImage: "checkmark")
                        } else {
                            Text("All stacks")
                        }
                    }
                    .accessibilityIdentifier("words.scope.all")

                    Divider()

                    ForEach(stacks, id: \.id) { stack in
                        Button {
                            selectScope(stack.id)
                        } label: {
                            if preferences.selectedStackID == stack.id {
                                Label(stack.name, systemImage: "checkmark")
                            } else {
                                Text(stack.name)
                            }
                        }
                        .accessibilityIdentifier("words.scope.\(stack.id.uuidString)")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(LocalizedStringKey(scopeName))
                                .font(AppFont.font(13, .semibold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(AppColor.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColor.accentSoft, in: Capsule())
                        Text("\(summary.saved) saved · \(dueCount) due today")
                            .font(AppFont.font(13, .regular))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(scopeName), \(summary.saved) saved, \(dueCount) due")
                .accessibilityHint("Choose stack")
                .accessibilityIdentifier("words.due")
            }
            Spacer(minLength: 4)
            Menu {
                Button("Review due cards") {
                    app.startReview(scopeID: preferences.selectedStackID)
                }
                Button("Stacks") { app.router.push(.stacks) }
                Button("Statistics") { app.router.push(.statistics(nil)) }
                Button("Settings") { app.router.push(.settings) }
                Button("Widgets") { app.router.push(.widgets) }
                Button("Import & Export") { app.router.push(.importExport) }
                Button("Support") { app.router.supportVisible = true }
                Divider()
                Button {
                    app.preferences.preferences.filter = preferences.filter == .difficult ? .all : .difficult
                } label: {
                    Text(LocalizedStringKey(preferences.filter == .difficult ? "Show all words" : "Difficult words"))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColor.surface))
                    .overlay(Circle().stroke(AppColor.divider, lineWidth: 1))
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("words.more")

            CircleIconButton(systemName: "plus", accessibilityLabel: "Add word", filled: true) {
                app.router.presentEditor(.new(stackID: preferences.selectedStackID ?? app.library.defaultStack()?.id))
            }
            .accessibilityIdentifier("words.add")

            CircleIconButton(
                systemName: "play.fill",
                accessibilityLabel: "Review due cards",
                filled: true
            ) {
                app.startReview(scopeID: preferences.selectedStackID)
            }
            .accessibilityIdentifier("words.review")
        }
    }

    private func activeSessionBanner(_ session: ReviewSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.accentStrong)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unfinished review")
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(app.review.totalReviewed(session)) answered · \(app.review.distinctCount(session)) in session")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Button("Resume") {
                app.router.reviewLaunch = ReviewLaunch(id: session.id)
            }
            .font(AppFont.font(13, .semibold))
            .foregroundStyle(AppColor.onAccent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(AppColor.accentStrong))
            .accessibilityIdentifier("words.review.resume")
            Button("End") { pendingEndSession = session }
                .font(AppFont.font(13, .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(height: 36)
        }
        .padding(14)
        .raisedSurface(radius: 16)
    }

    // MARK: Compact

    private func compactContent(width: CGFloat, cards: [CardDisplayModel]) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let session = app.review.latestActiveSession() {
                        activeSessionBanner(session)
                    }
                    if width >= 440 {
                        DueHero(due: dueCount, total: summary.saved, label: scopeName) {
                            app.startReview(scopeID: preferences.selectedStackID)
                        }
                    } else {
                        statCards
                    }
                    searchAndFilters
                }
                .padding(.top, 8)
                .padding(.bottom, 2)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            wordSection(cards: cards)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColor.page)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("words.list")
    }

    private var statCards: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    StatCard(count: summary.new, label: "New", accessibilityIdentifier: "words.stat.new")
                    StatCard(count: summary.learning, label: "Learning", accessibilityIdentifier: "words.stat.learning")
                    StatCard(count: summary.learned, label: "Learned", accessibilityIdentifier: "words.stat.learned")
                }
            } else {
                HStack(spacing: 11) {
                    StatCard(count: summary.new, label: "New", accessibilityIdentifier: "words.stat.new")
                    StatCard(count: summary.learning, label: "Learning", accessibilityIdentifier: "words.stat.learning")
                    StatCard(count: summary.learned, label: "Learned", accessibilityIdentifier: "words.stat.learned")
                }
            }
        }
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(placeholder: "Search words", text: $searchText)
            FlowLayout(spacing: 7) {
                ForEach([CardFilter.all, .learning, .learned, .new]) { filter in
                    FilterChip(
                        title: filter.title,
                        count: filter == .all ? summary.saved : categories.first(where: { $0.filter == filter })?.count,
                        isSelected: preferences.filter == filter,
                        action: { select(filter) }
                    )
                }
            }
            if preferences.filter == .difficult {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("Difficult filter is on")
                        .font(AppFont.font(12, .semibold))
                    Spacer()
                    Button("Show all") { select(.all) }
                        .font(AppFont.font(12, .semibold))
                        .foregroundStyle(AppColor.accentStrong)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(AppColor.accentInk)
                .padding(.horizontal, 12)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .contain)
            }
        }
    }

    @ViewBuilder
    private func wordSection(cards: [CardDisplayModel]) -> some View {
        Section {
            if isBuildingSnapshot && listIndex.entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .listRowBackground(AppColor.surface)
                    .accessibilityIdentifier("words.loading")
            } else if cards.isEmpty {
                emptyState
                    .listRowBackground(AppColor.surface)
            } else {
                ForEach(Array(cards.enumerated()), id: \.element.id) { _, card in
                    WordRow(card: card) {
                        app.router.presentEditor(.edit(card.id))
                    }
                    .accessibilityIdentifier("words.row")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(AppColor.surface)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 72 }
                    .listRowSeparatorTint(AppColor.divider)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(card)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onAppear {
                        loadMore(after: card.id, in: cards)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if summary.saved == 0 {
            EmptyStateView(
                title: "Your word list is empty",
                message: "Save a word and its translation to start practicing.",
                actionTitle: "Add your first word",
                action: {
                    app.router.presentEditor(.new(stackID: preferences.selectedStackID ?? app.library.defaultStack()?.id))
                }
            )
            .accessibilityIdentifier("words.empty")
        } else {
            EmptyStateView(
                title: searchText.isEmpty ? "No words here" : "No matches",
                message: searchText.isEmpty
                    ? "Try another filter or stack."
                    : "Try a different spelling or clear the search.",
                actionTitle: "Reset filters",
                action: resetFilters
            )
            .accessibilityIdentifier("words.empty.results")
        }
    }

    private func wordList(cards: [CardDisplayModel]) -> some View {
        List {
            wordSection(cards: cards)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .accessibilityIdentifier("words.list")
    }

    private func loadMore(after id: UUID, in cards: [CardDisplayModel]) {
        guard id == cards.last?.id, cards.count >= visibleLimit else { return }
        visibleLimit += 150
    }

    private func delete(_ card: CardDisplayModel) {
        guard let model = app.library.card(id: card.id) else { return }
        switch app.library.deleteCard(model) {
        case .success:
            refreshTask?.cancel()
            listIndex = listIndex.removing(cardID: card.id)
            indexNeedsRefresh = false
            refreshDueCount()
            app.router.showToast("Word deleted.")
        case .failure(let error):
            app.router.showToast(error.localizedDescription)
        }
    }

    // MARK: Expanded

    private func expandedContent(width: CGFloat, mode: AppMetrics.LayoutMode, cards: [CardDisplayModel]) -> some View {
        let gap = mode.gap
        let leftWidth = mode == .duo
            ? min(mode.leftWidth, max(200, width * 0.35))
            : min(mode.leftWidth, max(240, width * 0.36))
        return VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, mode.inset)
                .padding(.top, 12)
            if let session = app.review.latestActiveSession() {
                activeSessionBanner(session)
                    .padding(.horizontal, mode.inset)
            }
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: 12) {
                    searchAndFilters
                    wordList(cards: cards)
                }
                .frame(width: leftWidth)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        DueHero(
                            due: dueCount,
                            total: summary.saved,
                            label: scopeName,
                            ringSize: mode == .pad ? 150 : 130
                        ) {
                            app.startReview(scopeID: preferences.selectedStackID)
                        }
                        HStack(spacing: 11) {
                            StatCard(count: summary.new, label: "New")
                            StatCard(count: summary.learning, label: "Learning")
                            StatCard(count: summary.learned, label: "Learned")
                        }
                        SectionHeader(title: "Categories")
                        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(categories) { category in
                                CategoryTile(
                                    summary: category,
                                    total: summary.saved,
                                    isSelected: preferences.filter == category.filter
                                ) {
                                    select(category.filter)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, mode.inset)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: min(width, AppMetrics.maxWorkingWidth), alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Actions

    private func selectScope(_ id: UUID?) {
        app.preferences.preferences.selectedStackID = id
    }

    private func select(_ filter: CardFilter) {
        app.preferences.preferences.filter = filter
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resetFilters() {
        searchText = ""
        visibleLimit = 150
        app.preferences.preferences.filter = .all
        app.preferences.preferences.selectedStackID = app.library.defaultStack()?.id
    }
}

struct ReviewScopePickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    let picker: ScopePickerState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose one stack for this session. Each stack keeps its own limits and learning rules.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                    GroupedSurface {
                        ForEach(Array(picker.stacks.enumerated()), id: \.element.id) { index, stack in
                            Button {
                                dismiss()
                                app.preferences.preferences.selectedStackID = stack.id
                                app.startReview(scopeID: stack.id)
                            } label: {
                                HStack(spacing: 12) {
                                    InitialTile(word: stack.name, id: stack.id, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stack.name)
                                            .font(AppFont.fieldValue())
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text("\(stack.savedCount) saved · \(stack.dueCount) due")
                                            .font(AppFont.caption())
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(AppColor.textMuted)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < picker.stacks.count - 1 { SettingsDivider(inset: 68) }
                        }
                    }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle("Review due cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
