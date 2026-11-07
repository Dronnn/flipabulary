import Foundation

enum DurationFormatting {
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        formatter.maximumUnitCount = 2
        return formatter
    }()

    static func short(_ seconds: Double) -> String {
        let safe = max(0, seconds)
        if safe < 1 { return formatter.string(from: 1) ?? "1s" }
        return formatter.string(from: safe) ?? "0s"
    }
}

struct WordReviewHistoryItem: Identifiable, Sendable {
    var id: UUID
    var date: Date
    var grade: ReviewGrade
    var frontSeconds: Double
    var backSeconds: Double
}

struct WordStatistics: Sendable {
    var cardID: UUID
    var word: String
    var translation: String
    var lifecycle: CardLifecycle
    var repeatCount: Int
    var threshold: Int
    var totalGrades: Int
    var timedGrades: Int
    var goodCount: Int
    var againCount: Int
    var frontSeconds: Double
    var backSeconds: Double
    var lastReviewedAt: Date?
    var nextDueAt: Date?
    var isFullyMastered: Bool
    var isDifficult: Bool
    var history: [WordReviewHistoryItem]

    var totalSeconds: Double { frontSeconds + backSeconds }
    var averageSeconds: Double {
        timedGrades > 0 ? totalSeconds / Double(timedGrades) : 0
    }
    var accuracy: Double {
        totalGrades > 0 ? Double(goodCount) / Double(totalGrades) : 0
    }
}

struct DayStatistics: Identifiable, Sendable {
    var date: Date
    var dayKey: String
    var good = 0
    var again = 0
    var reviewSeconds: Double = 0
    var appSeconds: Double = 0

    var id: String { dayKey }
    var reviews: Int { good + again }
}

struct StackStatistics: Identifiable, Sendable {
    var id: UUID
    var name: String
    var saved: Int
    var learned: Int
    var mastered: Int
    var reviews: Int
    var good: Int
    var again: Int
    var reviewSeconds: Double
    var frontSeconds: Double
    var backSeconds: Double
    var activeSessionSeconds: Double
    var lastReviewedAt: Date?

    var accuracy: Double {
        reviews > 0 ? Double(good) / Double(reviews) : 0
    }
}

struct LibraryStatistics: Sendable {
    var days: [DayStatistics]
    var stacks: [StackStatistics]
    var totalAppSeconds: Double
    var totalReviewSeconds: Double
    var totalReviews: Int
    var totalGood: Int
    var totalAgain: Int
    var saved: Int
    var learned: Int
    var mastered: Int

    var accuracy: Double {
        totalReviews > 0 ? Double(totalGood) / Double(totalReviews) : 0
    }
}
