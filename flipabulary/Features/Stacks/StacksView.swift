import SwiftUI
import SwiftData

struct StacksView: View {
    @Environment(AppEnvironment.self) private var app

    @State private var showCreateAlert = false
    @State private var newStackName = ""
    @State private var renameStack: VocabularyStack?
    @State private var renameText = ""
    @State private var deleteStack: VocabularyStack?
    @State private var error: String?
    private let allStacksTileID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

    var body: some View {
        let stacks = app.library.stacks()
        let displays = LibraryProjection.stackDisplays(
            stacks: stacks,
            cards: app.maintenance.cardsForList(),
            records: app.maintenance.records(),
            globalRules: app.preferences.preferences.rules,
            now: app.maintenance.clock.now,
            calendar: app.maintenance.calendar
        )
        let displaysByID = Dictionary(displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allSaved = displays.reduce(0) { $0 + $1.savedCount }
        let allDue = displays.reduce(0) { $0 + $1.dueCount }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Stacks keep words and their practice settings together.")
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textSecondary)

                GroupedSurface {
                    Button {
                        select(nil)
                    } label: {
                        stackRow(
                            name: "All stacks",
                            saved: allSaved,
                            due: allDue,
                            isSelected: app.preferences.preferences.selectedStackID == nil,
                            tileID: allStacksTileID
                        )
                    }
                    .buttonStyle(.plain)
                    SettingsDivider(inset: 16)
                    ForEach(Array(stacks.enumerated()), id: \.element.id) { index, stack in
                        HStack(spacing: 0) {
                            Button {
                                select(stack.id)
                            } label: {
                                stackRow(
                                    name: stack.name,
                                    saved: displaysByID[stack.id]?.savedCount ?? 0,
                                    due: displaysByID[stack.id]?.dueCount ?? 0,
                                    isSelected: app.preferences.preferences.selectedStackID == stack.id,
                                    isDefault: stack.isDefault,
                                    tileID: stack.id
                                )
                            }
                            .buttonStyle(.plain)
                            Button {
                                app.router.push(.stackSettings(stack.id))
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Settings for \(stack.name)")
                            Menu {
                                Button("Rename") {
                                    renameStack = stack
                                    renameText = stack.name
                                }
                                Button("Settings") { app.router.push(.stackSettings(stack.id)) }
                                Divider()
                                Button("Delete", role: .destructive) { deleteStack = stack }
                                    .disabled(stack.isDefault)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColor.textMuted)
                                    .frame(width: 36, height: 44)
                            }
                        }
                        if index < stacks.count - 1 { SettingsDivider(inset: 16) }
                    }
                }

                if let error { InlineMessage(text: error) }

                Button {
                    newStackName = ""
                    showCreateAlert = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New stack")
                    }
                    .font(AppFont.font(15, .semibold))
                    .foregroundStyle(AppColor.accentStrong)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColor.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stacks.add")
            }
            .padding(20)
        }
        .pageBackground()
        .navigationTitle("Stacks")
        .navigationBarTitleDisplayMode(.large)
        .alert("New stack", isPresented: $showCreateAlert) {
            TextField("Stack name", text: $newStackName)
            Button("Create") { createStack() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give the stack a short name.")
        }
        .alert("Rename stack", isPresented: Binding(
            get: { renameStack != nil },
            set: { if !$0 { renameStack = nil } }
        )) {
            TextField("Stack name", text: $renameText)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) { renameStack = nil }
        }
        .confirmationDialog(
            "Delete \(deleteStack?.name ?? "stack")?",
            isPresented: Binding(
                get: { deleteStack != nil },
                set: { if !$0 { deleteStack = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move words to My words") { performDelete(.moveCardsToDefault) }
            Button("Delete words too", role: .destructive) { performDelete(.deleteCards) }
            Button("Cancel", role: .cancel) { deleteStack = nil }
        } message: {
            Text("This permanently removes the stack. Choose what happens to its words.")
        }
    }

    private func stackRow(
        name: String,
        saved: Int,
        due: Int,
        isSelected: Bool,
        isDefault: Bool = false,
        tileID: UUID
    ) -> some View {
        HStack(spacing: 12) {
            InitialTile(word: name, id: tileID, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    if isDefault {
                        Text("DEFAULT")
                            .font(AppFont.font(8, .semibold))
                            .tracking(0.8)
                            .foregroundStyle(AppColor.accentInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.accentSoft, in: Capsule())
                    }
                }
                Text("\(saved) saved · \(due) due")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.accentStrong)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(saved) saved, \(due) due")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ id: UUID?) {
        app.preferences.preferences.selectedStackID = id
        app.router.popToRoot()
    }

    private func createStack() {
        switch app.library.createStack(named: newStackName) {
        case .success(let stack):
            app.preferences.preferences.selectedStackID = stack.id
            error = nil
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }

    private func performRename() {
        guard let stack = renameStack else { return }
        switch app.library.renameStack(stack, to: renameText) {
        case .success:
            renameStack = nil
            error = nil
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }

    private func performDelete(_ mode: StackDeletionMode) {
        guard let stack = deleteStack else { return }
        switch app.library.deleteStack(stack, mode: mode) {
        case .success:
            deleteStack = nil
            error = nil
            if app.router.path.last == .stackSettings(stack.id) {
                app.router.path.removeLast()
            }
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }
}

struct StackSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    let stackID: UUID
    var showsClose: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var showStepsEditor = false
    @State private var showRulesEditor = false
    @State private var error: String?

    private var stack: VocabularyStack? { app.library.stack(id: stackID) }

    private var dueCount: Int {
        guard let stack else { return 0 }
        let consumed = app.maintenance.consumedNewCardIDs(stackID: stack.id)
        return LibraryProjection.dueCount(
            stack: stack,
            consumed: consumed,
            globalRules: app.preferences.preferences.rules,
            now: app.maintenance.clock.now,
            calendar: app.maintenance.calendar
        )
    }

    var body: some View {
        Group {
            if let stack {
                content(stack)
            } else {
                EmptyStateView(title: "Stack unavailable", message: "This stack was deleted or moved.")
                    .pageBackground()
            }
        }
        .navigationTitle(LocalizedStringKey(showsClose ? "Session settings" : "Stack"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showStepsEditor) {
            if let stack {
                StepsEditorView(stack: stack)
                    .environment(app)
            }
        }
        .sheet(isPresented: $showRulesEditor) {
            if let stack {
                NavigationStack {
                    LearningRulesView(stackID: stack.id, showsClose: true)
                        .environment(app)
                }
            }
        }
        .onChange(of: stack?.cardsPerSession) { _, _ in persist(stack) }
        .onChange(of: stack?.newCardsPerDay) { _, _ in persist(stack) }
        .onChange(of: stack?.shuffleOrder) { _, _ in persist(stack) }
    }

    private func content(_ stack: VocabularyStack) -> some View {
        @Bindable var stack = stack
        return GeometryReader { proxy in
            let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero(stack, mode: mode)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Session")
                        GroupedSurface {
                            settingRow(
                                title: "Cards per session",
                                detail: "Distinct cards admitted to one session.",
                                value: $stack.cardsPerSession,
                                range: 1...100,
                                identifier: "stack.cardsPerSession"
                            )
                            SettingsDivider(inset: 16)
                            settingRow(
                                title: "New cards per day",
                                detail: "Shared across every session in this stack.",
                                value: $stack.newCardsPerDay,
                                range: 0...100,
                                identifier: "stack.newCardsPerDay"
                            )
                            SettingsDivider(inset: 16)
                            SettingsToggleRow(
                                title: "Shuffle order",
                                detail: "Randomize due and new groups for each new session.",
                                isOn: $stack.shuffleOrder,
                                accessibilityIdentifier: "stack.shuffle"
                            )
                            SettingsDivider(inset: 16)
                            directionRow(stack)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Learning")
                        GroupedSurface {
                            SettingsRow(
                                title: "Steps",
                                value: formattedSteps(stack.steps),
                                showsChevron: true
                            ) {
                                showStepsEditor = true
                            }
                            .accessibilityIdentifier("stack.steps")
                            SettingsDivider(inset: 16)
                            SettingsRow(
                                title: "Learning rules",
                                value: rulesSummary(stack),
                                detail: stack.customRules == nil ? "Using default learning rules." : "Custom rules for this stack.",
                                showsChevron: true
                            ) {
                                showRulesEditor = true
                            }
                            .accessibilityIdentifier("stack.rules")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Session help")
                        GroupedSurface {
                            Text("A session admits due Learning cards first, then New cards within the daily limit. Each card appears once, with up to three repeat presentations. Revealing an answer never changes progress; only Again or Good does. Leaving mid-session keeps every completed rating.")
                                .font(AppFont.body())
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(16)
                        }
                    }

                    if let error { InlineMessage(text: error) }

                    Text("Changes apply to the next session.")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: min(proxy.size.width, 820), alignment: .center)
                .padding(.horizontal, mode.inset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .pageBackground()
        }
    }

    private func hero(_ stack: VocabularyStack, mode: AppMetrics.LayoutMode) -> some View {
        let learned = stack.cards.filter { $0.learningState?.lifecycle == .learned }.count
        let total = stack.cards.count
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stack.name)
                    .font(AppFont.screenTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("\(total) saved · \(dueCount) due today")
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: 0)
                Button {
                    app.startReview(scopeID: stack.id)
                } label: {
                    Text("Review due cards")
                        .font(AppFont.font(13, .semibold))
                        .foregroundStyle(AppColor.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Capsule().fill(AppColor.accentStrong))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review \(dueCount) due cards in \(stack.name)")
            }
            Spacer(minLength: 0)
            ZStack {
                ProgressRing(
                    progress: LibraryQuery.relativeRatio(count: learned, total: total),
                    lineWidth: mode == .compact ? 8 : 10,
                    size: mode == .compact ? 72 : 140,
                    label: "\(learned) of \(total) learned"
                )
                VStack(spacing: 0) {
                    Text("\(dueCount)")
                        .font(AppFont.font(mode == .compact ? 20 : 30, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    Text("due")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .padding(18)
        .raisedSurface()
    }

    private func directionRow(_ stack: VocabularyStack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Card direction")
                .font(AppFont.fieldValue())
                .foregroundStyle(AppColor.textPrimary)
            Text("Choose which side appears first.")
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
            HStack(spacing: 4) {
                ForEach(CardPresentationOrder.allCases) { mode in
                    Button {
                        stack.presentationMode = mode
                        persist(stack)
                    } label: {
                        Text(LocalizedStringKey(mode.title))
                            .font(AppFont.font(12, .semibold))
                            .foregroundStyle(stack.presentationMode == mode ? AppColor.onAccent : AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(stack.presentationMode == mode ? AppColor.accentStrong : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(stack.presentationMode == mode ? .isSelected : [])
                    .accessibilityIdentifier(
                        mode == .backFirst ? "stack.translationFirst" : "stack.direction.\(mode.rawValue)"
                    )
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColor.divider, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func settingRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        identifier: String
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.fieldValue())
                    .foregroundStyle(AppColor.textPrimary)
                Text(LocalizedStringKey(detail))
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            StepperCapsule(label: title, value: value, range: range, accessibilityIdentifier: identifier)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }

    private func formattedSteps(_ steps: [TimeInterval]) -> String {
        steps.map { durationText($0) }.joined(separator: " · ")
    }

    private func durationText(_ interval: TimeInterval) -> String {
        if interval >= 86_400, interval.truncatingRemainder(dividingBy: 86_400) == 0 {
            let days = Int(interval / 86_400)
            return "\(days)d"
        }
        if interval >= 3_600, interval.truncatingRemainder(dividingBy: 3_600) == 0 {
            let hours = Int(interval / 3_600)
            return "\(hours)h"
        }
        let minutes = max(1, Int(interval / 60))
        return "\(minutes)m"
    }

    private func rulesSummary(_ stack: VocabularyStack) -> String {
        let rules = stack.effectiveRules(global: app.preferences.preferences.rules)
        let first = durationText(rules.stepInterval(at: 0))
        let last = durationText(rules.stepInterval(at: max(0, rules.steps.count - 1)))
        return "\(rules.correctThreshold) · \(first) → \(last)"
    }

    private func persist(_ stack: VocabularyStack?) {
        guard let stack else { return }
        if case .failure(let error) = app.library.saveStackSettings(stack) {
            self.error = error.localizedDescription
        } else {
            error = nil
        }
    }
}

// MARK: - Steps editor

struct StepsEditorView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    let stack: VocabularyStack

    enum Unit: String, CaseIterable, Identifiable {
        case minutes, hours, days, weeks
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var seconds: TimeInterval {
            switch self {
            case .minutes: 60
            case .hours: 3_600
            case .days: 86_400
            case .weeks: 604_800
            }
        }
    }

    struct StepDraft: Identifiable {
        let id = UUID()
        var value: Int
        var unit: Unit

        var seconds: TimeInterval { TimeInterval(value) * unit.seconds }
    }

    @State private var steps: [StepDraft] = []
    @State private var error: String?
    @State private var didLoad = false

    private var isValid: Bool {
        guard !steps.isEmpty else { return false }
        guard steps.allSatisfy({ $0.value > 0 }) else { return false }
        let seconds = steps.map(\.seconds)
        guard Set(seconds).count == seconds.count else { return false }
        return zip(seconds, seconds.dropFirst()).allSatisfy { $0 < $1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Short steps bring new and relearning cards back quickly. Each step must be positive, unique, and longer than the one before it.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)

                    GroupedSurface {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            HStack(spacing: 10) {
                                Text("Step \(index + 1)")
                                    .font(AppFont.font(13, .semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                                Spacer()
                                StepperCapsule(
                                    label: "Step \(index + 1)",
                                    value: Binding(
                                        get: { steps[index].value },
                                        set: { steps[index].value = $0 }
                                    ),
                                    range: 1...999
                                )
                                Picker("Unit", selection: Binding(
                                    get: { steps[index].unit },
                                    set: { steps[index].unit = $0 }
                                )) {
                                    ForEach(Unit.allCases) { unit in
                                        Text(LocalizedStringKey(unit.title)).tag(unit)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColor.accent)
                                .frame(minWidth: 84)
                                Button(role: .destructive) {
                                    steps.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(AppColor.danger)
                                        .frame(width: 40, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove step \(index + 1)")
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            if index < steps.count - 1 { SettingsDivider(inset: 16) }
                        }
                        SettingsDivider(inset: 16)
                        Button {
                            addStep()
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add step")
                            }
                            .font(AppFont.font(14, .semibold))
                            .foregroundStyle(AppColor.accentStrong)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    if !isValid, !steps.isEmpty {
                        InlineMessage(text: "Steps must be positive, unique, and increasing.")
                    }
                    if let error { InlineMessage(text: error) }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle("Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                steps = stack.steps.map { interval in
                    if interval >= 604_800, interval.truncatingRemainder(dividingBy: 604_800) == 0 {
                        return StepDraft(value: Int(interval / 604_800), unit: .weeks)
                    }
                    if interval >= 86_400, interval.truncatingRemainder(dividingBy: 86_400) == 0 {
                        return StepDraft(value: Int(interval / 86_400), unit: .days)
                    }
                    if interval >= 3_600, interval.truncatingRemainder(dividingBy: 3_600) == 0 {
                        return StepDraft(value: Int(interval / 3_600), unit: .hours)
                    }
                    return StepDraft(value: max(1, Int(interval / 60)), unit: .minutes)
                }
            }
        }
    }

    private func addStep() {
        let last = steps.last?.seconds ?? 60
        let next = last * 2
        if next >= 604_800, next.truncatingRemainder(dividingBy: 604_800) == 0 {
            steps.append(StepDraft(value: Int(next / 604_800), unit: .weeks))
        } else if next >= 86_400, next.truncatingRemainder(dividingBy: 86_400) == 0 {
            steps.append(StepDraft(value: Int(next / 86_400), unit: .days))
        } else if next >= 3_600, next.truncatingRemainder(dividingBy: 3_600) == 0 {
            steps.append(StepDraft(value: Int(next / 3_600), unit: .hours))
        } else {
            steps.append(StepDraft(value: max(1, Int(next / 60)), unit: .minutes))
        }
    }

    private func save() {
        let intervals = steps.map(\.seconds)
        stack.steps = intervals
        switch app.library.saveStackSettings(stack) {
        case .success:
            dismiss()
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }
}
