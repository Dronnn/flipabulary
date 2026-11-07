import Foundation
import SwiftData
import XCTest
@testable import flipabulary

func testCalendar(timeZone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

func testDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

@MainActor
final class FakeNotificationAdapter: NotificationCenterAdapter {
    var status: ReminderAuthorization = .authorized
    var grantsAuthorization = true
    var requestAuthorizationCallCount = 0
    var pending: [String: ReminderRequest] = [:]
    var delivered: Set<String> = []
    var added: [ReminderRequest] = []

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return grantsAuthorization
    }

    func authorizationState() async -> ReminderAuthorization { status }

    func add(_ request: ReminderRequest) async throws {
        pending[request.identifier] = request
        added.append(request)
    }

    func pendingFeatureRequests() async -> [String] {
        Array(pending.keys).filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }
    }

    func deliveredFeatureRequests() async -> [String] { Array(delivered) }

    func removePending(identifiers: [String]) async {
        for identifier in identifiers { pending.removeValue(forKey: identifier) }
    }

    func removeDelivered(identifiers: [String]) async {
        for identifier in identifiers { delivered.remove(identifier) }
    }
}

@MainActor
final class FakeSupportPurchasing: SupportPurchasing {
    var products: [SupportProduct] = []
    var purchaseOutcome: SupportPurchaseOutcome = .verified
    var restoreOutcome: SupportRestoreOutcome = .nothingToRestore
    var loadError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var purchaseCalls: [String] = []

    func loadProducts() async throws -> [SupportProduct] {
        if let loadError { throw loadError }
        return products
    }

    func purchase(productID: String) async throws -> SupportPurchaseOutcome {
        purchaseCalls.append(productID)
        if let purchaseError { throw purchaseError }
        return purchaseOutcome
    }

    func restore() async throws -> SupportRestoreOutcome {
        if let restoreError { throw restoreError }
        return restoreOutcome
    }
}

@MainActor
final class TestHarness {
    let container: ModelContainer
    let context: ModelContext
    let preferences: PreferencesStore
    let clock: MutableClock
    var calendar: Calendar
    let snapshotStore: WidgetSnapshotStore
    let maintenance: MaintenanceService
    let library: LibraryService
    let review: ReviewService
    let notifications: FakeNotificationAdapter
    let reminders: ReminderService

    private let defaults: UserDefaults
    private let suiteName: String
    private let tempDirectory: URL

    init(
        now: Date = testDate("2026-11-07T10:00:00Z"),
        calendar: Calendar = testCalendar()
    ) throws {
        self.calendar = calendar
        clock = MutableClock(now: now)
        suiteName = "flipabulary.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let configuration = ModelConfiguration(schema: FlipabularySchema.schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: FlipabularySchema.schema, configurations: [configuration])
        context = container.mainContext

        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("flipabulary-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        snapshotStore = WidgetSnapshotStore(
            fileURL: tempDirectory.appendingPathComponent("widget-snapshot.json"),
            defaultsSuiteName: suiteName
        )

        preferences = PreferencesStore(defaults: defaults, reset: true)
        maintenance = MaintenanceService(
            modelContext: context,
            preferences: preferences,
            clock: clock,
            calendar: calendar,
            snapshotStore: snapshotStore,
            widgetReloader: NoopWidgetReloader()
        )
        library = LibraryService(
            modelContext: context,
            preferences: preferences,
            maintenance: maintenance,
            clock: clock
        )
        review = ReviewService(
            modelContext: context,
            preferences: preferences,
            library: library,
            maintenance: maintenance,
            clock: clock,
            calendar: calendar,
            seedProvider: { 7 }
        )
        notifications = FakeNotificationAdapter()
        reminders = ReminderService(
            preferences: preferences,
            maintenance: maintenance,
            notifications: notifications,
            clock: clock,
            calendar: calendar
        )
    }

    func prefer(_ stack: VocabularyStack) {
        preferences.preferences.selectedStackID = stack.id
        preferences.preferences.widgetDefaults.stackID = stack.id
    }

    @discardableResult
    func makeStack(
        name: String = "My words",
        isDefault: Bool = true,
        cardsPerSession: Int = 20,
        newCardsPerDay: Int = 10,
        shuffle: Bool = false,
        translationFirst: Bool = false,
        steps: [TimeInterval] = LearningRules.defaultSteps
    ) -> VocabularyStack {
        let stack = VocabularyStack(
            name: name,
            isDefault: isDefault,
            createdAt: clock.now,
            cardsPerSession: cardsPerSession,
            newCardsPerDay: newCardsPerDay,
            shuffleOrder: shuffle,
            translationFirst: translationFirst,
            steps: steps
        )
        context.insert(stack)
        return stack
    }

    @discardableResult
    func makeCard(
        word: String,
        translation: String = "перевод",
        stack: VocabularyStack,
        lifecycle: CardLifecycle = .new,
        repeatCount: Int = 0,
        nextDueAt: Date? = nil,
        createdAt: Date? = nil,
        tags: [String] = []
    ) -> VocabularyCard {
        let tagModels = tags.map { name in
            let tag = VocabularyTag(name: name, createdAt: clock.now)
            context.insert(tag)
            return tag
        }
        let card = VocabularyCard(
            word: word,
            translation: translation,
            stack: stack,
            tags: tagModels,
            createdAt: createdAt ?? clock.now
        )
        context.insert(card)
        if let state = card.learningState {
            state.repeatCount = repeatCount
            state.lifecycle = lifecycle
            state.nextDueAt = nextDueAt
            state.learnedAnchor = lifecycle == .learned ? (nextDueAt.map { $0.addingTimeInterval(-86_400) } ?? clock.now) : nil
            state.lastGradedAt = lifecycle == .new ? nil : clock.now
        }
        return card
    }

    func addEvent(
        to card: VocabularyCard,
        grade: ReviewGrade,
        at date: Date,
        sessionID: UUID = UUID()
    ) {
        let event = ReviewEvent(
            presentationID: UUID(),
            sessionID: sessionID,
            cardID: card.id,
            grade: grade,
            timestamp: date,
            beforeRepeatCount: max(0, card.learningState?.repeatCount ?? 0),
            afterRepeatCount: card.learningState?.repeatCount ?? 0,
            beforeLifecycle: .learning,
            afterLifecycle: .learning,
            rulesVersion: 1,
            card: card
        )
        context.insert(event)
    }

    func save() throws {
        try context.save()
    }

    func finish() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}
