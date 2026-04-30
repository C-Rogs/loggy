import XCTest
@testable import Loggy

final class LoggyMetricDisplayTests: XCTestCase {
    func testKgNilReturnsEmpty() {
        XCTAssertEqual(LoggyMetricDisplay.kgForTextField(nil), "")
    }

    func testKgWholeNumberOmitsDecimal() {
        XCTAssertEqual(LoggyMetricDisplay.kgForTextField(60), "60")
        XCTAssertEqual(LoggyMetricDisplay.kgForTextField(100), "100")
    }

    func testKgFractionKeepsSigDigits() {
        XCTAssertEqual(LoggyMetricDisplay.kgForTextField(60.5), "60.5")
        XCTAssertEqual(LoggyMetricDisplay.kgForTextField(62.25), "62.25")
    }

    func testKmNilReturnsEmpty() {
        XCTAssertEqual(LoggyMetricDisplay.kmForTextField(nil), "")
    }

    func testKmWholeAndFraction() {
        XCTAssertEqual(LoggyMetricDisplay.kmForTextField(5), "5")
        XCTAssertEqual(LoggyMetricDisplay.kmForTextField(1.25), "1.25")
    }
}
