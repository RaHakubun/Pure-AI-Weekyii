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
        XCTAssertTrue(firstTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTitle.waitForExistence(timeout: 5))

        let firstBefore = firstTitle.label
        let secondBefore = secondTitle.label

        let moveDownButton = app.buttons["draftMoveDown_0"]
        XCTAssertTrue(moveDownButton.waitForExistence(timeout: 3))
        moveDownButton.tap()

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

    func testPendingWeekDetailShowsDraftCrudEntryPoints() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedPendingWeek",
            "1"
        ]
        app.launch()

        let pendingTab = app.tabBars.buttons["未来"]
        XCTAssertTrue(pendingTab.waitForExistence(timeout: 5))
        pendingTab.tap()

        let weekCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pendingWeekCard_'")).firstMatch
        XCTAssertTrue(weekCard.waitForExistence(timeout: 5))
        weekCard.tap()

        let addButton = app.buttons["pendingDraftAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        let titleField = app.textFields["taskEditorTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))

        let cancelButton = app.buttons["taskEditorCancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.tap()

        let pendingEditButton = app.buttons["pendingDraftEditButton"]
        XCTAssertTrue(pendingEditButton.waitForExistence(timeout: 2))

        let firstTask = app.buttons["pendingDraftTask_0"]
        XCTAssertTrue(firstTask.waitForExistence(timeout: 3))
        firstTask.tap()

        XCTAssertTrue(titleField.waitForExistence(timeout: 3))

        let editorCancelButton = app.buttons["taskEditorCancelButton"]
        XCTAssertTrue(editorCancelButton.waitForExistence(timeout: 2))
        editorCancelButton.tap()

        XCTAssertTrue(pendingEditButton.waitForExistence(timeout: 2))
        pendingEditButton.tap()

        let secondTask = app.buttons["pendingDraftTask_1"]
        XCTAssertTrue(secondTask.waitForExistence(timeout: 3))

        let deleteButton = app.buttons["pendingDraftDeleteButton_0"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        let confirmDelete = app.buttons["删除任务"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 2))
        XCTAssertTrue(secondTask.exists)

        let destructiveButtons = app.buttons.matching(identifier: "删除任务")
        XCTAssertGreaterThanOrEqual(destructiveButtons.count, 1)
        destructiveButtons.element(boundBy: 0).tap()

        XCTAssertFalse(app.buttons["pendingDraftTask_1"].waitForExistence(timeout: 2))
    }

    func testSuspendedTasksCanBeCreatedAndDeletedWithConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        let extensionsTab = app.tabBars.buttons["扩展"]
        XCTAssertTrue(extensionsTab.waitForExistence(timeout: 5))
        extensionsTab.tap()

        let suspendedSeeAll = app.buttons["extensionsSuspendedSeeAllButton"]
        XCTAssertTrue(suspendedSeeAll.waitForExistence(timeout: 5))
        suspendedSeeAll.tap()

        let createButton = app.buttons["suspendedEmptyCreateButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        createButton.tap()

        let titleField = app.textFields["suspendedTaskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("Wait for legal reply")

        let saveButton = app.buttons["suspendedTaskSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.tap()

        let taskTitle = app.staticTexts["Wait for legal reply"]
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 3))

        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'suspendedDeleteButton_'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        let confirmDelete = app.sheets.buttons["删除"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 2))
        confirmDelete.tap()

        XCTAssertFalse(taskTitle.waitForExistence(timeout: 2))
    }

    func testWeekOverviewSupportsCardsStripsAndCollapsedModes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        let weekButton = app.buttons["todaySectionWeekButton"]
        XCTAssertTrue(weekButton.waitForExistence(timeout: 5))
        weekButton.tap()

        let cardsGrid = app.descendants(matching: .any)["weekOverviewCardsGrid"]
        XCTAssertTrue(cardsGrid.waitForExistence(timeout: 3))

        let stripsButton = app.buttons["weekOverviewMode_strips"]
        XCTAssertTrue(stripsButton.waitForExistence(timeout: 3))
        stripsButton.tap()

        let stripList = app.descendants(matching: .any)["weekOverviewStripList"]
        XCTAssertTrue(stripList.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["weekStripRow_0"].waitForExistence(timeout: 3))

        let collapsedButton = app.buttons["weekOverviewMode_collapsed"]
        XCTAssertTrue(collapsedButton.waitForExistence(timeout: 3))
        collapsedButton.tap()

        let collapsedState = app.descendants(matching: .any)["weekOverviewCollapsedState"]
        XCTAssertTrue(collapsedState.waitForExistence(timeout: 3))

        let cardsButton = app.buttons["weekOverviewMode_cards"]
        XCTAssertTrue(cardsButton.waitForExistence(timeout: 3))
        cardsButton.tap()

        XCTAssertTrue(cardsGrid.waitForExistence(timeout: 3))
    }
}
