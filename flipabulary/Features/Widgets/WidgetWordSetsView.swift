import SwiftUI
import SwiftData
import Combine

struct WidgetWordSetEditorView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let setID: UUID

    @State private var name = ""
    @State private var cardIDs: [UUID] = []
    @State private var didLoad = false
    @State private var isPickerPresented = false
    @State private var isDeleteConfirmationPresented = false

    private var normalizedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Word set" : trimmed
    }

    private var selectedRows: [WidgetWordSetDisplayRow] {
        let cards = app.maintenance.cards()
        let lookup = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return cardIDs.compactMap { id in
            guard let card = lookup[id] else { return nil }
            return WidgetWordSetDisplayRow(
                id: card.id,
                word: card.word,
                translation: card.translation,
                stackName: card.stack?.name ?? "My words"
            )
        }
    }

    var body: some View {
        let rows = selectedRows
        return List {
            Section {
                HStack {
                    Text("Name")
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    TextField("Word set", text: $name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(persist)
                }
            }

            Section {
                if rows.isEmpty {
                    Text("No words in this set yet.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(rows) { row in
                        WidgetWordSetRowView(row: row)
                    }
                    .onMove { offsets, destination in
                        var ids = rows.map(\.id)
                        ids.move(fromOffsets: offsets, toOffset: destination)
                        cardIDs = ids
                    }
                    .onDelete { offsets in
                        var ids = rows.map(\.id)
                        ids.remove(atOffsets: offsets)
                        cardIDs = ids
                    }
                }
            } header: {
                Text("Words")
            } footer: {
                Text("Drag words to reorder. Each widget can use a different set.")
            }

            Section {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Add words", systemImage: "plus")
                }
                .accessibilityIdentifier("widget.set.addWords")
            }

            Section {
                Button("Delete word set", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .accessibilityIdentifier("widget.set.delete")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColor.page)
        .navigationTitle(normalizedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    persist()
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .confirmationDialog(
            "Delete word set?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSet() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isPickerPresented, onDismiss: persist) {
            NavigationStack {
                WidgetWordPickerView(selectedCardIDs: $cardIDs)
                    .environment(app)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            load()
        }
        .onDisappear {
            guard didLoad else { return }
            persist()
        }
    }

    private func load() {
        guard let set = app.preferences.preferences.widgetWordSet(id: setID) else {
            dismiss()
            return
        }
        name = set.name
        let validIDs = Set(app.maintenance.cards().map(\.id))
        cardIDs = set.cardIDs.filter { validIDs.contains($0) }
    }

    private func persist() {
        var preferences = app.preferences.preferences
        guard let index = preferences.widgetWordSets.firstIndex(where: { $0.id == setID }) else { return }
        preferences.widgetWordSets[index].name = normalizedName
        preferences.widgetWordSets[index].cardIDs = cardIDs
        guard preferences != app.preferences.preferences else { return }
        app.preferences.preferences = preferences
        app.maintenance.publishSnapshot()
    }

    private func deleteSet() {
        app.haptics.warning()
        var preferences = app.preferences.preferences
        preferences.widgetWordSets.removeAll { $0.id == setID }
        if preferences.widgetDefaults.wordSetID == setID {
            preferences.widgetDefaults.wordSetID = nil
            if preferences.widgetDefaults.sort == .manual {
                preferences.widgetDefaults.sort = .dueFirst
            }
        }
        app.preferences.preferences = preferences
        app.maintenance.publishSnapshot()
        dismiss()
    }
}

private struct WidgetWordPickerSection: Identifiable {
    let name: String
    var cards: [VocabularyCard]

    var id: String { name }
}

private struct WidgetPickerEntry: Identifiable {
    let card: VocabularyCard
    let stackName: String
    let wordKey: String
    let translationKey: String
    let stackKey: String

    var id: UUID { card.id }

    func matches(_ query: String) -> Bool {
        wordKey.contains(query) || translationKey.contains(query) || stackKey.contains(query)
    }
}

struct WidgetWordSetDisplayRow: Identifiable {
    let id: UUID
    let word: String
    let translation: String
    let stackName: String
}

struct WidgetWordSetRowView: View {
    let row: WidgetWordSetDisplayRow

    var body: some View {
        HStack(spacing: 12) {
            InitialTile(word: row.word, id: row.id, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.word)
                    .font(AppFont.font(15, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(row.translation)
                    .font(AppFont.font(12, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                Text(row.stackName)
                    .font(AppFont.font(10, .medium))
                    .foregroundStyle(AppColor.accentStrong)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }
}

struct WidgetWordPickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCardIDs: [UUID]
    @State private var searchText = ""
    @State private var editorTarget: EditorTarget?
    @State private var entries: [WidgetPickerEntry] = []

    private var selected: Set<UUID> { Set(selectedCardIDs) }

    private func makeSections() -> [WidgetWordPickerSection] {
        let query = SearchNormalizer.normalize(searchText)
        var result: [WidgetWordPickerSection] = []
        var currentName: String?
        var currentCards: [VocabularyCard] = []

        func flush() {
            guard let currentName else { return }
            result.append(WidgetWordPickerSection(name: currentName, cards: currentCards))
        }

        for entry in entries {
            guard query.isEmpty || entry.matches(query) else { continue }
            if entry.stackName != currentName {
                flush()
                currentName = entry.stackName
                currentCards = []
            }
            currentCards.append(entry.card)
        }
        flush()
        return result
    }

    private func reloadEntries() {
        entries = app.maintenance.cards()
            .map { card in
                let stackName = card.stack?.name ?? "My words"
                return WidgetPickerEntry(
                    card: card,
                    stackName: stackName,
                    wordKey: SearchNormalizer.normalize(card.word),
                    translationKey: SearchNormalizer.normalize(card.translation),
                    stackKey: SearchNormalizer.normalize(stackName)
                )
            }
            .sorted { lhs, rhs in
                if lhs.stackName != rhs.stackName {
                    return lhs.stackName.localizedStandardCompare(rhs.stackName) == .orderedAscending
                }
                return lhs.card.word.localizedStandardCompare(rhs.card.word) == .orderedAscending
            }
    }

    var body: some View {
        let sections = makeSections()
        let selectedIDs = selected
        return List {
            if sections.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No words available", systemImage: "text.book.closed")
                    } description: {
                        Text("Add words in Flipabulary first, then come back to build this set.")
                    } actions: {
                        Button("New word") {
                            editorTarget = .new(
                                stackID: app.preferences.preferences.selectedStackID
                                    ?? app.library.defaultStack()?.id
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(sections) { section in
                    Section(section.name) {
                        ForEach(section.cards) { card in
                            Button {
                                toggle(card.id)
                            } label: {
                                HStack(spacing: 12) {
                                    InitialTile(word: card.word, id: card.id, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(card.word)
                                            .font(AppFont.font(15, .semibold))
                                            .foregroundStyle(AppColor.textPrimary)
                                            .lineLimit(1)
                                        Text(card.translation)
                                            .font(AppFont.font(12, .regular))
                                            .foregroundStyle(AppColor.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: selectedIDs.contains(card.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(selectedIDs.contains(card.id) ? AppColor.accentStrong : AppColor.textMuted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColor.page)
        .searchable(text: $searchText, prompt: "Search words")
        .task { reloadEntries() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reloadEntries()
        }
        .navigationTitle("Add words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new(
                        stackID: app.preferences.preferences.selectedStackID
                            ?? app.library.defaultStack()?.id
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New word")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .fullScreenCover(item: $editorTarget) { target in
            CardEditorView(target: target) { card in
                if !selectedCardIDs.contains(card.id) {
                    selectedCardIDs.append(card.id)
                }
                reloadEntries()
            }
            .environment(app)
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selectedCardIDs.firstIndex(of: id) {
            selectedCardIDs.remove(at: index)
        } else {
            selectedCardIDs.append(id)
        }
    }
}

