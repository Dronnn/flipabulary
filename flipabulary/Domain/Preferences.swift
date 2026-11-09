import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case german = "de"
    case spanish = "es"
    case portugueseBrazil = "pt-BR"
    case french = "fr"
    case russian = "ru"
    case polish = "pl"
    case ukrainian = "uk"
    case chineseSimplified = "zh-Hans"
    case korean = "ko"
    case japanese = "ja"
    case vietnamese = "vi"
    case italian = "it"
    case dutch = "nl"
    case turkish = "tr"
    case indonesian = "id"

    var id: String { rawValue }

    var isSystem: Bool { self == .system }

    var locale: Locale {
        if self == .system {
            return Locale.current
        }
        return Locale(identifier: rawValue)
    }

    var nativeName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .portugueseBrazil: "Português (Brasil)"
        case .french: "Français"
        case .russian: "Русский"
        case .polish: "Polski"
        case .ukrainian: "Українська"
        case .chineseSimplified: "简体中文"
        case .korean: "한국어"
        case .japanese: "日本語"
        case .vietnamese: "Tiếng Việt"
        case .italian: "Italiano"
        case .dutch: "Nederlands"
        case .turkish: "Türkçe"
        case .indonesian: "Bahasa Indonesia"
        }
    }
}

struct WidgetWordSet: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var cardIDs: [UUID]

    init(id: UUID = UUID(), name: String, cardIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.cardIDs = cardIDs
    }
}

struct WidgetDefaults: Codable, Equatable, Sendable {
    var stackID: UUID?
    var wordSetID: UUID?
    var sort: WidgetSort
    var showTranslations: Bool

    static let `default` = WidgetDefaults(stackID: nil, wordSetID: nil, sort: .dueFirst, showTranslations: false)
}

struct ReminderTime: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int

    init(id: UUID = UUID(), hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }

    var timeText: String {
        let components = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct ReminderPreferences: Codable, Equatable, Sendable {
    static let legacyTimeID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!

    var enabled: Bool
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>
    var stackID: UUID?
    var soundEnabled: Bool
    var times: [ReminderTime]? = nil

    static let `default` = ReminderPreferences(
        enabled: false,
        hour: 20,
        minute: 0,
        weekdays: Set(1...7),
        stackID: nil,
        soundEnabled: true
    )

    var allTimes: [ReminderTime] {
        if let times, !times.isEmpty {
            return times.sorted {
                ($0.hour, $0.minute) < ($1.hour, $1.minute)
            }
        }
        return [ReminderTime(id: Self.legacyTimeID, hour: hour, minute: minute)]
    }

    var timeText: String {
        allTimes.first?.timeText ?? ""
    }

    var weekdayText: String {
        if weekdays.count == 7 { return "Every day" }
        let labels = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return weekdays.sorted().map { labels[$0] }.joined(separator: ", ")
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var appearance: AppearancePreference
    var selectedStackID: UUID?
    var filter: CardFilter
    var rules: LearningRules
    var widgetDefaults: WidgetDefaults
    var reminders: ReminderPreferences
    var language: AppLanguage?
    var widgetWordSets: [WidgetWordSet]
    var hapticsEnabled: Bool

    init(
        schemaVersion: Int,
        appearance: AppearancePreference,
        selectedStackID: UUID?,
        filter: CardFilter,
        rules: LearningRules,
        widgetDefaults: WidgetDefaults,
        reminders: ReminderPreferences,
        language: AppLanguage?,
        widgetWordSets: [WidgetWordSet] = [],
        hapticsEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.appearance = appearance
        self.selectedStackID = selectedStackID
        self.filter = filter
        self.rules = rules
        self.widgetDefaults = widgetDefaults
        self.reminders = reminders
        self.language = language
        self.widgetWordSets = widgetWordSets
        self.hapticsEnabled = hapticsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appearance
        case selectedStackID
        case filter
        case rules
        case widgetDefaults
        case reminders
        case language
        case widgetWordSets
        case hapticsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appearance = try container.decode(AppearancePreference.self, forKey: .appearance)
        selectedStackID = try container.decodeIfPresent(UUID.self, forKey: .selectedStackID)
        filter = try container.decode(CardFilter.self, forKey: .filter)
        rules = try container.decode(LearningRules.self, forKey: .rules)
        widgetDefaults = try container.decode(WidgetDefaults.self, forKey: .widgetDefaults)
        reminders = try container.decode(ReminderPreferences.self, forKey: .reminders)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language)
        widgetWordSets = try container.decodeIfPresent([WidgetWordSet].self, forKey: .widgetWordSets) ?? []
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
    }

    static let `default` = AppPreferences(
        schemaVersion: 1,
        appearance: .system,
        selectedStackID: nil,
        filter: .all,
        rules: .default,
        widgetDefaults: .default,
        reminders: .default,
        language: .system
    )

    func widgetWordSet(id: UUID?) -> WidgetWordSet? {
        guard let id else { return nil }
        return widgetWordSets.first(where: { $0.id == id })
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

@MainActor
@Observable
final class PreferencesStore {
    static let storageKey = "flipabulary.preferences.v1"

    private let defaults: UserDefaults
    private(set) var storageError: String?
    var preferences: AppPreferences {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard, reset: Bool = false) {
        self.defaults = defaults
        if reset {
            defaults.removeObject(forKey: Self.storageKey)
        }
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = .default
        }
    }

    func reconcile(validStackIDs: Set<UUID>) {
        var updated = preferences
        if let selected = updated.selectedStackID, !validStackIDs.contains(selected) {
            updated.selectedStackID = nil
        }
        if let widgetStack = updated.widgetDefaults.stackID, !validStackIDs.contains(widgetStack) {
            updated.widgetDefaults.stackID = nil
        }
        if let reminderStack = updated.reminders.stackID, !validStackIDs.contains(reminderStack) {
            updated.reminders.stackID = nil
        }
        if updated != preferences {
            preferences = updated
        }
    }

    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        preferences = .default
        storageError = nil
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: Self.storageKey)
            storageError = nil
        } catch {
            storageError = "Preferences could not be saved: \(error.localizedDescription)"
        }
    }
}
