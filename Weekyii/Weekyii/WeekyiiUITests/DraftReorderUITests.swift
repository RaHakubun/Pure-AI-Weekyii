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

        let explicitFirstHandle = app.images["draftDragHandle_0"]
        let explicitSecondHandle = app.images["draftDragHandle_1"]
        let firstHandle: XCUIElement
        let secondHandle: XCUIElement
        if explicitFirstHandle.waitForExistence(timeout: 1), explicitSecondHandle.waitForExistence(timeout: 1) {
            firstHandle = explicitFirstHandle
            secondHandle = explicitSecondHandle
        } else {
            let systemHandles = app.images.matching(identifier: "line.horizontal.3")
            XCTAssertGreaterThanOrEqual(systemHandles.count, 2)
            firstHandle = systemHandles.element(boundBy: 0)
            secondHandle = systemHandles.element(boundBy: 1)
            XCTAssertTrue(firstHandle.waitForExistence(timeout: 2))
            XCTAssertTrue(secondHandle.waitForExistence(timeout: 2))
        }

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

    func testRitualStepShowsOnlyStampAndConfirmAction() {
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

        let warningPrimaryButton = app.buttons["startFlowPrimaryButton"]
        XCTAssertTrue(warningPrimaryButton.waitForExistence(timeout: 2))
        warningPrimaryButton.tap()

        let ritualCard = app.otherElements["startFlowRitualCard"]
        XCTAssertTrue(ritualCard.waitForExistence(timeout: 3))

        let ritualSecondaryButton = app.buttons["startFlowSecondaryButton"]
        XCTAssertFalse(ritualSecondaryButton.exists)

        let confirmButton = app.buttons["startFlowPrimaryButton"]
        XCTAssertTrue(confirmButton.exists)
        XCTAssertEqual(confirmButton.label, "确认开始")
    }

    func testExtensionsEmptyStateDoesNotShowDuplicateCreateButtons() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        let extensionsTab = app.tabBars.buttons["扩展"]
        XCTAssertTrue(extensionsTab.waitForExistence(timeout: 5))
        extensionsTab.tap()

        let projectsSeeAll = app.buttons["extensionsProjectsSeeAllButton"]
        XCTAssertTrue(projectsSeeAll.waitForExistence(timeout: 5))
        projectsSeeAll.tap()

        let projectsEmptyCreate = app.buttons["projectsEmptyCreateButton"]
        XCTAssertTrue(projectsEmptyCreate.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["projectsFooterCreateButton"].exists)

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()

        let mindStampsSeeAll = app.buttons["extensionsMindStampsSeeAllButton"]
        XCTAssertTrue(mindStampsSeeAll.waitForExistence(timeout: 5))
        mindStampsSeeAll.tap()

        let mindStampsEmptyCreate = app.buttons["mindstampsEmptyCreateButton"]
        XCTAssertTrue(mindStampsEmptyCreate.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["mindstampsFooterCreateButton"].exists)
    }
}
