import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var selectedStackName: String {
        app.library.selectedStack()?.name ?? "My words"
    }

    private var selectedLanguage: AppLanguage {
        app.preferences.preferences.language ?? .system
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    app.preferences.preferences.language = language
                    app.haptics.selection()
                    app.maintenance.publishSnapshot()
                } label: {
                    if language == selectedLanguage {
                        Label {
                            languageMenuLabel(language)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        languageMenuLabel(language)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language")
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Switch languages without restarting the app.")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 8)
                if selectedLanguage == .system {
                    Text("System")
                        .font(AppFont.font(14, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    Text(verbatim: selectedLanguage.nativeName)
                        .font(AppFont.font(14, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("settings.language")
    }

    @ViewBuilder
    private func languageMenuLabel(_ language: AppLanguage) -> some View {
        if language == .system {
            Text("System")
        } else {
            Text(verbatim: language.nativeName)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Appearance")
                    GroupedSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            AppearanceSelector(
                                selection: Binding(
                                    get: { app.preferences.preferences.appearance },
                                    set: { newValue in
                                        if app.preferences.preferences.appearance != newValue {
                                            app.haptics.selection()
                                        }
                                        app.preferences.preferences.appearance = newValue
                                    }
                                )
                            )
                            Text("Choose Light, Dark, or follow the system setting.")
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .padding(16)
                        SettingsDivider(inset: 16)
                        languageMenu
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Feedback")
                    GroupedSurface {
                        SettingsToggleRow(
                            title: "Haptics",
                            detail: "Vibrate for swipes, ratings, and important actions.",
                            isOn: Binding(
                                get: { app.preferences.preferences.hapticsEnabled },
                                set: { newValue in
                                    let wasEnabled = app.preferences.preferences.hapticsEnabled
                                    app.preferences.preferences.hapticsEnabled = newValue
                                    if newValue && !wasEnabled {
                                        app.haptics.selection()
                                    }
                                }
                            ),
                            accessibilityIdentifier: "settings.haptics"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Learning")
                    GroupedSurface {
                        SettingsRow(title: "Learning rules", detail: "Learning intervals and long-term reviews.") {
                            app.router.push(.learningRules)
                        }
                        .accessibilityIdentifier("settings.rules")
                        SettingsDivider(inset: 16)
                        SettingsRow(title: "Stack settings", value: selectedStackName) {
                            if let stack = app.library.selectedStack() {
                                app.router.push(.stackSettings(stack.id))
                            } else if let stack = app.library.defaultStack() {
                                app.router.push(.stackSettings(stack.id))
                            }
                        }
                        .accessibilityIdentifier("settings.stack")
                        SettingsDivider(inset: 16)
                        SettingsRow(title: "Statistics", detail: "Time, reviews, accuracy, and progress by day and stack.") {
                            app.router.push(.statistics(nil))
                        }
                        .accessibilityIdentifier("settings.statistics")
                        SettingsDivider(inset: 16)
                        SettingsRow(title: "Widgets", detail: "Create sets and show a different one in each widget.") {
                            app.router.push(.widgets)
                        }
                        .accessibilityIdentifier("settings.widgets")
                        SettingsDivider(inset: 16)
                        SettingsRow(title: "Import & Export", detail: "Bring in decks or export your words.") {
                            app.router.push(.importExport)
                        }
                        .accessibilityIdentifier("settings.importExport")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Reminders")
                    GroupedSurface {
                        SettingsRow(
                            title: "Reminders",
                            value: app.localized(app.reminders.isEnabled ? "On" : "Off"),
                            detail: "Local notifications that respect your review workload."
                        ) {
                            app.router.push(.reminders)
                        }
                        .accessibilityIdentifier("settings.reminders")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Help")
                    GroupedSurface {
                        SettingsRow(
                            title: "Show onboarding again",
                            detail: "Replay the welcome, word sets, learning, and widget setup."
                        ) {
                            app.onboarding.presentAgain()
                        }
                        .accessibilityIdentifier("settings.onboarding")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Support")
                    GroupedSurface {
                        SettingsRow(
                            title: "Support Flipabulary",
                            detail: "Voluntary tips keep learning free. No features are unlocked."
                        ) {
                            app.router.supportVisible = true
                        }
                        .accessibilityIdentifier("settings.support")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "About")
                    GroupedSurface {
                        SettingsRow(title: "Flipabulary", value: versionText, showsChevron: false)
                        SettingsDivider(inset: 16)
                        SettingsRow(title: "Made for learning offline", detail: "Your words stay on this device.", showsChevron: false)
                    }
                    Text("Flipabulary works offline. Widgets and reminders use the data already on this device.")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle(app.localized("Settings"))
        .navigationBarTitleDisplayMode(.large)
    }
}
