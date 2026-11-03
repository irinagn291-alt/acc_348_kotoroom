import XCTest
import Photos
@testable import Piproom

final class CleanupRulesTests: XCTestCase {
    func testSystemCaptureFlagsAreSpecificToMediaType() {
        XCTAssertTrue(CleanupKind.isScreenshot(.image, [.photoScreenshot, .photoHDR]))
        XCTAssertFalse(CleanupKind.isScreenshot(.image, .photoLive))
        XCTAssertFalse(CleanupKind.isScreenshot(.video, .photoScreenshot))
        XCTAssertTrue(CleanupKind.isRecording(.video, [.videoScreenRecording, .videoHighFrameRate]))
        XCTAssertFalse(CleanupKind.isRecording(.video, .videoStreamed))
        XCTAssertFalse(CleanupKind.isRecording(.image, .videoScreenRecording))
    }
}
