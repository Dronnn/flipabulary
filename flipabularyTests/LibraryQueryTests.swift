import XCTest
@testable import flipabulary

final class LibraryQueryTests: XCTestCase {
    private let stackA = UUID()
    private let stackB = UUID()
    private let now = testDate("2026-11-07T10:00:00Z")

    private func card(
        id: UUID = UUID(),
        word: String,
        translation: String = "перевод",
        stack: UUID? = nil,
        lifecycle: CardLifecycle = .learning,
        count: Int = 1,
        tags: [String] = [],
        created: Date? = nil,
        grades: [ReviewGrade] = [.good]
    ) -> CardDisplayModel {
        CardDisplayModel(
            id: id,
            word: word,
            translation: translation,
            sourceExample: nil,
            translatedExample: nil,
            phonetic: nil,
            partOfSpeech: nil,
            stackID: stack ?? stackA,
            stackName: "My words",
            tagNames: tags,
            lifecycle: lifecycle,
            repeatCount: count,
            threshold: 5,
            nextDueAt: nil,
            createdAt: created ?? now,
            recentGrades: grades.enumerated().map { index, grade in
                CardHistoryItem(grade: grade, timestamp: now.addingTimeInterval(TimeInterval(-index)))
            }
        )
    }

    func testScopeAndFilterAndSearchIntersect() {
        let cards = [
            card(word: "ephemeral", translation: "мимолетный", stack: stackA, lifecycle: .learning, tags: ["B1"]),
            card(word: "ubiquitous", translation: "вездесущий", stack: stackA, lifecycle: .learned),
            card(word: "ephemeral", translation: "мимолетный", stack: stackB, lifecycle: .new),
            card(word: "mitigate", translation: "смягчать", stack: stackB, lifecycle: .learning)
        ]

        let stackAFiltered = LibraryQuery.filter(cards, stackID: stackA, filter: .all, search: "")
        XCTAssertEqual(Set(stackAFiltered.map(\.word)), ["ephemeral", "ubiquitous"])

        let learnedInA = LibraryQuery.filter(cards, stackID: stackA, filter: .learned, search: "")
        XCTAssertEqual(learnedInA.map(\.word), ["ubiquitous"])

        let tagSearch = LibraryQuery.filter(cards, stackID: nil, filter: .all, search: "b1")
        XCTAssertEqual(tagSearch.map(\.word), ["ephemeral"])
    }

    func testUnicodeNormalizedSearch() {
        let cards = [
            card(word: "café", translation: "кофейня"),
            card(word: "МИМОЛЕТНЫЙ", translation: "ephemeral"),
            card(word: "ＦＵＬＬ", translation: "fullwidth")
        ]
        XCTAssertEqual(LibraryQuery.filter(cards, stackID: nil, filter: .all, search: "CAFE").map(\.word), ["café"])
        XCTAssertEqual(LibraryQuery.filter(cards, stackID: nil, filter: .all, search: "мимолет").map(\.word), ["МИМОЛЕТНЫЙ"])
        XCTAssertEqual(LibraryQuery.filter(cards, stackID: nil, filter: .all, search: "full").map(\.word), ["ＦＵＬＬ"])
    }

    func testDifficultUsesLastFiveAnswersOnly() {
        let difficult = card(
            word: "difficult",
            grades: [.good, .again, .good, .again, .good, .good, .good]
        )
        let nowEasy = card(
            word: "recovered",
            grades: [.again, .again, .good, .good, .good]
        )
        let oldMistakes = card(
            word: "old",
            grades: [.good, .good, .good, .good, .good, .again, .again]
        )
        XCTAssertTrue(difficult.isDifficult)
        XCTAssertTrue(nowEasy.isDifficult)
        XCTAssertFalse(oldMistakes.isDifficult)
    }

    func testSummaryCountsAreDisjointAndRatiosSafe() {
        let cards = [
            card(word: "new", lifecycle: .new, count: 0),
            card(word: "learning", lifecycle: .learning, count: 2),
            card(word: "learned", lifecycle: .learned, count: 5)
        ]
        let summary = LibraryQuery.summary(allCards: cards, stackID: nil, dueCount: 4)
        XCTAssertEqual(summary.saved, 3)
        XCTAssertEqual(summary.new + summary.learning + summary.learned, summary.saved)
        XCTAssertEqual(summary.due, 4)
        XCTAssertEqual(summary.learnedProgress, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(LibraryQuery.relativeRatio(count: 0, total: 0), 0)
        XCTAssertFalse(LibraryQuery.relativeRatio(count: 0, total: 0).isNaN)
    }

    func testStableSortingByCreationThenID() {
        let later = card(word: "later", created: now.addingTimeInterval(10))
        let sameA = card(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, word: "a", created: now)
        let sameB = card(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, word: "b", created: now)
        let filtered = LibraryQuery.filter([later, sameB, sameA], stackID: nil, filter: .all, search: "")
        XCTAssertEqual(filtered.map(\.word), ["a", "b", "later"])
        let again = LibraryQuery.filter([later, sameB, sameA], stackID: nil, filter: .all, search: "")
        XCTAssertEqual(filtered.map(\.id), again.map(\.id))
    }

    func testEmptyScopeAndZeroTotalCategoryRatios() {
        let summary = LibraryQuery.summary(allCards: [], stackID: nil, dueCount: 0)
        XCTAssertEqual(summary.saved, 0)
        XCTAssertEqual(summary.learnedProgress, 0)
        let categories = LibraryQuery.categoryCounts(allCards: [], stackID: nil)
        XCTAssertEqual(categories.count, 4)
        XCTAssertTrue(categories.allSatisfy { $0.count == 0 })
    }
}
