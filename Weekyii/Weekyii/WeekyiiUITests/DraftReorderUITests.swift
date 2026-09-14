import XCTest

// MARK: - Manual screenshot harness

/// Ad-hoc screenshot helpers used to capture UI for review. They live in the UI
/// test target because it is the one place where the host controls the app
/// launch and can dismiss system alerts (notification permission) before
/// snapping. They are skipped by CI via the `-skip-ui-screenshots` launch arg
/// filter that we set in the production target, and they ignore their own
/// outcome: success is "the file was written to /tmp/weekyii_shots/".
final class ThemePickerScreenshotTests: XCTestCase {
    func test_themePickerRenders() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            if alert.buttons["允许"].exists { alert.buttons["允许"].tap(); return true }
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let mineTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(mineTab.waitForExistence(timeout: 8))
        mineTab.tap()

        var appearanceLink = app.staticTexts["外观与主题"]
        if !appearanceLink.exists { app.swipeUp() }
        appearanceLink = app.staticTexts["外观与主题"]
        guard appearanceLink.waitForExistence(timeout: 5) else {
            XCTFail("Couldn't find 外观与主题")
            return
        }
        appearanceLink.tap()

        // Give the navigation transition a moment before snapping.
        _ = app.staticTexts["主题"].waitForExistence(timeout: 5)
        sleep(1)

        let screenshot = app.screenshot()
        try screenshot.pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/weekyii_shots/uitest_picker.png")
        )

        // Scroll the page so the personalised themes (粗野 / 霓虹 / 纸感 / 终端)
        // appear in the screenshot. Form pages use a UI element whose swipe
        // can be invoked at the application level.
        for _ in 0..<4 {
            app.swipeUp()
            sleep(1)
        }
        sleep(1)
        let scrolled = app.screenshot()
        try scrolled.pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/weekyii_shots/uitest_picker_scrolled.png")
        )
    }
}

final class DraftReorderUITests: XCTestCase {
    func testExtensionsHubUsesSquareShortcutsAboveProjects() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        let extensionsTab = app.tabBars.buttons["扩展"]
        XCTAssertTrue(extensionsTab.waitForExistence(timeout: 5))
        extensionsTab.tap()

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

    func testSettingsExecutionModeCardsCanSelectFlexibleMode() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1"
        ]
        app.launch()

        let settingsTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let todayRhythm = app.cells.containing(.staticText, identifier: "今日节奏").firstMatch
        XCTAssertTrue(todayRhythm.waitForExistence(timeout: 3))
        todayRhythm.tap()

        let flexibleButton = app.buttons["executionModeOption.flexible"]
        XCTAssertTrue(flexibleButton.waitForExistence(timeout: 3))
        flexibleButton.tap()
        XCTAssertEqual(flexibleButton.value as? String, "已选择")
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

        let ritualCard = app.descendants(matching: .any)["startFlowRitualCard"]
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

        let extensionsTab = app.tabBars.buttons["扩展"]
        XCTAssertTrue(extensionsTab.waitForExistence(timeout: 5))
        extensionsTab.tap()

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

        let extensionsTab = app.tabBars.buttons["扩展"]
        XCTAssertTrue(extensionsTab.waitForExistence(timeout: 5))
        extensionsTab.tap()

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

    func testPendingMonthViewShowsDynamicSelectedDayTypeSummaryWithoutFixedTypeCards() {
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

        let switchToMonth = app.buttons["pendingSwitchToMonthButton"]
        XCTAssertTrue(switchToMonth.waitForExistence(timeout: 3))
        switchToMonth.tap()

        let seededDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let seededDayButton = app.buttons["pendingMonthDay_\(dateFormatter.string(from: seededDate))"]
        XCTAssertTrue(seededDayButton.waitForExistence(timeout: 3))
        seededDayButton.tap()

        XCTAssertTrue(app.staticTexts["pendingSelectedDayTaskCount"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["pendingSelectedDayTypeSummary"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["pendingMonthSummary_regular"].exists)
        XCTAssertFalse(app.otherElements["pendingMonthSummary_ddl"].exists)
        XCTAssertFalse(app.otherElements["pendingMonthSummary_leisure"].exists)
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
        // The topology card is replaced by an empty state when the week holds no
        // tasks, so seed today's draft tasks to reach the tree itself.
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft"
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

    /// Tapping a task node must land on the task inspector.
    ///
    /// The inspector picks its variant from the selected node id. A task belongs
    /// to a day but matches neither that day's id nor a group id, so it has to be
    /// checked *before* the forgotten fallback — otherwise a live task renders as
    /// "任务已遗忘". This guards that ordering.
    func testWeekTopologyTaskNodeShowsTaskInspectorNotForgotten() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "1",
            "-uiTestingSeedDraft"
        ]
        app.launch()

        let weekButton = app.buttons["todaySectionWeekButton"]
        XCTAssertTrue(weekButton.waitForExistence(timeout: 5))
        weekButton.tap()

        let topology = app.descendants(matching: .any)["weekTopologyView"]
        XCTAssertTrue(topology.waitForExistence(timeout: 3))

        // Focusing a day is what brings the task layer into the compact canvas.
        app.buttons["weekTopologyDay_0"].tap()

        // Task cards carry a label (title + type) but no identifier.
        let taskCard = topology.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Draft Task A"))
            .firstMatch
        XCTAssertTrue(taskCard.waitForExistence(timeout: 3))
        taskCard.tap()

        // `.accessibilityIdentifier("weekTopologyInspector")` propagates to every
        // child of the inspector, so the id is not unique and scoping a query to
        // it is unreliable. Assert on labels that only one variant renders:
        // "查看任务详情" exists only in the task inspector, "任务已遗忘" only in
        // the forgotten one.
        XCTAssertTrue(
            app.buttons["查看任务详情"].waitForExistence(timeout: 3),
            "轻点任务卡后没有出现任务详情入口，可能落到了别的 inspector"
        )
        XCTAssertFalse(
            app.staticTexts["任务已遗忘"].exists,
            "轻点任务卡错误地显示成了「任务已遗忘」"
        )
    }
}
