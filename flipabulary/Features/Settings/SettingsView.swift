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
                                    set: { app.preferences.preferences.appearance = $0 }
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
                    SectionHeader(title: "Learning")
                    GroupedSurface {
                        SettingsRow(title: "Learning rules", detail: "Threshold, reset, and decay.") {
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
                        SettingsRow(title: "Widgets", detail: "Choose list content and preview widgets.") {
                            app.router.push(.widgets)
                        }
                        .accessibilityIdentifier("settings.widgets")
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}
