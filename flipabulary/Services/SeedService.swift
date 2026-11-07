import Foundation
import SwiftData

@MainActor
enum SeedService {
    struct PreparationResult {
        var error: String?
        var didSeedDemo = false
    }

    @discardableResult
    static func prepare(
        context: ModelContext,
        preferences: PreferencesStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PreparationResult {
        do {
            var stacks = try context.fetch(FetchDescriptor<VocabularyStack>(sortBy: [SortDescriptor(\.createdAt)]))
            let defaultStack: VocabularyStack
            if stacks.isEmpty {
                defaultStack = VocabularyStack(name: "My words", isDefault: true, createdAt: now)
                context.insert(defaultStack)
                stacks = [defaultStack]
            } else if let existing = stacks.first(where: { $0.isDefault }) {
                defaultStack = existing
            } else {
                stacks.sort { $0.createdAt < $1.createdAt }
                let fallback = stacks[0]
                fallback.isDefault = true
                fallback.updatedAt = now
                defaultStack = fallback
            }

            if preferences.preferences.selectedStackID == nil {
                preferences.preferences.selectedStackID = defaultStack.id
            }
            if preferences.preferences.widgetDefaults.stackID == nil {
                preferences.preferences.widgetDefaults.stackID = defaultStack.id
            }
            preferences.reconcile(validStackIDs: Set(stacks.map(\.id)))

            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let shouldSeed = arguments.contains("-UITestDemoData") || arguments.contains("-DemoData")
            let shouldSeedLargeLibrary = arguments.contains("-UITestLargeLibrary")
            #else
            let shouldSeed = false
            let shouldSeedLargeLibrary = false
            #endif
            var didSeed = false
            if shouldSeedLargeLibrary && defaultStack.cards.isEmpty && stacks.allSatisfy({ $0.cards.isEmpty }) {
                defaultStack.shuffleOrder = false
                seedLargeLibrary(context: context, stack: defaultStack, now: now)
                didSeed = true
            } else if shouldSeed && defaultStack.cards.isEmpty && stacks.allSatisfy({ $0.cards.isEmpty }) {
                defaultStack.shuffleOrder = false
                seedDemo(context: context, stack: defaultStack, now: now)
                if !stacks.contains(where: { $0.name == "Spanish B1" }) {
                    let spanish = VocabularyStack(name: "Spanish B1", createdAt: now.addingTimeInterval(-86_400))
                    context.insert(spanish)
                }
                didSeed = true
            }

            try context.save()
            return PreparationResult(error: nil, didSeedDemo: didSeed)
        } catch {
            context.rollback()
            return PreparationResult(error: "Could not prepare the library: \(error.localizedDescription)", didSeedDemo: false)
        }
    }

    private static func seedLargeLibrary(context: ModelContext, stack: VocabularyStack, now: Date) {
        for index in 0..<800 {
            let card = VocabularyCard(
                word: "word \(index)",
                translation: "перевод \(index)",
                stack: stack,
                createdAt: now.addingTimeInterval(Double(index) / 1_000)
            )
            context.insert(card)
        }
    }

    private static func seedDemo(context: ModelContext, stack: VocabularyStack, now: Date) {
        let tag = VocabularyTag(name: "B1", createdAt: now.addingTimeInterval(-200_000))
        context.insert(tag)

        struct Fixture {
            let word: String
            let translation: String
            let sourceExample: String
            let translatedExample: String
            let phonetic: String
            let partOfSpeech: String
            let count: Int
            let lifecycle: CardLifecycle
            let dueOffset: TimeInterval?
            let grades: [ReviewGrade]
        }

        let fixtures: [Fixture] = [
            Fixture(
                word: "ephemeral",
                translation: "мимолетный",
                sourceExample: "Fame can be ephemeral.",
                translatedExample: "Слава может быть мимолетной.",
                phonetic: "ɪˈfem(ə)rəl",
                partOfSpeech: "adj",
                count: 3,
                lifecycle: .learning,
                dueOffset: -120,
                grades: [.good, .good, .good]
            ),
            Fixture(
                word: "ubiquitous",
                translation: "вездесущий",
                sourceExample: "Phones are ubiquitous now.",
                translatedExample: "Телефоны сейчас повсюду.",
                phonetic: "juːˈbɪkwɪtəs",
                partOfSpeech: "adj",
                count: 5,
                lifecycle: .learned,
                dueOffset: 86_400,
                grades: [.good, .good, .good, .good, .good]
            ),
            Fixture(
                word: "mitigate",
                translation: "смягчать",
                sourceExample: "We can mitigate the risk.",
                translatedExample: "Мы можем смягчить риск.",
                phonetic: "ˈmɪtɪɡeɪt",
                partOfSpeech: "vt",
                count: 1,
                lifecycle: .learning,
                dueOffset: -30,
                grades: [.good]
            ),
            Fixture(
                word: "resilient",
                translation: "устойчивый",
                sourceExample: "Children are wonderfully resilient.",
                translatedExample: "Дети удивительно устойчивы.",
                phonetic: "rɪˈzɪliənt",
                partOfSpeech: "adj",
                count: 2,
                lifecycle: .learning,
                dueOffset: 3_600,
                grades: [.good, .good]
            ),
            Fixture(
                word: "ambiguous",
                translation: "двусмысленный",
                sourceExample: "The answer was ambiguous.",
                translatedExample: "Ответ был двусмысленным.",
                phonetic: "amˈbɪɡjuəs",
                partOfSpeech: "adj",
                count: 4,
                lifecycle: .learning,
                dueOffset: -60,
                grades: [.good, .good, .good, .good]
            )
        ]

        for (index, fixture) in fixtures.enumerated() {
            let card = VocabularyCard(
                word: fixture.word,
                translation: fixture.translation,
                sourceExample: fixture.sourceExample,
                translatedExample: fixture.translatedExample,
                phonetic: fixture.phonetic,
                partOfSpeech: fixture.partOfSpeech,
                stack: stack,
                tags: [tag],
                createdAt: now.addingTimeInterval(-Double((fixtures.count - index) * 3_600))
            )
            context.insert(card)
            let state = card.learningState ?? CardLearningState(card: card)
            state.repeatCount = fixture.count
            state.lifecycle = fixture.lifecycle
            state.stepIndex = fixture.count
            state.nextDueAt = fixture.dueOffset.map { now.addingTimeInterval($0) }
            state.lastGradedAt = now.addingTimeInterval(-600)
            state.learnedAnchor = fixture.lifecycle == .learned ? now : nil
            state.totalGrades = fixture.grades.count
            state.rulesVersion = LearningRules.default.version
            state.card = card
            card.learningState = state
            if card.learningState == nil {
                context.insert(state)
            }

            let sessionID = UUID()
            for (gradeIndex, grade) in fixture.grades.enumerated() {
                let before = gradeIndex
                let after = grade == .good ? min(before + 1, 5) : 0
                let event = ReviewEvent(
                    presentationID: UUID(),
                    sessionID: sessionID,
                    cardID: card.id,
                    grade: grade,
                    timestamp: now.addingTimeInterval(-Double((fixture.grades.count - gradeIndex) * 120)),
                    beforeRepeatCount: before,
                    afterRepeatCount: after,
                    beforeLifecycle: before == 0 ? .new : .learning,
                    afterLifecycle: after >= 5 ? .learned : .learning,
                    rulesVersion: LearningRules.default.version,
                    card: card
                )
                context.insert(event)
            }
        }
    }
}
