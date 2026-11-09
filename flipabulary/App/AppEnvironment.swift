import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let modelContext: ModelContext
    let preferences: PreferencesStore
    let haptics: HapticsService
    let maintenance: MaintenanceService
    let library: LibraryService
    let review: ReviewService
    let reminders: ReminderService
    let purchasing: SupportPurchasing
    let router: AppRouter
    let notificationInbox: NotificationInbox
    let onboarding: OnboardingStore
    let storageError: String?

    private(set) var didBootstrap = false
    @ObservationIgnored private let usageTracker = AppUsageTracker()

    init(bootstrap: PersistenceBootstrap) {
        container = bootstrap.container
        modelContext = container.mainContext
        storageError = bootstrap.storageError

        #if DEBUG
        let resetPreferences = ProcessInfo.processInfo.arguments.contains("-UITestResetPreferences")
        #else
        let resetPreferences = false
        #endif
        preferences = PreferencesStore(reset: resetPreferences)
        haptics = HapticsService(preferences: preferences)
        maintenance = MaintenanceService(modelContext: modelContext, preferences: preferences)
        library = LibraryService(modelContext: modelContext, preferences: preferences, maintenance: maintenance)
        review = ReviewService(
            modelContext: modelContext,
            preferences: preferences,
            library: library,
            maintenance: maintenance
        )
        reminders = ReminderService(preferences: preferences, maintenance: maintenance)
        #if DEBUG
        purchasing = ProcessInfo.processInfo.arguments.contains("-DebugSupportPreview")
            ? PreviewSupportService()
            : StoreKitSupportService()
        #else
        purchasing = StoreKitSupportService()
        #endif
        router = AppRouter()
        notificationInbox = .shared
        onboarding = OnboardingStore()

        let seed = SeedService.prepare(context: modelContext, preferences: preferences)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DebugDark") {
            preferences.preferences.appearance = .dark
        }
        #endif
        if let seedError = seed.error {
            maintenance.lastError = seedError
        }

        maintenance.onSnapshotPublished = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.reminders.reconcile()
            }
        }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if UIApplication.shared.applicationState == .active {
            startAppUsage()
        }
        maintenance.refresh()
        await reminders.refreshAndReconcile()
        let stackIDs = Set(maintenance.stacks().map(\.id))
        preferences.reconcile(validStackIDs: stackIDs)
        await review.repairIfNeeded()
        #if DEBUG
        try? await Task.sleep(for: .milliseconds(1_200))
        applyDebugRouteIfRequested()
        #endif
    }

    #if DEBUG
    private func applyDebugRouteIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-DebugRoute"), arguments.indices.contains(index + 1) else { return }
        let route = arguments[index + 1]
        switch route {
        case "settings":
            router.push(.settings)
        case "rules":
            router.push(.learningRules)
        case "widgets":
            router.push(.widgets)
        case "reminders":
            router.push(.reminders)
        case "stacks":
            router.push(.stacks)
        case "stackSettings":
            if let stack = library.selectedStack() ?? library.defaultStack() {
                router.push(.stackSettings(stack.id))
            }
        case "editor":
            router.presentEditor(.new(stackID: selectedScopeID() ?? library.defaultStack()?.id))
        case "editorEdit":
            if let card = library.cards().first {
                router.presentEditor(.edit(card.id))
            }
        case "support":
            router.supportVisible = true
        case "review":
            startReview(scopeID: selectedScopeID())
        default:
            break
        }
    }
    #endif

    func appDidBecomeActive() async {
        startAppUsage()
        maintenance.refresh()
        if let launch = router.reviewLaunch,
           let session = review.session(id: launch.id),
           session.status == .active {
            review.resume(session)
        }
        await reminders.refreshAndReconcile()
        if let destination = notificationInbox.consume() {
            await handle(destination: destination)
        }
    }

    func appDidBecomeInactive() {
        stopAppUsage()
        if let session = review.latestActiveSession() {
            review.pause(session)
        }
    }

    func appDidEnterBackground() {
        appDidBecomeInactive()
    }

    func handleTimeChange() async {
        maintenance.refresh()
        await reminders.refreshAndReconcile()
    }

    func startAppUsage() {
        usageTracker.start()
    }

    func stopAppUsage() {
        guard let interval = usageTracker.stop() else { return }
        maintenance.addAppUsage(from: interval.start, to: interval.end)
    }

    func currentAppUsageSeconds(now: Date = Date()) -> Double {
        usageTracker.liveSeconds(now: now)
    }

    func currentAppUsageInterval(now: Date = Date()) -> AppUsageInterval? {
        usageTracker.liveInterval(now: now)
    }

    func handle(url: URL) async {
        guard let destination = AppDestination.parse(url) else { return }
        await handle(destination: destination)
    }

    func handle(destination: AppDestination) async {
        switch destination {
        case .settings:
            router.popToRoot()
            router.push(.settings)
        case .widgets:
            router.popToRoot()
            router.push(.widgets)
        case .reminders:
            router.popToRoot()
            router.push(.reminders)
        case .words(let stackID):
            router.reviewLaunch = nil
            router.popToRoot()
            if let stackID {
                if let stack = library.stack(id: stackID) {
                    preferences.preferences.selectedStackID = stack.id
                } else {
                    preferences.preferences.selectedStackID = nil
                    router.showToast("That stack is no longer available. Showing all stacks.")
                }
            }
        case .card(let id):
            guard let card = library.card(id: id), let stack = card.stack else {
                router.popToRoot()
                router.showToast("That word is no longer in your library.")
                return
            }
            router.popToRoot()
            preferences.preferences.selectedStackID = stack.id
            router.presentEditor(.edit(card.id))
        case .review(let stackID):
            if router.reviewLaunch != nil { return }
            var effectiveScopeID = stackID
            if let stackID {
                if let stack = library.stack(id: stackID) {
                    preferences.preferences.selectedStackID = stack.id
                } else {
                    router.showToast("That stack is no longer available. Showing all stacks.")
                    preferences.preferences.selectedStackID = nil
                    effectiveScopeID = nil
                }
            }
            startReview(scopeID: effectiveScopeID)
        }
    }

    func startReview(scopeID: UUID?, singleCardID: UUID? = nil) {
        switch review.requestReview(scopeID: scopeID, singleCardID: singleCardID) {
        case .started(let id), .existing(let id):
            router.reviewLaunch = ReviewLaunch(id: id)
        case .needsScope(let stacks):
            router.scopePicker = ScopePickerState(stacks: stacks)
        case .empty(let nextDueAt):
            router.popToRoot()
            if let nextDueAt {
                router.showToast("All caught up. Next review \(nextDueAt.formatted(date: .abbreviated, time: .shortened)).")
            } else {
                router.showToast("All caught up. Add a word to keep going.")
            }
        case .failure(let message):
            router.showToast(message)
        }
    }

    func selectedScopeID() -> UUID? {
        let selected = preferences.preferences.selectedStackID
        if let selected, library.stack(id: selected) != nil { return selected }
        return nil
    }

    func localized(_ key: String) -> String {
        L10n.string(key, language: preferences.preferences.language)
    }

    func createOrEditReviewCard() {
        router.presentEditor(.new(stackID: selectedScopeID() ?? library.defaultStack()?.id))
    }
}

extension ReviewService {
    func repairIfNeeded() async {
        guard let session = latestActiveSession() else { return }
        repair(session)
    }
}
