import SwiftUI
import SwiftData
import UIKit

@main
struct FlipabularyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var environment: AppEnvironment?
    @State private var failureMessage: String?

    init() {
        if let bootstrap = PersistenceContainer.make() {
            _environment = State(initialValue: AppEnvironment(bootstrap: bootstrap))
        } else {
            _failureMessage = State(
                initialValue: "Flipabulary could not open its local library. Restart the app after freeing some storage."
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootView()
                    .environment(environment)
                    .modelContainer(environment.container)
                    .environment(\.locale, environment.preferences.preferences.language?.locale ?? Locale.current)
                    .preferredColorScheme(environment.preferences.preferences.appearance.colorScheme)
            } else {
                StorageFailureView(message: failureMessage ?? "Storage is unavailable.")
            }
        }
    }
}

struct StorageFailureView: View {
    let message: String

    var body: some View {
        ZStack {
            AppColor.page.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(AppColor.accentStrong)
                Text("Library unavailable")
                    .font(AppFont.screenTitle())
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppFont.body())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(32)
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var router = app.router
        NavigationStack(path: $router.path) {
            WordsView()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .tint(AppColor.accent)
        .preferredColorScheme(app.preferences.preferences.appearance.colorScheme)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = app.storageError {
                StorageBanner(message: error)
            }
        }
        .fullScreenCover(item: $router.editorTarget) { target in
            CardEditorView(target: target)
                .environment(app)
        }
        .fullScreenCover(isPresented: $router.supportVisible) {
            SupportView(purchasing: app.purchasing)
                .environment(app)
        }
        .sheet(item: $router.scopePicker) { picker in
            ReviewScopePickerView(picker: picker)
                .environment(app)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $router.reviewLaunch) { launch in
            ReviewView(sessionID: launch.id) {
                router.reviewLaunch = nil
            }
            .environment(app)
        }
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                ToastView(message: toast.text)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: router.toast?.id)
        .onOpenURL { url in
            Task { await app.handle(url: url) }
        }
        .task {
            await app.bootstrap()
            try? await Task.sleep(for: .milliseconds(450))
            if let destination = app.notificationInbox.consume() {
                await app.handle(destination: destination)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await app.appDidBecomeActive() }
            case .background:
                app.appDidEnterBackground()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await app.appDidBecomeActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await app.appDidBecomeActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await app.appDidBecomeActive() }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .stacks:
            StacksView()
        case .stackSettings(let id):
            StackSettingsView(stackID: id)
        case .stackRules(let id):
            LearningRulesView(stackID: id)
        case .learningRules:
            LearningRulesView(stackID: nil)
        case .settings:
            SettingsView()
        case .widgets:
            WidgetSettingsView()
        case .reminders:
            RemindersView()
        }
    }
}

struct StorageBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.accentStrong)
            Text(message)
                .font(AppFont.font(12, .medium))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.accentSoft)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColor.divider).frame(height: 1)
        }
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(LocalizedStringKey(message))
            .font(AppFont.font(14, .medium))
            .foregroundStyle(AppColor.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(AppColor.textPrimary.opacity(0.94))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            )
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isStaticText)
    }
}
