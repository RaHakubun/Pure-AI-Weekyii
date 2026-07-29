import XCTest
import UIKit

final class DraftReorderUITests: XCTestCase {
    private func selectModule(_ title: String, sidebarID: String, in app: XCUIApplication) {
        let tabButton = app.tabBars.buttons[title]
        if tabButton.waitForExistence(timeout: 1) {
            tabButton.tap()
            return
        }

        let sidebarItem = app.descendants(matching: .any)[sidebarID]
        if sidebarItem.waitForExistence(timeout: 1) {
            sidebarItem.tap()
            return
        }

        let workspaceID: String
        switch sidebarID {
        case "mainSidebar_pending":
            workspaceID = "workspaceRoute_pending"
        case "mainSidebar_settings":
            workspaceID = "workspaceRoute_settings"
        case "mainSidebar_extensions":
            workspaceID = "workspaceRoute_projects"
        default:
            workspaceID = sidebarID
        }
        let workspaceItem = app.descendants(matching: .any)[workspaceID]
        XCTAssertTrue(workspaceItem.waitForExistence(timeout: 5))
        workspaceItem.tap()
    }

    func testExtensionsHubUsesSquareShortcutsAboveProjects() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        selectModule("扩展", sidebarID: "mainSidebar_extensions", in: app)

        let mindStamps = app.buttons["extensionsMindStampsSeeAllButton"]
        let suspended = app.buttons["extensionsSuspendedSeeAllButton"]
        let projects = app.buttons["extensionsProjectsSeeAllButton"]
        XCTAssertTrue(mindStamps.waitForExistence(timeout: 5))
        XCTAssertTrue(suspended.waitForExistence(timeout: 5))
        XCTAssertTrue(projects.waitForExistence(timeout: 5))

        let mindFrame = mindStamps.frame
        let suspendedFrame = suspended.frame
        let projectsFrame = projects.frame
        let tolerance: CGFloat = 3

        XCTAssertEqual(mindFrame.minY, suspendedFrame.minY, accuracy: tolerance)
        XCTAssertEqual(mindFrame.width, suspendedFrame.width, accuracy: tolerance)
        XCTAssertEqual(mindFrame.height, suspendedFrame.height, accuracy: tolerance)
        XCTAssertEqual(mindFrame.width, mindFrame.height, accuracy: tolerance)
        XCTAssertGreaterThan(projectsFrame.minY, max(mindFrame.maxY, suspendedFrame.maxY))
    }

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

    func testFlexibleExecutionUnlockEnablesQueueEditingAndExchange() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedFlexibleExecution",
            "1"
        ]
        app.launch()

        let lockButton = app.buttons["executionQueueLockButton"]
        let exchangeButton = app.buttons["focusExchangeButton"]
        let addButton = app.buttons["draftAddButton"]
        let editButton = app.buttons["draftEditButton"]

        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        XCTAssertEqual(lockButton.label, "解冻草稿区")
        XCTAssertEqual(lockButton.value as? String, "冻结")
        XCTAssertTrue(exchangeButton.waitForExistence(timeout: 3))
        XCTAssertFalse(exchangeButton.isEnabled)
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertFalse(editButton.isEnabled)
        XCTAssertTrue(lockButton.isHittable)

        lockButton.tap()

        XCTAssertEqual(lockButton.label, "冻结草稿区")
        XCTAssertEqual(lockButton.value as? String, "解冻")
        XCTAssertTrue(exchangeButton.isEnabled)
        XCTAssertTrue(addButton.isEnabled)
        XCTAssertTrue(editButton.isEnabled)
        XCTAssertTrue(addButton.isHittable)
        XCTAssertTrue(editButton.isHittable)
    }

    func testFlexibleExecutionExchangeSwapsFirstQueueTaskIntoFocus() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedFlexibleExecution",
            "1"
        ]
        app.launch()

        let lockButton = app.buttons["executionQueueLockButton"]
        let exchangeButton = app.buttons["focusExchangeButton"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        lockButton.tap()
        XCTAssertTrue(exchangeButton.waitForExistence(timeout: 3))
        exchangeButton.tap()

        XCTAssertTrue(app.staticTexts["Flexible Queue Task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["draftTaskTitle_0"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["draftTaskTitle_0"].label, "Flexible Focus Task")
    }

    func testSettingsExecutionModePickerCanSelectFlexibleMode() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        selectModule("我的", sidebarID: "mainSidebar_settings", in: app)

        let picker = app.segmentedControls["executionModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        let flexibleButton = picker.buttons["灵动模式"]
        XCTAssertTrue(flexibleButton.exists)
        flexibleButton.tap()
        XCTAssertTrue(flexibleButton.isSelected)
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

        selectModule("扩展", sidebarID: "mainSidebar_extensions", in: app)

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

        let mindStampsToolbarCreate = app.buttons["mindstampsToolbarCreateButton"]
        XCTAssertTrue(mindStampsToolbarCreate.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mindstampsFooterCreateButton"].exists)
    }

    func testMindStampsPageShowsToolbarCreateAndDeleteConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        selectModule("扩展", sidebarID: "mainSidebar_extensions", in: app)

        let mindStampsSeeAll = app.buttons["extensionsMindStampsSeeAllButton"]
        XCTAssertTrue(mindStampsSeeAll.waitForExistence(timeout: 5))
        mindStampsSeeAll.tap()

        XCTAssertTrue(app.navigationBars["呆胶布"].waitForExistence(timeout: 3))

        let toolbarCreateButton = app.buttons["mindstampsToolbarCreateButton"]
        XCTAssertTrue(toolbarCreateButton.waitForExistence(timeout: 5))
        toolbarCreateButton.tap()

        let editorTextField = app.textFields["mindstampEditorTextField"]
        XCTAssertTrue(editorTextField.waitForExistence(timeout: 3))
        editorTextField.tap()
        editorTextField.typeText("测试呆胶布")

        let saveButton = app.buttons["mindstampEditorSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.tap()

        let itemCard = app.buttons["mindstampItemCard_0"]
        let itemMeta = app.staticTexts["mindstampItemMeta_0"]
        XCTAssertTrue(itemCard.waitForExistence(timeout: 5))
        XCTAssertTrue(itemMeta.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["测试呆胶布"].exists)

        itemCard.tap()
        XCTAssertTrue(app.navigationBars["编辑呆胶布"].waitForExistence(timeout: 3))
        let cancelEditButton = app.buttons["取消"]
        XCTAssertTrue(cancelEditButton.waitForExistence(timeout: 2))
        cancelEditButton.tap()

        let stampDeleteButton = app.buttons["mindstampDeleteButton_0"]
        XCTAssertTrue(stampDeleteButton.waitForExistence(timeout: 5))
        stampDeleteButton.tap()

        let confirmDeleteButton = app.alerts.buttons["删除"]
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 3))
        confirmDeleteButton.tap()

        XCTAssertFalse(app.buttons["mindstampDeleteButton_0"].waitForExistence(timeout: 3))
    }

    func testMindStampsEmptyStateExplainsToolbarCreateAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        selectModule("扩展", sidebarID: "mainSidebar_extensions", in: app)

        let mindStampsSeeAll = app.buttons["extensionsMindStampsSeeAllButton"]
        XCTAssertTrue(mindStampsSeeAll.waitForExistence(timeout: 5))
        mindStampsSeeAll.tap()

        let toolbarCreateButton = app.buttons["mindstampsToolbarCreateButton"]
        XCTAssertTrue(toolbarCreateButton.waitForExistence(timeout: 5))

        let hintLabel = app.staticTexts["mindstampEmptyCreateHint"]
        XCTAssertTrue(hintLabel.waitForExistence(timeout: 3))
        XCTAssertEqual(hintLabel.label, "右上角点 + 新建呆胶布")
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

        selectModule("未来", sidebarID: "mainSidebar_pending", in: app)

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

        selectModule("扩展", sidebarID: "mainSidebar_extensions", in: app)

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

        let topology = app.descendants(matching: .any)["weekTopologyView"]
        XCTAssertTrue(topology.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["weekTopologyDay_0"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["weekTopologyDay_6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["weekTopologyInspector"].waitForExistence(timeout: 3))

        app.buttons["weekTopologyDay_0"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weekTopologyInspector"].exists)

        let fullScreenButton = app.buttons["weekTopologyFullscreenButton"]
        XCTAssertTrue(fullScreenButton.waitForExistence(timeout: 3))
        fullScreenButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weekTopologyFullscreen"].waitForExistence(timeout: 3))
        let closeFullScreen = app.buttons["weekTopologyFullscreenCloseButton"]
        XCTAssertTrue(closeFullScreen.waitForExistence(timeout: 3))
        closeFullScreen.tap()

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

final class IPadLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad responsive layout tests require an iPad destination.")
        }
    }

    func testRegularWidthUsesSidebarAndTodayColumns() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft",
            "1"
        ]
        app.launch()

        let sidebar = app.descendants(matching: .any)["workspaceSidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["todayHeroStage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["todayTaskColumn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["todayAuxiliaryColumn"].waitForExistence(timeout: 5))
    }

    func testRotationKeepsSelectedModule() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        let pendingItem = app.descendants(matching: .any)["workspaceRoute_pending"]
        XCTAssertTrue(pendingItem.waitForExistence(timeout: 5))
        pendingItem.tap()
        XCTAssertTrue(app.buttons["pendingToolbarAddButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["pendingHeroStage"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.buttons["pendingToolbarAddButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workspaceRoute_pending"].exists)
    }

    func testWorkspaceElevatesPlanningAndReflectionDestinations() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "1"]
        app.launch()

        for route in ["projects", "suspended", "insights", "mindStamps"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["workspaceRoute_\(route)"]
                    .waitForExistence(timeout: 5)
            )
        }

        app.descendants(matching: .any)["workspaceRoute_projects"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["projectsHeroStage"].waitForExistence(timeout: 5))

        app.descendants(matching: .any)["workspaceRoute_insights"].tap()
        XCTAssertTrue(app.staticTexts["洞察"].waitForExistence(timeout: 5))
    }

    func testCommandSearchAndInspectorStayInWorkspace() {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "1"]
        app.launch()

        let searchButton = app.buttons["workspaceCommandSearch"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workspaceSearch"].waitForExistence(timeout: 5))

        let inspectorButton = app.buttons["workspaceInspectorButton"]
        if inspectorButton.waitForExistence(timeout: 2) {
            inspectorButton.tap()
            XCTAssertTrue(app.descendants(matching: .any)["workspaceInspector"].waitForExistence(timeout: 5))
        }
    }
}
