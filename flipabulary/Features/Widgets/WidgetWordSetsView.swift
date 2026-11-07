import SwiftUI
import SwiftData

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

    private var selectedRows: [WidgetWordSetRow] {
        let cards = app.maintenance.cards()
        let lookup = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return cardIDs.compactMap { id in
            guard let card = lookup[id] else { return nil }
            return WidgetWordSetRow(card: card, stackName: card.stack?.name ?? "My words")
        }
    }

    var body: some View {
        List {
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
                if selectedRows.isEmpty {
                    Text("No words in this set yet.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(selectedRows) { row in
                        WidgetWordSetRowView(row: row)
                    }
                    .onMove { offsets, destination in
                        var ids = selectedRows.map(\.id)
                        ids.move(fromOffsets: offsets, toOffset: destination)
                        cardIDs = ids
                    }
                    .onDelete { offsets in
                        var ids = selectedRows.map(\.id)
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
        .onChange(of: cardIDs) { _, _ in
            guard didLoad else { return }
            persist()
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
    let cards: [VocabularyCard]

    var id: String { name }
}

private struct WidgetWordSetRow: Identifiable {
    let card: VocabularyCard
    let stackName: String

    var id: UUID { card.id }
}

private struct WidgetWordSetRowView: View {
    let row: WidgetWordSetRow

    var body: some View {
        HStack(spacing: 12) {
            InitialTile(word: row.card.word, id: row.card.id, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.card.word)
                    .font(AppFont.font(15, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(row.card.translation)
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
    @State private var isQuickAddPresented = false

    private var selected: Set<UUID> { Set(selectedCardIDs) }

    private var sections: [WidgetWordPickerSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cards = app.maintenance.cards().filter { card in
            guard !query.isEmpty else { return true }
            return card.word.localizedCaseInsensitiveContains(query)
                || card.translation.localizedCaseInsensitiveContains(query)
                || (card.stack?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
        let grouped = Dictionary(grouping: cards) { card in
            card.stack?.name ?? "My words"
        }
        return grouped.map { name, cards in
            WidgetWordPickerSection(
                name: name,
                cards: cards.sorted {
                    $0.word.localizedStandardCompare($1.word) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if sections.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No words available", systemImage: "text.book.closed")
                    } description: {
                        Text("Add words in Flipabulary first, then come back to build this set.")
                    } actions: {
                        Button("New word") { isQuickAddPresented = true }
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
                                    Image(systemName: selected.contains(card.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(selected.contains(card.id) ? AppColor.accentStrong : AppColor.textMuted)
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
        .navigationTitle("Add words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isQuickAddPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New word")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $isQuickAddPresented) {
            WidgetWordQuickAddView { card in
                if !selectedCardIDs.contains(card.id) {
                    selectedCardIDs.append(card.id)
                }
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

struct WidgetWordQuickAddView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let onSaved: (VocabularyCard) -> Void

    @State private var word = ""
    @State private var translation = ""
    @State private var stackID: UUID?
    @State private var error: String?
    @State private var didLoad = false

    private var stacks: [VocabularyStack] { app.library.stacks() }

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stackID != nil
    }

    private var stackName: String {
        stacks.first(where: { $0.id == stackID })?.name ?? "Choose stack"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Word", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Translation", text: $translation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Menu {
                        ForEach(stacks) { stack in
                            Button(stack.name) { stackID = stack.id }
                        }
                    } label: {
                        HStack {
                            Text("Stack")
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Text(stackName)
                                .foregroundStyle(AppColor.textSecondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.textMuted)
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.page)
            .navigationTitle("New word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                stackID = app.library.defaultStack()?.id ?? stacks.first?.id
            }
        }
    }

    private func save() {
        var draft = CardDraft()
        draft.word = word
        draft.translation = translation
        draft.stackID = stackID

        switch app.library.saveCard(draft: draft, existing: nil) {
        case .success(let card):
            onSaved(card)
            dismiss()
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }
}
