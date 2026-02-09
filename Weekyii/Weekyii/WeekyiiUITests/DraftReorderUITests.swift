import XCTest

final class DraftReorderUITests: XCTestCase {
    func testDragHandleReordersDraftTasks() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft",
            "1"
        ]
        app.launch()

        let editButton = app.buttons["draftEditButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let firstTitle = app.staticTexts["draftTaskTitle_0"]
        let secondTitle = app.staticTexts["draftTaskTitle_1"]
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 2))
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 2))

        let firstHandle = app.buttons["draftDragHandle_0"]
        let secondHandle = app.buttons["draftDragHandle_1"]
        XCTAssertTrue(firstHandle.waitForExistence(timeout: 2))
        XCTAssertTrue(secondHandle.waitForExistence(timeout: 2))

        let firstBefore = firstTitle.label
        let secondBefore = secondTitle.label

        secondHandle.press(forDuration: 0.2, thenDragTo: firstHandle)

        let firstAfter = app.staticTexts["draftTaskTitle_0"].label
        let secondAfter = app.staticTexts["draftTaskTitle_1"].label

        XCTAssertEqual(firstAfter, secondBefore)
        XCTAssertEqual(secondAfter, firstBefore)
    }
}
