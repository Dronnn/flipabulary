import Foundation
import UIKit

enum HapticImpact: Equatable, Sendable {
    case light
    case medium
    case heavy
    case soft
    case rigid
}

enum HapticNotification: Equatable, Sendable {
    case success
    case warning
    case error
}

@MainActor
protocol HapticEngine: AnyObject {
    func selectionChanged()
    func impactOccurred(_ style: HapticImpact, intensity: CGFloat)
    func notificationOccurred(_ type: HapticNotification)
}

@MainActor
final class SystemHapticEngine: HapticEngine {
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)

    func selectionChanged() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    func impactOccurred(_ style: HapticImpact, intensity: CGFloat) {
        let generator = switch style {
        case .light: lightGenerator
        case .medium: mediumGenerator
        case .heavy: heavyGenerator
        case .soft: softGenerator
        case .rigid: rigidGenerator
        }
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    func notificationOccurred(_ type: HapticNotification) {
        let feedback: UINotificationFeedbackGenerator.FeedbackType = switch type {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(feedback)
    }
}

@MainActor
final class HapticsService {
    private let preferences: PreferencesStore
    private let engine: HapticEngine

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        self.engine = SystemHapticEngine()
    }

    init(preferences: PreferencesStore, engine: HapticEngine) {
        self.preferences = preferences
        self.engine = engine
    }

    var isEnabled: Bool {
        preferences.preferences.hapticsEnabled
    }

    func selection() {
        guard isEnabled else { return }
        engine.selectionChanged()
    }

    func impact(_ style: HapticImpact = .light, intensity: CGFloat = 1) {
        guard isEnabled else { return }
        engine.impactOccurred(style, intensity: intensity)
    }

    func success() {
        notification(.success)
    }

    func warning() {
        notification(.warning)
    }

    func error() {
        notification(.error)
    }

    private func notification(_ type: HapticNotification) {
        guard isEnabled else { return }
        engine.notificationOccurred(type)
    }
}
