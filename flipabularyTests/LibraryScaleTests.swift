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
