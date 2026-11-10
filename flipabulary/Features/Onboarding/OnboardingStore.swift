import Foundation
import Observation
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Codable, Sendable {
    case welcome
    case wordSets
    case widgets
    case learning
    case ready
}

@MainActor
@Observable
final class OnboardingStore {
    static let completedKey = "flipabulary.onboarding.completed.v1"
    static let stepKey = "flipabulary.onboarding.step.v1"

    private let defaults: UserDefaults

    private(set) var hasCompleted: Bool
    private(set) var step: OnboardingStep

    var isPresented: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var suppressForUITests = false
        #if DEBUG
        if defaults === UserDefaults.standard {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-UITestOnboarding") {
                defaults.removeObject(forKey: Self.completedKey)
                defaults.removeObject(forKey: Self.stepKey)
            } else if !arguments.contains("-UITestOnboardingKeepState"),
                      arguments.contains("-UITestInMemory") {
                suppressForUITests = true
            }
        }
        #endif

        let completed = suppressForUITests || defaults.bool(forKey: Self.completedKey)
        hasCompleted = completed

        if !completed,
           let rawValue = defaults.object(forKey: Self.stepKey) as? Int,
           let savedStep = OnboardingStep(rawValue: rawValue) {
            step = savedStep
        } else {
            step = .welcome
        }

        isPresented = !completed
    }

    var isLastStep: Bool { step == .ready }

    var stepNumber: Int { step.rawValue + 1 }

    var stepCount: Int { OnboardingStep.allCases.count }

    func select(_ newStep: OnboardingStep) {
        setStep(newStep)
    }

    func advance() {
        guard let next = Self.nextStep(after: step) else {
            complete()
            return
        }
        setStep(next)
    }

    func goBack() {
        guard let previous = Self.previousStep(before: step) else { return }
        setStep(previous)
    }

    func skip() {
        complete()
    }

    func complete() {
        hasCompleted = true
        defaults.set(true, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.stepKey)
        step = .welcome
        isPresented = false
    }

    func presentAgain() {
        hasCompleted = false
        defaults.set(false, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.stepKey)
        step = .welcome
        isPresented = true
    }

    static func nextStep(after step: OnboardingStep) -> OnboardingStep? {
        switch step {
        case .welcome: .wordSets
        case .wordSets: .widgets
        case .widgets: .learning
        case .learning: .ready
        case .ready: nil
        }
    }

    static func previousStep(before step: OnboardingStep) -> OnboardingStep? {
        switch step {
        case .welcome: nil
        case .wordSets: .welcome
        case .widgets: .wordSets
        case .learning: .widgets
        case .ready: .learning
        }
    }

    private func setStep(_ newStep: OnboardingStep) {
        step = newStep
        defaults.set(newStep.rawValue, forKey: Self.stepKey)
    }
}

// MARK: - Word set order demo

struct OnboardingSetOrderDemo: Equatable, Sendable {
    static let defaultWords = ["ubiquitous", "resilient", "mitigate"]

    private(set) var words: [String]

    init(words: [String] = OnboardingSetOrderDemo.defaultWords) {
        self.words = words
    }

    @discardableResult
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
        let before = words
        words.move(fromOffsets: offsets, toOffset: destination)
        return words != before
    }
}

// MARK: - Learning demo

enum OnboardingLearningDemoPhase: Equatable, Sendable {
    case prompt
    case revealed
    case learned
}

struct OnboardingLearningDemo: Equatable, Sendable {
    private(set) var snapshot = LearningSnapshot.fresh
    private(set) var simulatedDate = Date(timeIntervalSince1970: 0)
    private(set) var phase: OnboardingLearningDemoPhase = .prompt
    private(set) var lastGrade: ReviewGrade?

    var threshold: Int { LearningRules.default.correctThreshold }
    var repeatCount: Int { snapshot.repeatCount }
    var isRevealed: Bool { phase != .prompt }
    var canRate: Bool { phase == .revealed }
    var isLearned: Bool { snapshot.isFullyMastered }

    mutating func reveal() {
        guard phase == .prompt else { return }
        phase = .revealed
    }

    mutating func rate(_ grade: ReviewGrade) {
        guard canRate else { return }
        lastGrade = grade
        simulatedDate = snapshot.nextDueAt ?? simulatedDate
        snapshot = LearningEngine.grade(snapshot, grade: grade, rules: .default, at: simulatedDate).after
        if isLearned { phase = .learned }
    }

    mutating func tryAgain() {
        self = OnboardingLearningDemo()
    }
}
