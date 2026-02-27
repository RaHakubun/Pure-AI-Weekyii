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

        let firstHandle = app.images["draftDragHandle_0"]
        let secondHandle = app.images["draftDragHandle_1"]
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

    func testDraftAddAndEditBothOpenTaskEditorSheet() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft",
            "1"
        ]
        app.launch()

        let addButton = app.buttons["draftAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let editorTitleField = app.textFields["taskEditorTitleField"]
        XCTAssertTrue(editorTitleField.waitForExistence(timeout: 3))

        let cancelButton = app.buttons["taskEditorCancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.tap()

        let firstDraftTask = app.staticTexts["draftTaskTitle_0"]
        XCTAssertTrue(firstDraftTask.waitForExistence(timeout: 3))
        firstDraftTask.tap()

        XCTAssertTrue(editorTitleField.waitForExistence(timeout: 3))
    }

    func testDraftShowsFloatingStartButton() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft",
            "1"
        ]
        app.launch()

        let floatingStartButton = app.buttons["todayFloatingStartButton"]
        XCTAssertTrue(floatingStartButton.waitForExistence(timeout: 5))
        XCTAssertTrue(floatingStartButton.isHittable)
    }

    func testStartFlowSheetShowsEnhancedSections() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft",
            "1"
        ]
        app.launch()

        let floatingStartButton = app.buttons["todayFloatingStartButton"]
        XCTAssertTrue(floatingStartButton.waitForExistence(timeout: 5))
        floatingStartButton.tap()

        let sheetHeader = app.otherElements["startFlowSheetHeader"]
        XCTAssertTrue(sheetHeader.waitForExistence(timeout: 3))

        let warningCard = app.otherElements["startFlowWarningCard"]
        XCTAssertTrue(warningCard.waitForExistence(timeout: 2))

        let primaryAction = app.buttons["startFlowPrimaryButton"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 2))
    }
}
