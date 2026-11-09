import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
protocol NotificationCenterAdapter: AnyObject {
    func requestAuthorization() async -> Bool
    func authorizationState() async -> ReminderAuthorization
    func add(_ request: ReminderRequest) async throws
    func pendingFeatureRequests() async -> [String]
    func deliveredFeatureRequests() async -> [String]
    func removePending(identifiers: [String]) async
    func removeDelivered(identifiers: [String]) async
}

@MainActor
final class UserNotificationCenterAdapter: NotificationCenterAdapter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationState() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    func add(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        if request.isTest {
            content.title = "Test reminder"
        } else {
            content.title = "Time to review"
        }
        content.body = "Your words are ready for another look."
        if request.soundEnabled {
            content.sound = .default
        }
        content.badge = nil
        var userInfo: [String: Any] = [:]
        if request.isTest {
            userInfo["route"] = "words"
            userInfo["test"] = true
        } else {
            userInfo["route"] = "review"
            if let scopeID = request.scopeID {
                userInfo["stack"] = scopeID.uuidString
            }
        }
        content.userInfo = userInfo

        let trigger: UNNotificationTrigger
        if request.isTest {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, request.fireDate.timeIntervalSinceNow),
                repeats: false
            )
        } else {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let notification = UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        try await center.add(notification)
    }

    func pendingFeatureRequests() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }
    }

    func deliveredFeatureRequests() async -> [String] {
        await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }
    }

    func removePending(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
@Observable
final class ReminderService {
    let preferences: PreferencesStore
    let maintenance: MaintenanceService
    let notifications: NotificationCenterAdapter
    let clock: DateProviding
    var calendar: Calendar

    private(set) var authorization: ReminderAuthorization = .notDetermined
    private(set) var nextScheduledAt: Date?
    private(set) var isReconciling = false
    var lastError: String?

    init(
        preferences: PreferencesStore,
        maintenance: MaintenanceService,
        notifications: NotificationCenterAdapter? = nil,
        clock: DateProviding = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.preferences = preferences
        self.maintenance = maintenance
        self.notifications = notifications ?? UserNotificationCenterAdapter()
        self.clock = clock
        self.calendar = calendar
    }

    var prefs: ReminderPreferences {
        get { preferences.preferences.reminders }
        set { preferences.preferences.reminders = newValue }
    }

    var isEnabled: Bool { prefs.enabled && authorization.allowsScheduling }

    func refreshAuthorization() async {
        let status = await notifications.authorizationState()
        authorization = status
        if prefs.enabled && !status.allowsScheduling {
            prefs.enabled = false
        }
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await notifications.requestAuthorization()
            let status = await notifications.authorizationState()
            authorization = status
            prefs.enabled = granted && status.allowsScheduling
        } else {
            prefs.enabled = false
        }
        await reconcile()
    }

    func refreshAndReconcile() async {
        await refreshAuthorization()
        await reconcile()
    }

    func reconcile() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let status = await notifications.authorizationState()
        authorization = status
        if prefs.enabled && !status.allowsScheduling {
            prefs.enabled = false
        }
        if let scopeID = prefs.stackID, !maintenance.stacks().contains(where: { $0.id == scopeID }) {
            prefs.stackID = nil
        }

        let desired: [ReminderRequest]
        if prefs.enabled, status.allowsScheduling {
            desired = ReminderScheduler.desiredRequests(
                preferences: prefs,
                authorization: status,
                work: workSnapshot(),
                now: clock.now,
                calendar: calendar
            )
        } else {
            desired = []
        }
        nextScheduledAt = ReminderScheduler.nextScheduledDate(in: desired)

        let pending = await notifications.pendingFeatureRequests()
        let desiredIDs = Set(desired.map(\.identifier))
        let stale = pending.filter { identifier in
            if identifier == ReminderRequest.testIdentifier {
                return !prefs.enabled
            }
            return !desiredIDs.contains(identifier)
        }
        await notifications.removePending(identifiers: stale)

        // Re-add desired requests so a changed time replaces the old fire date even when the ID is stable.
        let toReplace = pending.filter { desiredIDs.contains($0) }
        await notifications.removePending(identifiers: toReplace)
        for request in desired {
            do {
                try await notifications.add(request)
            } catch {
                lastError = "A reminder could not be scheduled: \(error.localizedDescription)"
            }
        }

        let delivered = await notifications.deliveredFeatureRequests()
        await notifications.removeDelivered(identifiers: delivered)
    }

    func sendTestReminder() async {
        guard prefs.enabled, authorization.allowsScheduling else { return }
        let request = ReminderRequest(
            identifier: ReminderRequest.testIdentifier,
            fireDate: clock.now.addingTimeInterval(5),
            scopeID: prefs.stackID,
            isTest: true,
            soundEnabled: prefs.soundEnabled
        )
        do {
            await notifications.removePending(identifiers: [ReminderRequest.testIdentifier])
            try await notifications.add(request)
        } catch {
            lastError = "The test reminder could not be scheduled: \(error.localizedDescription)"
        }
    }

    func nextScheduledText() -> String {
        let language = preferences.preferences.language
        guard prefs.enabled, authorization.allowsScheduling else {
            return L10n.string("No reminder is scheduled.", language: language)
        }
        guard let nextScheduledAt else {
            return L10n.string("All caught up. No review work is expected in the next seven days.", language: language)
        }
        return L10n.date(nextScheduledAt, language: language)
    }

    private func workSnapshot() -> ReminderWorkSnapshot {
        let now = clock.now
        let key = CalendarTools.dayKey(for: now, calendar: calendar)
        let records = maintenance.records()
        var recordsByStack: [UUID: DailyAdmissionRecord] = [:]
        for record in records where record.dayKey == key {
            recordsByStack[record.stackID] = record
        }
        var cardsByStack: [UUID: [VocabularyCard]] = [:]
        for card in maintenance.cardsForList() {
            guard let stackID = card.stack?.id else { continue }
            cardsByStack[stackID, default: []].append(card)
        }
        let stacks = maintenance.stacks().map { stack -> ReminderStackWork in
            let rules = stack.effectiveRules(global: preferences.preferences.rules)
            let consumed = recordsByStack[stack.id]?.cardIDs ?? []
            let cards = (cardsByStack[stack.id] ?? []).map { card -> ReminderCardWork in
                let state = card.learningState?.snapshot ?? .fresh
                return ReminderCardWork(
                    lifecycle: state.lifecycle,
                    repeatCount: state.repeatCount,
                    nextDueAt: state.nextDueAt,
                    learnedAnchor: state.learnedAnchor,
                    appliedMilestones: state.appliedMilestones
                )
            }
            return ReminderStackWork(
                id: stack.id,
                name: stack.name,
                newPerDay: stack.newCardsPerDay,
                consumedToday: consumed,
                rules: rules,
                cards: cards
            )
        }
        return ReminderWorkSnapshot(stacks: stacks)
    }
}

@MainActor
@Observable
final class NotificationInbox {
    static let shared = NotificationInbox()

    var pendingDestination: AppDestination?
    var activeReviewStackID: UUID?

    func receive(_ destination: AppDestination) {
        pendingDestination = destination
    }

    func consume() -> AppDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    func destination(from userInfo: [AnyHashable: Any]) -> AppDestination? {
        let route = userInfo["route"] as? String
        let stackID = (userInfo["stack"] as? String).flatMap(UUID.init(uuidString:))
        switch route {
        case "review":
            return .review(stackID: stackID)
        case "words":
            return .words(stackID: stackID)
        default:
            return nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let stackID = (notification.request.content.userInfo["stack"] as? String).flatMap(UUID.init(uuidString:))
        return await MainActor.run {
            if let active = NotificationInbox.shared.activeReviewStackID {
                if stackID == nil || stackID == active {
                    return []
                }
            }
            return [.banner, .sound]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        let stackID = (response.notification.request.content.userInfo["stack"] as? String)
            .flatMap(UUID.init(uuidString:))
        let destination: AppDestination?
        switch route {
        case "review": destination = .review(stackID: stackID)
        case "words": destination = .words(stackID: stackID)
        default: destination = nil
        }
        await MainActor.run {
            if let destination {
                NotificationInbox.shared.receive(destination)
            }
        }
    }
}
