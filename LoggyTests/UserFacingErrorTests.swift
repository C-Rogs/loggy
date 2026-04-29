import XCTest
@testable import Loggy

final class UserFacingErrorTests: XCTestCase {
    func testHevyImportMapped() {
        let m = UserFacingError.message(for: HevyImportError.missingHeader)
        XCTAssertTrue(m.contains("Hevy") || m.contains("CSV"), "Should reference Hevy/CSV, got: \(m)")
    }

    func testExportErrorMapped() {
        let m = UserFacingError.message(for: ExportError.encodingFailed)
        XCTAssertFalse(m.isEmpty)
    }
}
