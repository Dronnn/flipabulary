import XCTest
@testable import flipabulary

@MainActor
final class HapticsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var preferences: PreferencesStore!
    private var engine: FakeHapticEngine!
    private var haptics: HapticsService!

    override func setUp() async throws {
        suiteName = "haptics.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        preferences = PreferencesStore(defaults: defaults)
        engine = FakeHapticEngine()
        haptics = HapticsService(preferences: preferences, engine: engine)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        preferences = nil
        engine = nil
        haptics = nil
    }

    func testHapticsAreEnabledByDefault() {
        XCTAssertTrue(preferences.preferences.hapticsEnabled)
        XCTAssertTrue(haptics.isEnabled)
    }

    func testDisabledHapticsProduceNoCalls() {
        preferences.preferences.hapticsEnabled = false

        haptics.selection()
        haptics.impact(.medium)
        haptics.impact(.rigid, intensity: 0.5)
        haptics.success()
        haptics.warning()
        haptics.error()

        XCTAssertTrue(engine.calls.isEmpty)
    }

    func testEnabledHapticsForwardSelectionImpactAndNotifications() {
        haptics.selection()
        haptics.impact(.medium)
        haptics.impact(.rigid, intensity: 0.5)
        haptics.success()
        haptics.warning()
        haptics.error()

        XCTAssertEqual(
            engine.calls,
            [
                .selection,
                .impact(.medium, 1),
                .impact(.rigid, 0.5),
                .notification(.success),
                .notification(.warning),
                .notification(.error)
            ]
        )
    }

    func testHapticsServiceFollowsPreferenceChanges() {
        haptics.selection()
        XCTAssertEqual(engine.calls, [.selection])

        preferences.preferences.hapticsEnabled = false
        haptics.selection()
        XCTAssertEqual(engine.calls, [.selection])

        preferences.preferences.hapticsEnabled = true
        haptics.selection()
        XCTAssertEqual(engine.calls, [.selection, .selection])
    }
}
