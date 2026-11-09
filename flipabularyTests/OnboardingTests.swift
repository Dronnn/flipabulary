import XCTest
@testable import flipabulary

@MainActor
final class OnboardingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "onboarding.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    private func makeStore() -> OnboardingStore {
        OnboardingStore(defaults: defaults)
    }

    func testFirstLaunchStartsPresentedAtWelcome() {
        let store = makeStore()
        XCTAssertTrue(store.isPresented)
        XCTAssertFalse(store.hasCompleted)
        XCTAssertEqual(store.step, .welcome)
        XCTAssertEqual(store.stepNumber, 1)
        XCTAssertEqual(store.stepCount, 5)
    }

    func testAdvanceWalksThroughEveryStepInOrder() {
        let store = makeStore()
        XCTAssertEqual(store.step, .welcome)

        store.advance()
        XCTAssertEqual(store.step, .wordSets)

        store.advance()
        XCTAssertEqual(store.step, .widgets)

        store.advance()
        XCTAssertEqual(store.step, .learning)

        store.advance()
        XCTAssertEqual(store.step, .ready)
        XCTAssertTrue(store.isLastStep)

        store.advance()
        XCTAssertTrue(store.hasCompleted)
        XCTAssertFalse(store.isPresented)
    }

    func testBackWalksEveryStepAndStopsAtWelcome() {
        let store = makeStore()
        store.advance()
        store.advance()
        store.advance()
        store.advance()
        XCTAssertEqual(store.step, .ready)

        store.goBack()
        XCTAssertEqual(store.step, .learning)
        store.goBack()
        XCTAssertEqual(store.step, .widgets)
        store.goBack()
        XCTAssertEqual(store.step, .wordSets)
        store.goBack()
        XCTAssertEqual(store.step, .welcome)
        store.goBack()
        XCTAssertEqual(store.step, .welcome)
    }

    func testSelectingAStepPersistsItForSwipeNavigation() {
        let store = makeStore()
        store.select(.widgets)
        XCTAssertEqual(store.step, .widgets)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.isPresented)
        XCTAssertEqual(reloaded.step, .widgets)
    }

    func testSkipCompletesAndPersists() {
        let store = makeStore()
        store.advance()
        store.skip()

        XCTAssertTrue(store.hasCompleted)
        XCTAssertFalse(store.isPresented)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.hasCompleted)
        XCTAssertFalse(reloaded.isPresented)
        XCTAssertEqual(reloaded.step, .welcome)
    }

    func testCompletionPersistsAndDoesNotPresentOnNextLaunch() {
        let store = makeStore()
        store.complete()

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.hasCompleted)
        XCTAssertFalse(reloaded.isPresented)
    }

    func testProgressResumesFromTheSavedStep() {
        let store = makeStore()
        store.select(.learning)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.isPresented)
        XCTAssertFalse(reloaded.hasCompleted)
        XCTAssertEqual(reloaded.step, .learning)
    }

    func testPresentAgainResetsProgressAndShowsWelcome() {
        let store = makeStore()
        store.complete()
        XCTAssertTrue(store.hasCompleted)

        store.presentAgain()
        XCTAssertTrue(store.isPresented)
        XCTAssertFalse(store.hasCompleted)
        XCTAssertEqual(store.step, .welcome)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.isPresented)
        XCTAssertEqual(reloaded.step, .welcome)
    }

    func testNextAndPreviousStepBoundaries() {
        XCTAssertEqual(OnboardingStore.nextStep(after: .welcome), .wordSets)
        XCTAssertEqual(OnboardingStore.nextStep(after: .wordSets), .widgets)
        XCTAssertEqual(OnboardingStore.nextStep(after: .widgets), .learning)
        XCTAssertEqual(OnboardingStore.nextStep(after: .learning), .ready)
        XCTAssertNil(OnboardingStore.nextStep(after: .ready))

        XCTAssertNil(OnboardingStore.previousStep(before: .welcome))
        XCTAssertEqual(OnboardingStore.previousStep(before: .wordSets), .welcome)
        XCTAssertEqual(OnboardingStore.previousStep(before: .widgets), .wordSets)
        XCTAssertEqual(OnboardingStore.previousStep(before: .learning), .widgets)
        XCTAssertEqual(OnboardingStore.previousStep(before: .ready), .learning)
    }

    func testSetOrderDemoMovesRowsLikeTheEditorList() {
        var demo = OnboardingSetOrderDemo(words: ["one", "two", "three", "four"])
        XCTAssertTrue(demo.move(fromOffsets: IndexSet(integer: 0), toOffset: 3))
        XCTAssertEqual(demo.words, ["two", "three", "one", "four"])
        XCTAssertTrue(demo.move(fromOffsets: IndexSet(integer: 3), toOffset: 0))
        XCTAssertEqual(demo.words, ["four", "two", "three", "one"])
        XCTAssertFalse(demo.move(fromOffsets: IndexSet(integer: 1), toOffset: 1))
        XCTAssertEqual(demo.words, ["four", "two", "three", "one"])
    }

    func testDefaultLearningDemoRequiresRevealBeforeRating() {
        var demo = OnboardingLearningDemo()
        XCTAssertFalse(demo.isRevealed)
        XCTAssertFalse(demo.canRate)
        XCTAssertEqual(demo.repeatCount, 0)

        demo.rate(.good)
        XCTAssertEqual(demo.repeatCount, 0)
    }

    func testLearningDemoGoodAnswersReachLearnedAtThreshold() {
        var demo = OnboardingLearningDemo(threshold: 3)
        demo.reveal()
        XCTAssertTrue(demo.canRate)

        demo.rate(.good)
        XCTAssertEqual(demo.repeatCount, 1)
        XCTAssertEqual(demo.lastGrade, .good)
        XCTAssertFalse(demo.isLearned)

        demo.rate(.good)
        XCTAssertEqual(demo.repeatCount, 2)
        XCTAssertFalse(demo.isLearned)

        demo.rate(.good)
        XCTAssertEqual(demo.repeatCount, 3)
        XCTAssertTrue(demo.isLearned)
        XCTAssertEqual(demo.phase, .learned)

        demo.rate(.good)
        XCTAssertEqual(demo.repeatCount, 3)
    }

    func testLearningDemoAgainResetsTheStreak() {
        var demo = OnboardingLearningDemo()
        demo.reveal()
        demo.rate(.good)
        demo.rate(.good)
        XCTAssertEqual(demo.repeatCount, 2)

        demo.rate(.again)
        XCTAssertEqual(demo.repeatCount, 0)
        XCTAssertEqual(demo.lastGrade, .again)
        XCTAssertFalse(demo.isLearned)
        XCTAssertTrue(demo.canRate)
    }

    func testLearningDemoTryAgainReturnsToPrompt() {
        var demo = OnboardingLearningDemo(threshold: 1)
        demo.reveal()
        demo.rate(.good)
        XCTAssertTrue(demo.isLearned)

        demo.tryAgain()
        XCTAssertEqual(demo.phase, .prompt)
        XCTAssertEqual(demo.repeatCount, 0)
        XCTAssertNil(demo.lastGrade)
        XCTAssertFalse(demo.isRevealed)
    }
}
