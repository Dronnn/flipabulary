import SwiftUI
import SwiftData

struct WidgetSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var scopeName: String {
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
                    Text("These defaults shape new List widgets. Existing widgets can keep their own stack, sort, and translation choices.")
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
        }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupedSurface {
                Menu {
                    Button("All stacks") {
                        update { $0.stackID = nil }
                    }
                    ForEach(app.library.stacks()) { stack in
                        Button(stack.name) {
                            update { $0.stackID = stack.id }
                        }
                    }
                } label: {
                    HStack {
                        Text("Stack")
                            .font(AppFont.fieldValue())
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(scopeName)
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
                .accessibilityIdentifier("widget.stack")
                SettingsDivider(inset: 16)
                Menu {
                    ForEach(WidgetSort.allCases) { sort in
                        Button {
                            update { $0.sort = sort }
                        } label: {
                            Text(LocalizedStringKey(sort.title))
                        }
                    }
                } label: {
                    HStack {
                        Text("Sort")
                            .font(AppFont.fieldValue())
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(LocalizedStringKey(defaults.sort.title))
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
                .accessibilityIdentifier("widget.sort")
                SettingsDivider(inset: 16)
                SettingsToggleRow(
                    title: "Show translations",
                    detail: "Show the translation under each word.",
                    isOn: Binding(
                        get: { defaults.showTranslations },
                        set: { value in update { $0.showTranslations = value } }
                    ),
                    accessibilityIdentifier: "widget.translations"
                )
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
        let stackID = projection.resolvedStackID(defaults.stackID)
        let cards = Array(projection.projectedCards(stackID: stackID, sort: defaults.sort).prefix(rows))
        let summary = projection.summary(stackID: stackID)
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
                Text(scopeName)
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
                    Text(scopeName)
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

    private func update(_ change: (inout WidgetDefaults) -> Void) {
        var defaults = app.preferences.preferences.widgetDefaults
        change(&defaults)
        app.preferences.preferences.widgetDefaults = defaults
        app.maintenance.publishSnapshot()
    }
}
