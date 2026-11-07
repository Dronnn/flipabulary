import XCTest
@testable import flipabulary

final class SwipeAxisLockTests: XCTestCase {
    func testReversingThroughCentreKeepsTrackingHorizontally() {
        var lock = SwipeAxisLock()
        XCTAssertTrue(lock.tracksHorizontal(CGSize(width: -80, height: 24)))
        XCTAssertTrue(lock.tracksHorizontal(CGSize(width: -12, height: 24)))
        XCTAssertTrue(lock.tracksHorizontal(CGSize(width: 0, height: 24)))
        XCTAssertTrue(lock.tracksHorizontal(CGSize(width: 12, height: 24)))
        XCTAssertEqual(lock.axis, .horizontal)
    }

    func testVerticalStartStaysVertical() {
        var lock = SwipeAxisLock()
        XCTAssertFalse(lock.tracksHorizontal(CGSize(width: 8, height: 30)))
        XCTAssertFalse(lock.tracksHorizontal(CGSize(width: 90, height: 4)))
        XCTAssertEqual(lock.axis, .vertical)
    }

    func testResetAllowsANewAxisForTheNextGesture() {
        var lock = SwipeAxisLock()
        XCTAssertFalse(lock.tracksHorizontal(CGSize(width: 4, height: 20)))
        lock.reset()
        XCTAssertTrue(lock.tracksHorizontal(CGSize(width: 20, height: 4)))
    }

    func testInitialFingerJitterDoesNotLockTheWrongAxis() {
        var lock = SwipeAxisLock()
        XCTAssertFalse(lock.tracksHorizontal(CGSize(width: 2, height: 5)))
        XCTAssertNil(lock.axis)
        XCTAssertTrue(lock.tracksHorizontal(CGSize(width: 60, height: 10)))
        XCTAssertEqual(lock.axis, .horizontal)
    }

    func testZeroTranslationDoesNotLockTheAxis() {
        var lock = SwipeAxisLock()
        XCTAssertFalse(lock.tracksHorizontal(.zero))
        XCTAssertNil(lock.axis)
    }
}
