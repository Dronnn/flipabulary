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
        VStack(alignment: .leading, spacing: 16) {
            GroupedSurface {
                Menu {
                    Button("All stacks") {
                        update {
                            $0.stackID = nil
                            $0.wordSetID = nil
                        }
                    }
                    ForEach(app.library.stacks()) { stack in
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

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Entries by size")
                GroupedSurface {
                    capacityRow("Small", 3)
                    SettingsDivider(inset: 16)
                    capacityRow("Medium", 6)
                    SettingsDivider(inset: 16)
                    capacityRow("Large", 10)
                    SettingsDivider(inset: 16)
                    capacityRow("Extra Large", 16)
                }
            }

            Text("Entry counts are fixed by the Home Screen size. Larger text may show fewer rows so labels stay legible.")
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private func capacityRow(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(AppFont.fieldValue())
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text("\(count) entries")
                .font(AppFont.font(14, .regular))
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) entries")
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
