@testable import MeetingTranscriber
import XCTest

final class ElapsedTimeTests: XCTestCase {
    func testFormatsMinutesAndHours() {
        XCTAssertEqual(ElapsedTime.string(seconds: 0), "00:00")
        XCTAssertEqual(ElapsedTime.string(seconds: 65), "01:05")
        XCTAssertEqual(ElapsedTime.string(seconds: 3599.9), "59:59")
        XCTAssertEqual(ElapsedTime.string(seconds: 3725), "1:02:05")
    }

    func testNegativeSpansReadAsZero() {
        XCTAssertEqual(ElapsedTime.string(seconds: -5), "00:00")
    }
}
