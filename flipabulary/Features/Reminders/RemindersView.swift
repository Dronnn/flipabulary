import SwiftUI
import UIKit

struct RemindersView: View {
    @Environment(AppEnvironment.self) private var app

    @State private var isWorking = false
    @State private var testMessage: String?

    private var prefs: ReminderPreferences { app.preferences.preferences.reminders }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = prefs.hour
                components.minute = prefs.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = prefs
                updated.hour = components.hour ?? 20
                updated.minute = components.minute ?? 0
                update(updated)
            }
        )
    }

    private var weekdayOrder: [Int] { [2, 3, 4, 5, 6, 7, 1] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupedSurface {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: "Enable reminders",
                            detail: "A gentle local reminder on the days you choose.",
                            isOn: Binding(
                                get: { prefs.enabled },
                                set: { newValue in
                                    guard !isWorking else { return }
                                    isWorking = true
                                    Task {
                                        await app.reminders.setEnabled(newValue)
                                        isWorking = false
                                    }
                                }
                            ),
                            accessibilityIdentifier: "reminders.enabled"
                        )
                        SettingsDivider(inset: 16)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("System permission")
                                    .font(AppFont.fieldValue())
                                    .foregroundStyle(AppColor.textPrimary)
                                Text(LocalizedStringKey(app.reminders.authorization.title))
                                    .font(AppFont.caption())
                                    .foregroundStyle(app.reminders.authorization.allowsScheduling ? AppColor.success : AppColor.textSecondary)
                            }
                            Spacer()
                            if app.reminders.authorization == .denied {
                                Button("Open Settings") { openSystemSettings() }
                                    .font(AppFont.font(13, .semibold))
                                    .foregroundStyle(AppColor.accentStrong)
                                    .frame(minHeight: 44)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 56)
                    }
                }

                Group {
                    GroupedSurface {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Time")
                                    .font(AppFont.fieldValue())
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("Local time")
                                    .font(AppFont.caption())
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()
                            DatePicker("Reminder time", selection: timeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(AppColor.accent)
                                .accessibilityIdentifier("reminders.time")
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)

                        SettingsDivider(inset: 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Days")
                                .font(AppFont.fieldValue())
                                .foregroundStyle(AppColor.textPrimary)
                            HStack(spacing: 6) {
                                ForEach(weekdayOrder, id: \.self) { weekday in
                                    let selected = prefs.weekdays.contains(weekday)
                                    Button {
                                        toggleWeekday(weekday)
                                    } label: {
                                        Text(weekdayLabel(weekday))
                                            .font(AppFont.font(11, .semibold))
                                            .foregroundStyle(selected ? AppColor.onAccent : AppColor.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .background(
                                                Circle()
                                                    .fill(selected ? AppColor.accentStrong : AppColor.accentSoft)
                                                    .frame(width: 36, height: 36)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(fullWeekdayLabel(weekday))
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                        }
                        .padding(16)

                        SettingsDivider(inset: 16)

                        Menu {
                            Button("All stacks") { updateScope(nil) }
                            ForEach(app.library.stacks()) { stack in
                                Button(stack.name) { updateScope(stack.id) }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Review scope")
                                        .font(AppFont.fieldValue())
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text("Only remind me when this scope has work.")
                                        .font(AppFont.caption())
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Text(scopeName)
                                    .font(AppFont.font(14, .regular))
                                    .foregroundStyle(AppColor.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColor.textMuted)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("reminders.scope")

                        SettingsDivider(inset: 16)

                        SettingsToggleRow(
                            title: "Sound",
                            detail: "Play the default notification sound.",
                            isOn: Binding(
                                get: { prefs.soundEnabled },
                                set: { value in
                                    var updated = prefs
                                    updated.soundEnabled = value
                                    update(updated)
                                }
                            ),
                            accessibilityIdentifier: "reminders.sound"
                        )
                    }

                    GroupedSurface {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Next reminder")
                                    .font(AppFont.fieldValue())
                                    .foregroundStyle(AppColor.textPrimary)
                                Text(app.reminders.nextScheduledText())
                                    .font(AppFont.caption())
                                    .foregroundStyle(AppColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(16)
                        SettingsDivider(inset: 16)
                        Button {
                            Task {
                                await app.reminders.sendTestReminder()
                                testMessage = "Test reminder scheduled for 5 seconds from now."
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge")
                                Text("Send test reminder")
                                Spacer()
                            }
                            .font(AppFont.font(14, .semibold))
                            .foregroundStyle(AppColor.accentStrong)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!app.reminders.isEnabled)
                        .accessibilityIdentifier("reminders.test")
                        if let testMessage {
                            InlineMessage(text: testMessage, kind: .success)
                                .padding(16)
                        }
                    }
                }
                .disabled(!prefs.enabled)
                .opacity(prefs.enabled ? 1 : 0.62)

                Text("Reminders are local notifications. The notification says only that words are ready; it never includes a word, translation, or due count. Flipabulary asks for permission when you turn reminders on.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await app.reminders.refreshAuthorization()
        }
        .onChange(of: prefs.timeText) { _, _ in
            Task { await app.reminders.reconcile() }
        }
        .onChange(of: prefs.weekdays) { _, _ in
            Task { await app.reminders.reconcile() }
        }
        .onChange(of: prefs.stackID) { _, _ in
            Task { await app.reminders.reconcile() }
        }
        .onChange(of: prefs.soundEnabled) { _, _ in
            Task { await app.reminders.reconcile() }
        }
    }

    private var scopeName: String {
        guard let id = prefs.stackID else { return "All stacks" }
        return app.library.stack(id: id)?.name ?? "All stacks"
    }

    private func toggleWeekday(_ weekday: Int) {
        var updated = prefs
        if updated.weekdays.contains(weekday) {
            updated.weekdays.remove(weekday)
        } else {
            updated.weekdays.insert(weekday)
        }
        update(updated)
    }

    private func updateScope(_ id: UUID?) {
        var updated = prefs
        updated.stackID = id
        update(updated)
    }

    private func update(_ updated: ReminderPreferences) {
        app.preferences.preferences.reminders = updated
        Task { await app.reminders.reconcile() }
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = app.preferences.preferences.language?.locale ?? Locale.current
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return symbols[max(0, min(6, weekday - 1))]
    }

    private func fullWeekdayLabel(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = app.preferences.preferences.language?.locale ?? Locale.current
        let symbols = formatter.weekdaySymbols ?? []
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1]
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
