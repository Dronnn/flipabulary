import SwiftUI
import SwiftData

struct WidgetSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var editingSet: WidgetWordSet?

    private var defaults: WidgetDefaults { app.preferences.preferences.widgetDefaults }

    private var snapshot: WidgetSnapshot {
        var prefs = app.preferences.preferences
        prefs.widgetDefaults = defaults
        return LibraryProjection.widgetSnapshot(
            stacks: app.maintenance.stacks(),
            cards: app.maintenance.cardsForList(),
            records: app.maintenance.records(),
            preferences: prefs,
            now: app.maintenance.clock.now,
            calendar: app.maintenance.calendar
        )
    }

    private var wordSets: [WidgetWordSet] {
        app.preferences.preferences.widgetWordSets
    }

    private var sourceName: String {
        if let set = app.preferences.preferences.widgetWordSet(id: defaults.wordSetID) { return set.name }
        guard let stackID = defaults.stackID else { return "All stacks" }
        return app.library.stack(id: stackID)?.name ?? "All stacks"
    }

    var body: some View {
        GeometryReader { proxy in
            let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Home Screen")
                        .sectionLabelStyle()
                    Text("Choose the default source for new List widgets. Each widget can still choose its own source, sort, translations, and word set in Edit Widget.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)

                    if mode == .duo && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 20) {
                            preview(mode: mode)
                                .frame(width: 280)
                            settingsColumn
                                .frame(width: 286)
                        }
                    } else if mode == .pad && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: mode.gap) {
                            preview(mode: mode)
                                .frame(width: 360)
                            settingsColumn
                        }
                    } else {
                        preview(mode: .compact)
                        settingsColumn
                    }
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, mode.inset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .pageBackground()
            .navigationTitle("List widget")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $editingSet) { set in
                NavigationStack {
                    WidgetWordSetEditorView(setID: set.id)
                        .environment(app)
                }
            }
        }
    }

    private var settingsColumn: some View {
        let stacks = app.library.stacks()
        return VStack(alignment: .leading, spacing: 16) {
            GroupedSurface {
                Menu {
                    Button("All stacks") {
                        update {
                            $0.stackID = nil
                            $0.wordSetID = nil
                        }
                    }
                    ForEach(stacks) { stack in
                        Button(stack.name) {
                            update {
                                $0.stackID = stack.id
                                $0.wordSetID = nil
                                if $0.sort == .manual { $0.sort = .dueFirst }
                            }
                        }
                    }
                    if !wordSets.isEmpty {
                        Section("Word sets") {
                            ForEach(wordSets) { set in
                                Button(set.name) {
                                    update {
                                        $0.stackID = nil
                                        $0.wordSetID = set.id
                                        $0.sort = .manual
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Source")
                            .font(AppFont.fieldValue())
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(sourceName)
                            .font(AppFont.font(14, .regular))
                            .foregroundStyle(AppColor.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("widget.source")
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Word sets")
                GroupedSurface {
                    ForEach(Array(wordSets.enumerated()), id: \.element.id) { index, set in
                        Button {
                            editingSet = set
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColor.accentStrong)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.name)
                                        .font(AppFont.fieldValue())
                                        .foregroundStyle(AppColor.textPrimary)
                                        .lineLimit(1)
                                    Text("\(set.cardIDs.count) words")
                                        .font(AppFont.font(12, .regular))
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColor.textMuted)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < wordSets.count - 1 { SettingsDivider(inset: 16) }
                    }
                    if !wordSets.isEmpty { SettingsDivider(inset: 16) }
                    Button {
                        createWordSet()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("New word set")
                        }
                        .font(AppFont.font(14, .semibold))
                        .foregroundStyle(AppColor.accentStrong)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("widget.newSet")
                }
                Text("Each List widget can choose its own set in Edit Widget. Sets can mix words from any stack.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                (Text("Small") + Text(verbatim: " 3  ·  ")
                    + Text("Medium") + Text(verbatim: " 6  ·  ")
                    + Text("Large") + Text(verbatim: " 10  ·  ")
                    + Text("Extra Large") + Text(verbatim: " 16"))
                    .font(AppFont.caption().weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                Text("Entry counts are fixed by the Home Screen size. Larger text may show fewer rows so labels stay legible.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            multipleWidgetsSection
        }
    }

    private var multipleWidgetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Multiple widgets")
                GroupedSurface {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("You can add more than one Word list widget to the Home Screen. Each widget can show a different word set, stack, sort, and translation setting, even on different Home Screen pages.")
                            .font(AppFont.body())
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            exampleWidget(number: 1, tint: AppColor.peach, rows: 3)
                            exampleWidget(number: 2, tint: AppColor.blue, rows: 3)
                        }
                        .accessibilityHidden(true)

                        Text("Each widget keeps its own settings.")
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textMuted)
                    }
                    .padding(16)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "How to add a widget")
                GroupedSurface {
                    instructionStep(1, "Touch and hold an empty area of the Home Screen.")
                    SettingsDivider(inset: 16)
                    instructionStep(2, "Tap Edit or Add Widget, search for Flipabulary, and choose Word list.")
                    SettingsDivider(inset: 16)
                    instructionStep(3, "Touch and hold the new widget, choose Edit Widget, then pick its Source, Sort, and Show translations.")
                    SettingsDivider(inset: 16)
                    instructionStep(4, "Repeat on any Home Screen page. Every widget can use a different word set.")
                }
                Text("Word sets are shared: editing a set updates every widget that uses it.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func exampleWidget(number: Int, tint: Color, rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                WidgetWordmark()
                Spacer()
                Text("\(rows) due")
                    .font(AppFont.font(8, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            (Text("Word set") + Text(verbatim: " \(number)"))
                .font(AppFont.font(13, .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
            Divider().overlay(AppColor.divider)
            VStack(spacing: 5) {
                ForEach(0..<rows, id: \.self) { index in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint.opacity(0.85))
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Capsule()
                                .fill(AppColor.textMuted.opacity(0.55))
                                .frame(width: 54 - CGFloat(index * 7), height: 3)
                            Capsule()
                                .fill(AppColor.divider)
                                .frame(width: 38, height: 2)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: "0/5")
                            .font(AppFont.font(7, .medium))
                            .foregroundStyle(AppColor.textMuted)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColor.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(AppFont.font(12, .bold))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(AppColor.accentStrong))
            Text(LocalizedStringKey(text))
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func preview(mode: AppMetrics.LayoutMode) -> some View {
        let rows = mode == .compact ? 4 : (mode == .duo ? 5 : 7)
        let projection = snapshot
        let stackID = defaults.wordSetID == nil ? projection.resolvedStackID(defaults.stackID) : nil
        let wordSetID = defaults.wordSetID.flatMap { projection.wordSet(id: $0)?.id }
        let cards = Array(projection.projectedCards(stackID: stackID, wordSetID: wordSetID, sort: defaults.sort).prefix(rows))
        let summary = projection.summary(stackID: stackID, wordSetID: wordSetID)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Preview")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    WidgetWordmark()
                    Spacer()
                    Text("\(summary.due) due")
                        .font(AppFont.font(10, .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Text(sourceName)
                    .font(AppFont.font(18, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Divider().overlay(AppColor.divider)
                if cards.isEmpty {
                    Text("No words to show yet.")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(spacing: 8) {
                        ForEach(cards) { card in
                            WidgetListRow(card: card, showTranslation: defaults.showTranslations)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Text(sourceName)
                    Spacer()
                    Text("\(summary.saved) words")
                }
                .font(AppFont.font(9, .medium))
                .foregroundStyle(AppColor.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            .raisedSurface(radius: 22)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("widget.preview")
        }
    }

    private func createWordSet() {
        var preferences = app.preferences.preferences
        let set = WidgetWordSet(name: "Word set \(preferences.widgetWordSets.count + 1)")
        preferences.widgetWordSets.append(set)
        app.preferences.preferences = preferences
        app.maintenance.publishSnapshot()
        editingSet = set
    }

    private func update(_ change: (inout WidgetDefaults) -> Void) {
        var defaults = app.preferences.preferences.widgetDefaults
        change(&defaults)
        app.preferences.preferences.widgetDefaults = defaults
        app.maintenance.publishSnapshot()
    }
}
