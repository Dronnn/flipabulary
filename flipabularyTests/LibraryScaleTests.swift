import XCTest
@testable import flipabulary

final class LibraryScaleTests: XCTestCase {
    private func model(_ index: Int) -> CardDisplayModel {
        CardDisplayModel(
            id: UUID(),
            word: "word \(index)",
            translation: "translation \(index)",
            sourceExample: nil,
            translatedExample: nil,
            phonetic: nil,
            partOfSpeech: nil,
            stackID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            stackName: "Scale",
            tagNames: ["tag \(index % 20)"],
            lifecycle: CardLifecycle.allCases[index % CardLifecycle.allCases.count],
            repeatCount: index % 5,
            threshold: 5,
            nextDueAt: nil,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            recentGrades: []
        )
    }

    func testPureIndexScalesToLargeLibraries() {
        let cards = (0..<20_000).map(model)
        let index = CardListIndex(cards: cards)
        measure(metrics: [XCTClockMetric()]) {
            let matches = index.filter(stackID: nil, filter: .all, search: "word 19999", limit: 150)
            XCTAssertEqual(matches.count, 1)
        }
    }

    @MainActor
    func testMergeScalesAcrossLargeOverlappingStacks() throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        for index in 0..<600 {
            harness.makeCard(
                word: "word \(index)",
                translation: "translation \(index)",
                stack: first
            )
            if index.isMultiple(of: 2) {
                harness.makeCard(
                    word: "translation \(index)",
                    translation: "word \(index)",
                    stack: second,
                    lifecycle: .learned,
                    repeatCount: 5
                )
            } else {
                harness.makeCard(
                    word: "word \(index)",
                    translation: "translation \(index)",
                    stack: second
                )
            }
        }
        try harness.save()

        switch harness.library.mergeStacks([first.id, second.id], named: "Merged", deleteOriginals: true) {
        case .success(let result):
            XCTAssertEqual(result.mergedCardCount, 600)
            XCTAssertEqual(result.duplicateCount, 600)
            XCTAssertEqual(result.removedStackCount, 2)
            XCTAssertEqual(result.stack.cards.count, 600)
            XCTAssertEqual(Set(result.stack.cards.map { "\($0.word)\u{1f}\($0.translation)" }).count, 600)
        case .failure(let error):
            XCTFail("Merge failed: \(error)")
        }
    }

    @MainActor
    func testStackStatsForLargeLibrary() async throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let stack = harness.makeStack()
        for index in 0..<800 {
            harness.makeCard(
                word: "word \(index)",
                translation: "translation \(index)",
                stack: stack
            )
        }
        try harness.save()

        let stats = await harness.library.computeStackStats(
            stackID: stack.id,
            rules: .default,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        XCTAssertEqual(stats?.total, 800)
        XCTAssertEqual(stats?.learned, 0)
        let expectedDue = LibraryProjection.dueCount(
            stack: stack,
            consumed: [],
            globalRules: .default,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        XCTAssertEqual(stats?.due, expectedDue)
    }

    @MainActor
    func testWidgetPublicationForLargeLibrary() throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let stack = harness.makeStack()
        for index in 0..<800 {
            harness.makeCard(
                word: "word \(index)",
                translation: "translation \(index)",
                stack: stack
            )
        }
        try harness.save()

        measure(metrics: [XCTClockMetric()]) {
            harness.maintenance.publishSnapshot()
        }
    }

    @MainActor
    func testSwiftDataProjectionAndIndexForLargeLibrary() throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let stack = harness.makeStack()
        for index in 0..<800 {
            harness.makeCard(
                word: "word \(index)",
                translation: "translation \(index)",
                stack: stack,
                tags: ["tag \(index % 20)"]
            )
        }
        try harness.save()

        measure(metrics: [XCTClockMetric()]) {
            let displays = harness.library.displayModels(stacks: harness.library.stacks())
            let index = CardListIndex(cards: displays)
            XCTAssertEqual(
                index.filter(stackID: nil, filter: .all, search: "word 799", limit: 150).count,
                1
            )
        }
    }
}
