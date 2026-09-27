import XCTest
@testable import PocketCardCore

final class CropGestureTests: XCTestCase {
    func testDragMovesImageWithFinger() throws {
        var crop = CropSettings(); crop.aspect = .square
        let moved = try crop.applyingGesture(imageWidth: 800, imageHeight: 400, viewportWidth: 200,
                                              translationX: 50, translationY: 90, magnification: 1)
        let rect = try moved.rect(imageWidth: 800, imageHeight: 400)
        XCTAssertEqual(rect.x, 100, accuracy: 0.001)
        XCTAssertEqual(rect.y, 0)
    }
    func testPinchKeepsCenterAndClampsZoom() throws {
        var crop = CropSettings(); crop.aspect = .square; crop.horizontal = 0.25
        let enlarged = try crop.applyingGesture(imageWidth: 800, imageHeight: 400, viewportWidth: 200,
                                                 translationX: 0, translationY: 0, magnification: 2)
        let rect = try enlarged.rect(imageWidth: 800, imageHeight: 400)
        XCTAssertEqual(rect.x, 200, accuracy: 0.001)
        XCTAssertEqual(rect.y, 100, accuracy: 0.001)
        XCTAssertEqual(rect.width, 200)
        let clamped = try crop.applyingGesture(imageWidth: 800, imageHeight: 400, viewportWidth: 200,
                                               translationX: 9999, translationY: -9999, magnification: 100)
        XCTAssertEqual(clamped.zoom, 3)
        XCTAssertEqual(clamped.horizontal, 0)
        XCTAssertEqual(clamped.vertical, 1)
    }
    func testZoomOutNeverExposesEmptyEdges() throws {
        var crop = CropSettings(); crop.zoom = 3; crop.horizontal = 1; crop.vertical = 0
        for aspect in CropAspect.allCases {
            crop.aspect = aspect
            let result = try crop.applyingGesture(imageWidth: 400, imageHeight: 900, viewportWidth: 300,
                                                  translationX: -1000, translationY: 1000, magnification: 0.01)
            let rect = try result.rect(imageWidth: 400, imageHeight: 900)
            XCTAssertEqual(result.zoom, 1)
            XCTAssertGreaterThanOrEqual(rect.x, 0); XCTAssertGreaterThanOrEqual(rect.y, 0)
            XCTAssertLessThanOrEqual(rect.x + rect.width, 400.0001)
            XCTAssertLessThanOrEqual(rect.y + rect.height, 900.0001)
        }
    }
    func testInvalidGestureRejected() {
        XCTAssertThrowsError(try CropSettings().applyingGesture(imageWidth: 400, imageHeight: 900,
            viewportWidth: 0, translationX: 0, translationY: 0, magnification: 1))
    }
}
