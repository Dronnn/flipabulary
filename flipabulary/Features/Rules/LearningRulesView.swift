import SwiftUI

struct LearningRulesView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    let stackID: UUID?
    var showsClose: Bool = false
    @State private var showSupport = false

    private var rules: LearningRules {
        app.library.stack(id: stackID)?.effectiveRules(global: app.preferences.preferences.rules)
            ?? app.preferences.preferences.rules
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Learning steps")
                GroupedSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(rules.steps.map(duration).joined(separator: " · "))
                            .font(AppFont.fieldValue())
                        Text("Complete every learning interval before starting long-term reviews. Change learning steps in stack settings.")
                    }
                    .padding(16)
                }
                SectionHeader(title: "Long-term reviews")
                GroupedSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1d · 3d · 7d · 14d · 1 month")
                            .font(AppFont.fieldValue())
                        Text("Each interval starts after the previous correct answer. When a long-term review becomes due, the repeat count decreases by one, once.")
                        Text("Good advances to the next interval. Again at any stage restarts learning from the first interval.")
                        Text("Overdue words stay due until answered. Early practice does not skip an interval. A correct final monthly review completes learning.")
                        Text("Editing the repeat count changes only the counter, not the learning stage.")
                    }
                    .padding(16)
                }
                .accessibilityIdentifier("rules.sequence")
                GroupedSurface {
                    SettingsRow(title: "Support Flipabulary", showsChevron: true) { showSupport = true }
                }
            }
            .font(AppFont.body())
            .foregroundStyle(AppColor.textSecondary)
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .fullScreenCover(isPresented: $showSupport) {
            SupportView(purchasing: app.purchasing).environment(app)
        }
        .navigationTitle("Learning rules")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        if seconds >= 86_400 { return "\(Int(seconds / 86_400))d" }
        if seconds >= 3_600 { return "\(Int(seconds / 3_600))h" }
        return "\(max(1, Int(seconds / 60)))m"
    }
}
