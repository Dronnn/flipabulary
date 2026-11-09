import SwiftUI
import SwiftData

struct LearningRulesView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stackID: UUID?
    var showsClose: Bool = false

    @State private var rules = LearningRules.default
    @State private var usesCustomRules = true
    @State private var didLoad = false
    @State private var error: String?
    @State private var showSupport = false

    private var stack: VocabularyStack? {
        guard let stackID else { return nil }
        return app.library.stack(id: stackID)
    }

    private var isStackScope: Bool { stackID != nil }

    var body: some View {
        GeometryReader { proxy in
            let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
            ScrollView {
                if mode == .compact || dynamicTypeSize.isAccessibilitySize {
                    compactContent
                } else {
                    expandedContent(mode: mode)
                }
            }
            .pageBackground()
            .navigationTitle(LocalizedStringKey(isStackScope ? "Stack rules" : "Learning rules"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .task { loadIfNeeded() }
            .fullScreenCover(isPresented: $showSupport) {
                SupportView(purchasing: app.purchasing)
                    .environment(app)
            }
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ownershipSection
            controls
            schedule
            explanation
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private func expandedContent(mode: AppMetrics.LayoutMode) -> some View {
        HStack(alignment: .top, spacing: mode.gap) {
            VStack(alignment: .leading, spacing: 16) {
                schedule
                explanation
            }
            .frame(width: mode == .duo ? 240 : 280)
            VStack(alignment: .leading, spacing: 16) {
                ownershipSection
                controls
            }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, mode.inset)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var ownershipSection: some View {
        if let stack {
            GroupedSurface {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(usesCustomRules ? "Custom rules" : "Use default rules"))
                                .font(AppFont.font(14, .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(LocalizedStringKey(usesCustomRules
                                 ? "This stack has its own learning rules."
                                 : "This stack follows the app's default rules."))
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        if usesCustomRules {
                            Button("Use defaults") { resetToDefaults() }
                                .font(AppFont.font(13, .semibold))
                                .foregroundStyle(AppColor.accentStrong)
                                .frame(minHeight: 44)
                        }
                    }
                    Text("\(stack.name) · \(stack.cards.count) words")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textMuted)
                }
                .padding(16)
            }
            .accessibilityIdentifier("rules.ownership")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Learning threshold")
            GroupedSurface {
                settingStepper(
                    title: "Correct in a row",
                    detail: "Good answers needed before a word is Learned.",
                    value: Binding(
                        get: { rules.correctThreshold },
                        set: { newValue in
                            var updated = rules
                            updated.correctThreshold = newValue
                            updated.returnBelow = min(updated.returnBelow, newValue)
                            update(updated)
                        }
                    ),
                    range: 1...20,
                    identifier: "rules.correctCount"
                )
                SettingsDivider(inset: 16)
                SettingsToggleRow(
                    title: "Reset streak on mistake",
                    detail: "Again returns the repeat count to zero.",
                    isOn: Binding(
                        get: { rules.resetOnMistake },
                        set: { newValue in
                            var updated = rules
                            updated.resetOnMistake = newValue
                            update(updated)
                        }
                    ),
                    accessibilityIdentifier: "rules.resetOnMistake"
                )
                SettingsDivider(inset: 16)
                SettingsToggleRow(
                    title: "Auto-decrease",
                    detail: "Remove a repeat at each decay milestone.",
                    isOn: Binding(
                        get: { rules.autoDecrease },
                        set: { newValue in
                            let wasOn = rules.autoDecrease
                            var updated = rules
                            updated.autoDecrease = newValue
                            update(updated)
                            if !wasOn && newValue {
                                app.maintenance.reanchorDecay(scopeID: stackID)
                            }
                        }
                    ),
                    accessibilityIdentifier: "rules.autoDecrease"
                )
                SettingsDivider(inset: 16)
                settingStepper(
                    title: "Return when below",
                    detail: "A Learned word returns to Learning below this repeat count.",
                    value: Binding(
                        get: { rules.returnBelow },
                        set: { newValue in
                            var updated = rules
                            updated.returnBelow = newValue
                            update(updated)
                        }
                    ),
                    range: 1...max(1, rules.correctThreshold),
                    identifier: "rules.returnBelow"
                )

            }
            if let error { InlineMessage(text: error) }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Schedule")
            GroupedSurface {
                ForEach(Array(LearningEngine.decayMilestones.enumerated()), id: \.element.index) { index, milestone in
                    HStack {
                        Text(LocalizedStringKey(milestoneLabel(milestone)))
                            .font(AppFont.fieldValue())
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text("−1")
                            .font(AppFont.font(14, .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    if index < LearningEngine.decayMilestones.count - 1 {
                        SettingsDivider(inset: 16)
                    }
                }
                if !rules.autoDecrease {
                    InlineMessage(text: "Auto-decrease is off. Earned repeats stay unchanged.", kind: .info)
                        .padding(16)
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "How it works")
            GroupedSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A word becomes Learned after \(rules.correctThreshold) correct answers in a row.")
                    Text("A Learned word returns to Learning when fewer than \(rules.returnBelow) repeats remain.")
                    Text("Good moves through the learning steps: \(formattedSteps(rules.steps)). A card becomes Learned at the threshold, then decay removes repeats at the schedule above.")
                    Text("Again schedules the first step immediately. Changing these rules never rewrites answer history, and an active session finishes with the rules it started with.")
                    Text("Decay milestones are cumulative from the latest learned or reinforced date. Month-end and daylight-saving changes use your local calendar.")
                }
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                Divider().overlay(AppColor.divider)
                SettingsRow(title: "Support Flipabulary", value: nil, showsChevron: true) {
                    showSupport = true
                }
                .accessibilityIdentifier("rules.support")
            }
        }
    }

    private func settingStepper(
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

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let stack {
            if let custom = stack.customRules {
                rules = custom
                usesCustomRules = true
            } else {
                rules = app.preferences.preferences.rules
                usesCustomRules = false
            }
        } else {
            rules = app.preferences.preferences.rules
            usesCustomRules = true
        }
    }

    private func update(_ newRules: LearningRules) {
        var normalized = newRules.normalized
        normalized.version = rules.version + 1
        rules = normalized
        error = nil

        if let stack {
            usesCustomRules = true
            stack.customRules = normalized
            if case .failure(let failure) = app.library.saveStackSettings(stack) {
                error = failure.localizedDescription
            }
            app.maintenance.refresh()
        } else {
            app.preferences.preferences.rules = normalized
            app.maintenance.refresh()
        }
    }

    private func resetToDefaults() {
        guard let stack else { return }
        stack.customRules = nil
        rules = app.preferences.preferences.rules
        usesCustomRules = false
        if case .failure(let failure) = app.library.saveStackSettings(stack) {
            error = failure.localizedDescription
        }
        app.maintenance.refresh()
    }

    private func milestoneLabel(_ milestone: DecayMilestone) -> String {
        if let days = milestone.days {
            switch days {
            case 7: return "1 week"
            case 14: return "2 weeks"
            default: return "\(days) \(days == 1 ? "day" : "days")"
            }
        }
        return "1 month"
    }

    private func formattedSteps(_ steps: [TimeInterval]) -> String {
        steps.map { interval in
            if interval >= 86_400 {
                return "\(Int(interval / 86_400))d"
            }
            if interval >= 3_600 {
                return "\(Int(interval / 3_600))h"
            }
            return "\(max(1, Int(interval / 60)))m"
        }.joined(separator: " → ")
    }
}
