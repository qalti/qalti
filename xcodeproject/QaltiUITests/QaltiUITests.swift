import XCTest
import QaltiRunnerLib

final class QaltiUITests: XCTestCase {

    let runner = QaltiRunnerLib.QaltiRunner()

    @MainActor
    func testRunController() throws {

        try runner.testRunController()
    }

}
