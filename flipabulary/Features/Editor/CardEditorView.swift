import SwiftUI
import SwiftData

struct CardEditorView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let target: EditorTarget
    var onSaved: ((VocabularyCard) -> Void)? = nil

    @State private var draft = CardDraft()
    @State private var initialDraft = CardDraft()
    @State private var existingCard: VocabularyCard?
    @State private var validation = CardValidation.valid
    @State private var generalError: String?
    @State private var duplicateCard: VocabularyCard?
    @State private var duplicateStackName = "My words"
    @State private var showDuplicateWarning = false
    @State private var showDiscardConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showStackPicker = false
    @State private var showTagPicker = false
    @State private var addAnother = false
    @State private var moreDetailsExpanded = false
    @State private var isSaving = false
    @State private var didLoad = false
    @State private var savedFeedback: String?
    @State private var stackName = "Choose a stack"
    @State private var wordStats: WordStatistics?
    @State private var streakValue = 0
    @State private var statsTask: Task<Void, Never>?

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case word, sourceExample, translation, translatedExample, phonetic, partOfSpeech
    }

    private var isEditing: Bool { existingCard != nil }
    private var isDirty: Bool {
        if isEditing {
            return draft != initialDraft
        }
        return draft != initialDraft
    }

    private var title: String {
        isEditing ? "Edit word" : "New word"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
                let usesCompactLayout = mode == .compact || dynamicTypeSize.isAccessibilitySize
                ScrollView {
                    if usesCompactLayout {
                        compactForm
                    } else {
                        expandedForm(mode: mode)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if usesCompactLayout {
                        bottomActions
                    }
                }
            }
            .pageBackground()
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        attemptClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close editor")
                    .accessibilityIdentifier("card.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { attemptSave(addAnyway: false) }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                        .accessibilityIdentifier("card.save.toolbar")
                }
            }
            .alert("Word already saved", isPresented: $showDuplicateWarning) {
                Button("Add anyway") {
                    addAnywaySave()
                }
                Button("Edit existing") {
                    editDuplicate()
                }
                Button("Cancel", role: .cancel) {
                    duplicateCard = nil
                }
            } message: {
                Text(
                    String(
                        format: app.localized("The same word and translation already exist in %@."),
                        duplicateStackName
                    )
                )
            }
            .confirmationDialog(
                "Discard this draft?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard draft", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Delete this word?", isPresented: $showDeleteConfirmation) {
                Button("Delete word", role: .destructive) { deleteCard() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The word, its examples, and its learning history will be removed from all surfaces.")
            }
            .sheet(isPresented: $showStackPicker) {
                StackPickerView(selection: $draft.stackID)
                    .environment(app)
            }
            .sheet(isPresented: $showTagPicker) {
                TagPickerView(selectedNames: $draft.tagNames)
                    .environment(app)
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .task {
                loadIfNeeded()
            }
            .onChange(of: draft.stackID) { _, _ in
                updateStackName()
            }
        }
    }

    // MARK: Forms

    private var compactForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let savedFeedback {
                InlineMessage(text: savedFeedback, kind: .success)
            }
            cardFields
            organization
            if isEditing {
                wordStatisticsSection
            }
            moreDetails
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func expandedForm(mode: AppMetrics.LayoutMode) -> some View {
        let preview = previewModel()
        let leftWidth = mode == .duo ? min(mode.leftWidth, 240) : mode.leftWidth
        return HStack(alignment: .top, spacing: mode.gap) {
            VStack(alignment: .leading, spacing: 16) {
                CardPreview(card: preview)
                if isEditing {
                    editingActions
                }
            }
            .frame(width: leftWidth)

            VStack(alignment: .leading, spacing: 16) {
                if let savedFeedback {
                    InlineMessage(text: savedFeedback, kind: .success)
                }
                cardFields
                organization
                if isEditing {
                    wordStatisticsSection
                }
                moreDetails
                if !isEditing {
                    addAnotherRow
                }
                expandedActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 820, alignment: .center)
        .padding(.horizontal, mode.inset)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var cardFields: some View {
        GroupedSurface {
            VStack(spacing: 0) {
                fieldBlock(
                    label: "Word",
                    text: $draft.word,
                    placeholder: "Word",
                    limit: 200,
                    error: validation.wordError,
                    field: .word,
                    axis: .horizontal,
                    identifier: "card.word",
                    isRequired: true
                )
                SettingsDivider(inset: 16)
                fieldBlock(
                    label: "Example",
                    text: $draft.sourceExample,
                    placeholder: "Optional source example",
                    limit: 2_000,
                    error: validation.sourceExampleError,
                    field: .sourceExample,
                    axis: .vertical,
                    identifier: "card.sourceExample"
                )
                SettingsDivider(inset: 16)
                fieldBlock(
                    label: "Translation",
                    text: $draft.translation,
                    placeholder: "Translation",
                    limit: 200,
                    error: validation.translationError,
                    field: .translation,
                    axis: .horizontal,
                    identifier: "card.translation",
                    isRequired: true
                )
                SettingsDivider(inset: 16)
                fieldBlock(
                    label: "Translated example",
                    text: $draft.translatedExample,
                    placeholder: "Optional translated example",
                    limit: 2_000,
                    error: validation.translatedExampleError,
                    field: .translatedExample,
                    axis: .vertical,
                    identifier: "card.translatedExample"
                )
            }
        }
    }

    private var organization: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Organization")
            GroupedSurface {
                SettingsRow(title: "Stack", value: stackName, showsChevron: true) {
                    showStackPicker = true
                }
                .accessibilityIdentifier("card.stack")
                if let error = validation.stackError {
                    InlineMessage(text: error).padding(.horizontal, 16).padding(.bottom, 10)
                }
                SettingsDivider(inset: 16)
                SettingsRow(
                    title: "Tags",
                    value: draft.tagNames.isEmpty ? "None" : draft.tagNames.joined(separator: ", "),
                    showsChevron: true
                ) {
                    showTagPicker = true
                }
                .accessibilityIdentifier("card.tags")
                if let error = validation.tagError {
                    InlineMessage(text: error).padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }
    }

    private var wordStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Statistics")
            GroupedSurface {
                if let stats = wordStats {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            swipeCountTile(
                                title: "Again",
                                count: stats.againCount,
                                systemImage: "arrow.left.circle.fill",
                                tint: AppColor.danger,
                                accessibilityIdentifier: "card.stats.again"
                            )
                            swipeCountTile(
                                title: "Good",
                                count: stats.goodCount,
                                systemImage: "arrow.right.circle.fill",
                                tint: AppColor.success,
                                accessibilityIdentifier: "card.stats.good"
                            )
                        }
                        .padding(14)

                        SettingsDivider(inset: 16)
                        difficultyRow(stats)
                        SettingsDivider(inset: 16)
                        statRow("Total reviews", "\(stats.totalGrades)", id: "card.stats.total")
                        SettingsDivider(inset: 16)
                        statRow("Accuracy", stats.accuracy.formatted(.percent.precision(.fractionLength(0))), id: "card.stats.accuracy")
                        SettingsDivider(inset: 16)
                        statRow("Total time", DurationFormatting.short(stats.totalSeconds), id: "card.stats.totalTime")
                        SettingsDivider(inset: 16)
                        statRow("Average time", DurationFormatting.short(stats.averageSeconds), id: "card.stats.averageTime")
                        SettingsDivider(inset: 16)
                        statRow(
                            "Front / back",
                            "\(DurationFormatting.short(stats.frontSeconds)) / \(DurationFormatting.short(stats.backSeconds))",
                            id: "card.stats.faces"
                        )
                        SettingsDivider(inset: 16)
                        statRow(
                            "Last review",
                            stats.lastReviewedAt.map {
                                $0.formatted(date: .abbreviated, time: .shortened)
                            } ?? "Never",
                            id: "card.stats.last"
                        )
                        SettingsDivider(inset: 16)
                        statRow(
                            "Next review",
                            stats.nextDueAt.map {
                                $0.formatted(date: .abbreviated, time: .shortened)
                            } ?? (stats.isFullyMastered ? app.localized("Fully learned") : "—"),
                            id: "card.stats.next"
                        )
                        SettingsDivider(inset: 16)
                        streakRow(stats)
                        SettingsDivider(inset: 16)
                        masteryRow(stats)
                        if !stats.history.isEmpty {
                            SettingsDivider(inset: 16)
                            historySection(stats)
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 96)
                }
            }
        }
    }

    private func swipeCountTile(
        title: String,
        count: Int,
        systemImage: String,
        tint: Color,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(LocalizedStringKey(title))
                    .font(AppFont.font(12, .semibold))
            }
            .foregroundStyle(tint)
            Text("\(count)")
                .font(AppFont.statCount())
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func difficultyRow(_ stats: WordStatistics) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(stats.isDifficult ? AppColor.accentStrong : AppColor.textMuted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Difficult words")
                    .font(AppFont.fieldValue())
                    .foregroundStyle(AppColor.textPrimary)
                Text(LocalizedStringKey(stats.isDifficult ? "In Difficult words" : "Not in Difficult words"))
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 8)
            Button(LocalizedStringKey(stats.isDifficult ? "Remove from Difficult" : "Mark as Difficult")) {
                setDifficult(!stats.isDifficult)
            }
            .font(AppFont.font(12, .semibold))
            .foregroundStyle(AppColor.accentStrong)
            .frame(minHeight: 44)
            .accessibilityIdentifier("card.difficultToggle")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }

    private func statRow(_ title: String, _ value: String, id: String) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(AppFont.fieldValue())
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(AppFont.font(14, .regular))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityIdentifier(id)
    }

    private func streakRow(_ stats: WordStatistics) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Correct streak")
                    .font(AppFont.fieldValue())
                    .foregroundStyle(AppColor.textPrimary)
                Text(String(format: app.localized("%lld of %lld"), streakValue, stats.threshold))
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 8)
            StepperCapsule(
                label: "Correct streak",
                value: Binding(
                    get: { streakValue },
                    set: { updateStreak($0) }
                ),
                range: 0...100,
                accessibilityIdentifier: "card.streak"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }

    @ViewBuilder
    private func masteryRow(_ stats: WordStatistics) -> some View {
        Button {
            setFullyLearned(!stats.isFullyMastered)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: stats.isFullyMastered ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(stats.isFullyMastered ? AppColor.success : AppColor.accentStrong)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(stats.isFullyMastered ? "Fully learned" : "Mark fully learned"))
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    Text(LocalizedStringKey(stats.isFullyMastered
                        ? "Return to learning to review it again."
                        : "Complete every learning stage as if all answers were Good."))
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if stats.isFullyMastered {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(AppColor.accentStrong)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.markMastered")
    }

    private func historySection(_ stats: WordStatistics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent answers")
                .font(AppFont.sectionLabel())
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(stats.history.prefix(6)) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.grade == .good ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                        .foregroundStyle(item.grade == .good ? AppColor.success : AppColor.danger)
                    Text(LocalizedStringKey(item.grade.title))
                        .font(AppFont.font(12, .medium))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 6)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                    Text(DurationFormatting.short(item.frontSeconds + item.backSeconds))
                        .font(AppFont.font(11, .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
            }
        }
        .padding(.bottom, 8)
    }

    private var moreDetails: some View {
        GroupedSurface {
            DisclosureGroup(isExpanded: $moreDetailsExpanded) {
                VStack(spacing: 0) {
                    fieldBlock(
                        label: "Phonetic",
                        text: $draft.phonetic,
                        placeholder: "Optional pronunciation",
                        limit: 200,
                        error: nil,
                        field: .phonetic,
                        axis: .horizontal
                    )
                    SettingsDivider(inset: 16)
                    fieldBlock(
                        label: "Part of speech",
                        text: $draft.partOfSpeech,
                        placeholder: "e.g. adj, n, vt",
                        limit: 80,
                        error: nil,
                        field: .partOfSpeech,
                        axis: .horizontal
                    )
                }
            } label: {
                HStack {
                    Text("More details")
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("Optional")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .tint(AppColor.accent)
            .padding(.horizontal, 16)
        }
    }

    private var addAnotherRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add another word")
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Keep this stack and these tags for the next card.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Toggle("Add another word", isOn: $addAnother)
                .labelsHidden()
                .toggleStyle(CompactToggleStyle())
                .accessibilityIdentifier("card.addAnother")
        }
        .padding(14)
        .raisedSurface(radius: 16)
    }

    private var editingActions: some View {
        VStack(spacing: 10) {
            SecondaryActionButton(title: "Review this card", systemImage: "play.fill") {
                startCardReview()
            }
            .accessibilityIdentifier("card.review")
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete word")
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(AppColor.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.delete")
        }
    }

    private var expandedActions: some View {
        VStack(spacing: 8) {
            if let generalError {
                InlineMessage(text: generalError, kind: .error)
            }
            PrimaryActionButton(
                title: isEditing ? "Save changes" : "Add card",
                systemImage: isEditing ? "checkmark" : "plus",
                isEnabled: !isSaving,
                isWorking: isSaving
            ) {
                attemptSave(addAnyway: false)
            }
            .accessibilityIdentifier("card.save")
        }
        .padding(.top, 4)
    }

    private var bottomActions: some View {
        VStack(spacing: 8) {
            if let generalError {
                InlineMessage(text: generalError, kind: .error)
            }
            if isEditing {
                HStack(spacing: 10) {
                    compactDeleteButton
                    compactReviewButton
                }
            } else {
                compactAddAnotherRow
            }
            PrimaryActionButton(
                title: isEditing ? "Save changes" : "Add card",
                systemImage: isEditing ? "checkmark" : "plus",
                isEnabled: !isSaving,
                isWorking: isSaving
            ) {
                attemptSave(addAnyway: false)
            }
            .accessibilityIdentifier("card.save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var compactAddAnotherRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add another word")
                    .font(AppFont.font(13, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Keep this stack and these tags for the next card.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 8)
            Toggle("Add another word", isOn: $addAnother)
                .labelsHidden()
                .toggleStyle(CompactToggleStyle())
                .accessibilityIdentifier("card.addAnother")
        }
        .frame(minHeight: 44)
    }

    private var compactDeleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
                .font(AppFont.font(14, .semibold))
                .foregroundStyle(AppColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AppColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete word")
        .accessibilityIdentifier("card.delete")
    }

    private var compactReviewButton: some View {
        Button {
            startCardReview()
        } label: {
            Label("Review", systemImage: "play.fill")
                .font(AppFont.font(14, .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColor.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.review")
    }

    // MARK: Field UI

    private func fieldBlock(
        label: String,
        text: Binding<String>,
        placeholder: String,
        limit: Int,
        error: String?,
        field: Field,
        axis: Axis,
        identifier: String? = nil,
        isRequired: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppFont.sectionLabel())
                .foregroundStyle(AppColor.textSecondary)
            TextField("", text: text, prompt: Text(LocalizedStringKey(placeholder)).foregroundStyle(AppColor.textMuted), axis: axis)
                .font(AppFont.font(17, axis == .vertical ? .regular : .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
                .focused($focus, equals: field)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier ?? "")
            HStack {
                if let error {
                    Text(error)
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.danger)
                } else if isRequired {
                    Text("Required")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textMuted)
                }
                Spacer()
                if text.wrappedValue.count > limit / 2 {
                    Text("\(max(0, limit - text.wrappedValue.count)) left")
                        .font(AppFont.caption())
                        .foregroundStyle(text.wrappedValue.count > limit ? AppColor.danger : AppColor.textMuted)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
    }

    // MARK: Load and save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        switch target {
        case .new(let stackID):
            draft = CardDraft()
            draft.stackID = stackID ?? app.library.selectedStack()?.id ?? app.library.defaultStack()?.id
            initialDraft = draft
            updateStackName()
        case .edit(let id):
            guard let card = app.library.card(id: id) else {
                generalError = "This word is no longer available."
                return
            }
            existingCard = card
            draft = CardDraft(card: card)
            initialDraft = draft
            updateStackName()
            refreshWordStatistics()
        }
    }

    private func updateStackName() {
        stackName = app.library.stack(id: draft.stackID)?.name ?? "Choose a stack"
    }

    private func refreshWordStatistics() {
        guard let cardID = existingCard?.id else {
            wordStats = nil
            streakValue = 0
            return
        }
        statsTask?.cancel()
        let calendar = app.maintenance.calendar
        statsTask = Task { @MainActor in
            let stats = await app.library.wordStatistics(
                cardID: cardID,
                now: Date(),
                calendar: calendar
            )
            guard !Task.isCancelled else { return }
            wordStats = stats
            streakValue = stats?.repeatCount ?? 0
        }
    }

    private func updateStreak(_ value: Int) {
        guard let cardID = existingCard?.id else { return }
        streakValue = value
        switch app.library.setCorrectStreak(cardID: cardID, value: value) {
        case .success:
            generalError = nil
            refreshWordStatistics()
        case .failure(let error):
            generalError = error.localizedDescription
            refreshWordStatistics()
        }
    }

    private func setDifficult(_ difficult: Bool) {
        guard let cardID = existingCard?.id else { return }
        switch app.library.setDifficult(cardID: cardID, isDifficult: difficult) {
        case .success:
            generalError = nil
            app.haptics.selection()
            app.router.showToast(difficult ? "Word marked as difficult." : "Word removed from Difficult.")
            refreshWordStatistics()
        case .failure(let error):
            generalError = error.localizedDescription
        }
    }

    private func setFullyLearned(_ mastered: Bool) {
        guard let cardID = existingCard?.id else { return }
        switch app.library.setFullyLearned(cardID: cardID, mastered: mastered) {
        case .success:
            generalError = nil
            app.haptics.selection()
            app.router.showToast(mastered ? "Word marked as fully learned." : "Word returned to learning.")
            refreshWordStatistics()
        case .failure(let error):
            generalError = error.localizedDescription
        }
    }

    private func attemptClose() {
        if isDirty {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func attemptSave(addAnyway: Bool) {
        guard !isSaving else { return }
        validation = app.library.validate(draft, excluding: existingCard?.id)
        generalError = nil
        guard validation.isValid else {
            app.haptics.error()
            focusFirstInvalid()
            return
        }
        if !addAnyway, let duplicate = app.library.duplicateInLibrary(of: draft, excluding: existingCard?.id) {
            duplicateCard = duplicate
            duplicateStackName = duplicate.stack?.name ?? "My words"
            showDuplicateWarning = true
            app.haptics.warning()
            return
        }

        isSaving = true
        defer { isSaving = false }
        let wasEditing = existingCard != nil
        let result = app.library.saveCard(draft: draft, existing: existingCard, addAnyway: addAnyway)
        switch result {
        case .success(let card):
            existingCard = card
            initialDraft = draft
            onSaved?(card)
            app.haptics.success()
            if addAnother && !wasEditing {
                keepOrganizationAndClear()
            } else {
                dismiss()
                app.router.showToast(wasEditing ? "Changes saved." : "Word added.")
            }
        case .failure(let error):
            if case .duplicate(let duplicateID) = error {
                duplicateCard = app.library.card(id: duplicateID)
                showDuplicateWarning = true
            } else if case .invalid(let result) = error {
                validation = result
                focusFirstInvalid()
            } else {
                generalError = error.localizedDescription
            }
        }
    }

    private func addAnywaySave() {
        duplicateCard = nil
        attemptSave(addAnyway: true)
    }

    private func editDuplicate() {
        guard let duplicate = duplicateCard else { return }
        existingCard = duplicate
        draft = CardDraft(card: duplicate)
        initialDraft = draft
        updateStackName()
        refreshWordStatistics()
        validation = .valid
        duplicateCard = nil
        app.router.showToast("Editing the existing word.")
    }

    private func keepOrganizationAndClear() {
        let stackID = draft.stackID
        let tags = draft.tagNames
        draft = CardDraft()
        draft.stackID = stackID
        draft.tagNames = tags
        initialDraft = draft
        existingCard = nil
        wordStats = nil
        streakValue = 0
        validation = .valid
        duplicateCard = nil
        generalError = nil
        savedFeedback = "Saved. Add another word."
        focus = .word
    }

    private func deleteCard() {
        guard let existingCard else { return }
        switch app.library.deleteCard(existingCard) {
        case .success:
            app.haptics.warning()
            dismiss()
            app.router.showToast("Word deleted.")
        case .failure(let error):
            generalError = error.localizedDescription
        }
    }

    private func startCardReview() {
        if isDirty {
            validation = app.library.validate(draft, excluding: existingCard?.id)
            generalError = nil
            guard validation.isValid else {
                focusFirstInvalid()
                return
            }
            if let duplicate = app.library.duplicateInLibrary(of: draft, excluding: existingCard?.id) {
                duplicateCard = duplicate
                duplicateStackName = duplicate.stack?.name ?? "My words"
                showDuplicateWarning = true
                return
            }
            switch app.library.saveCard(draft: draft, existing: existingCard, addAnyway: false) {
            case .success(let saved):
                existingCard = saved
                initialDraft = draft
                onSaved?(saved)
            case .failure(let error):
                generalError = error.localizedDescription
                return
            }
        }
        guard let card = existingCard else { return }
        let id = card.id
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            app.startReview(scopeID: nil, singleCardID: id)
        }
    }

    private func focusFirstInvalid() {
        if validation.wordError != nil { focus = .word }
        else if validation.translationError != nil { focus = .translation }
        else if validation.sourceExampleError != nil { focus = .sourceExample }
        else if validation.translatedExampleError != nil { focus = .translatedExample }
    }

    private func previewModel() -> CardDisplayModel? {
        if let existingCard {
            var model = LibraryProjection.displayModel(
                card: existingCard,
                stack: existingCard.stack ?? app.library.defaultStack() ?? VocabularyStack(name: "My words"),
                rules: app.preferences.preferences.rules,
                recentGrades: []
            )
            model.word = draft.trimmedWord
            model.translation = draft.trimmedTranslation
            model.sourceExample = draft.sourceExample.nilIfEmptyTrimmed
            model.translatedExample = draft.translatedExample.nilIfEmptyTrimmed
            model.phonetic = draft.phonetic.nilIfEmptyTrimmed
            model.partOfSpeech = draft.partOfSpeech.nilIfEmptyTrimmed
            model.stackName = stackName
            return model
        }
        guard !draft.trimmedWord.isEmpty || !draft.trimmedTranslation.isEmpty else { return nil }
        return CardDisplayModel(
            id: UUID(),
            word: draft.trimmedWord,
            translation: draft.trimmedTranslation,
            sourceExample: draft.sourceExample.nilIfEmptyTrimmed,
            translatedExample: draft.translatedExample.nilIfEmptyTrimmed,
            phonetic: draft.phonetic.nilIfEmptyTrimmed,
            partOfSpeech: draft.partOfSpeech.nilIfEmptyTrimmed,
            stackID: draft.stackID ?? UUID(),
            stackName: stackName,
            tagNames: draft.tagNames,
            lifecycle: .new,
            repeatCount: 0,
            threshold: app.preferences.preferences.rules.correctThreshold,
            nextDueAt: nil,
            createdAt: Date(),
            recentGrades: []
        )
    }
}

// MARK: - Stack picker

struct StackPickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: UUID?

    @State private var newStackName = ""
    @State private var error: String?

    var body: some View {
        let stacks = app.library.stacks()
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupedSurface {
                        ForEach(Array(stacks.enumerated()), id: \.element.id) { index, stack in
                            Button {
                                selection = stack.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    InitialTile(word: stack.name, id: stack.id, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stack.name)
                                            .font(AppFont.fieldValue())
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text("\(stack.cards.count) words")
                                            .font(AppFont.caption())
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    if selection == stack.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppColor.accentStrong)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < stacks.count - 1 {
                                SettingsDivider(inset: 66)
                            }
                        }
                    }
                    SectionHeader(title: "New stack")
                    GroupedSurface {
                        HStack(spacing: 10) {
                            TextField("Stack name", text: $newStackName)
                                .font(AppFont.font(15, .regular))
                                .textInputAutocapitalization(.words)
                            Button("Create") { createStack() }
                                .font(AppFont.font(14, .semibold))
                                .foregroundStyle(AppColor.accentStrong)
                                .disabled(newStackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(16)
                    }
                    if let error {
                        InlineMessage(text: error)
                    }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle("Choose stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func createStack() {
        switch app.library.createStack(named: newStackName) {
        case .success(let stack):
            selection = stack.id
            newStackName = ""
            error = nil
            dismiss()
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Tag picker

struct TagPickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedNames: [String]

    @State private var query = ""
    @State private var newTagName = ""
    @State private var error: String?

    private var allNames: [String] {
        let existing = app.library.tags().map(\.name)
        var names = Array(Set(existing + selectedNames)).sorted()
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            names = names.filter {
                SearchNormalizer.normalize($0).contains(SearchNormalizer.normalize(query))
            }
        }
        return names
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SearchField(placeholder: "Search tags", text: $query, accessibilityIdentifier: "tags.search")
                    GroupedSurface {
                        if allNames.isEmpty {
                            EmptyStateView(title: "No tags yet", message: "Create a tag to group related words.")
                        } else {
                            ForEach(Array(allNames.enumerated()), id: \.element) { index, name in
                                Button {
                                    toggle(name)
                                } label: {
                                    HStack {
                                        Text(name)
                                            .font(AppFont.fieldValue())
                                            .foregroundStyle(AppColor.textPrimary)
                                        Spacer()
                                        Image(systemName: isSelected(name) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected(name) ? AppColor.accentStrong : AppColor.textMuted)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 50)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < allNames.count - 1 { SettingsDivider(inset: 16) }
                            }
                        }
                    }
                    SectionHeader(title: "Create tag")
                    GroupedSurface {
                        HStack(spacing: 10) {
                            TextField("Tag name", text: $newTagName)
                                .font(AppFont.font(15, .regular))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Add") { createTag() }
                                .font(AppFont.font(14, .semibold))
                                .foregroundStyle(AppColor.accentStrong)
                                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(16)
                    }
                    if let error { InlineMessage(text: error) }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isSelected(_ name: String) -> Bool {
        selectedNames.contains { SearchNormalizer.normalize($0) == SearchNormalizer.normalize(name) }
    }

    private func toggle(_ name: String) {
        if let index = selectedNames.firstIndex(where: { SearchNormalizer.normalize($0) == SearchNormalizer.normalize(name) }) {
            selectedNames.remove(at: index)
        } else {
            selectedNames.append(name)
        }
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard name.count <= 60 else {
            error = "Tag names are limited to 60 characters."
            return
        }
        if !isSelected(name) {
            selectedNames.append(name)
        }
        newTagName = ""
        error = nil
    }
}

private extension String {
    var nilIfEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
