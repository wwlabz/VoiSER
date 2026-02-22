import XCTest
@testable import VoiceWidget

@MainActor
final class OverlayWidgetViewModelTests: XCTestCase {
    func testInputLevelSmoothingIsClampedAndMonotonicToTarget() {
        let viewModel = OverlayWidgetViewModel()

        viewModel.pushInputLevel(1.6)
        let first = viewModel.inputLevelSmoothed
        viewModel.pushInputLevel(1.0)
        let second = viewModel.inputLevelSmoothed
        viewModel.pushInputLevel(1.0)
        let third = viewModel.inputLevelSmoothed

        XCTAssertEqual(viewModel.inputLevelRaw, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThan(second, first)
        XCTAssertGreaterThan(third, second)
        XCTAssertLessThanOrEqual(third, 1.0)
    }

    func testResetInputLevelsClearsRawAndSmoothed() {
        let viewModel = OverlayWidgetViewModel()

        viewModel.pushInputLevel(0.7)
        viewModel.pushInputLevel(0.8)
        XCTAssertGreaterThan(viewModel.inputLevelSmoothed, 0)

        viewModel.resetInputLevels()
        XCTAssertEqual(viewModel.inputLevelRaw, 0)
        XCTAssertEqual(viewModel.inputLevelSmoothed, 0)
    }
}
