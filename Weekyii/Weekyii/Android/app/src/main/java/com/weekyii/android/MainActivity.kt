package com.weekyii.android

import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Scaffold
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.SideEffect
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.weekyii.android.ui.navigation.NavItem
import com.weekyii.android.ui.navigation.WeekyiiNavBar
import com.weekyii.android.ui.theme.WeekyiiTheme
import com.weekyii.android.ui.screens.today.TodayScreen
import com.weekyii.android.ui.screens.pending.PendingScreen
import com.weekyii.android.ui.screens.past.PastScreen
import com.weekyii.android.ui.screens.extensions.ExtensionsScreen
import com.weekyii.android.ui.screens.settings.SettingsScreen
import com.weekyii.android.ui.viewmodel.TodayViewModel
import com.weekyii.android.ui.viewmodel.PendingViewModel
import com.weekyii.android.ui.viewmodel.PastViewModel
import com.weekyii.android.ui.viewmodel.ExtensionsViewModel
import com.weekyii.android.ui.viewmodel.SettingsViewModel
import com.weekyii.android.ui.viewmodel.WeekViewModel
import com.weekyii.android.data.repository.WeekCalculator
import com.weekyii.android.data.repository.ProjectRepository
import com.weekyii.android.data.repository.MindStampRepository

/**
 * 临时手动装配（未接入 Hilt），仅为界面跑通。依赖 Room/DB 初始化后应替换为 Application 级单例。
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as WeekyiiApplication
        setContent {
            val themeId by app.settingsStore.themeId.collectAsState()
            val appearanceMode by app.settingsStore.appearanceMode.collectAsState()
            val darkTheme = when (appearanceMode) {
                "light" -> false
                "dark" -> true
                else -> isSystemInDarkTheme()
            }
            WeekyiiTheme(themeId = themeId, darkTheme = darkTheme) {
                val view = LocalView.current
                val backgroundColor = MaterialTheme.colorScheme.background
                SideEffect {
                    val window = (view.context as? Activity)?.window ?: return@SideEffect
                    window.statusBarColor = backgroundColor.toArgb()
                    window.navigationBarColor = backgroundColor.toArgb()
                    WindowCompat.getInsetsController(window, view).apply {
                        isAppearanceLightStatusBars = !darkTheme
                        isAppearanceLightNavigationBars = !darkTheme
                    }
                }
                if (app.startupError != null) {
                    Text(text = app.startupError!!, modifier = Modifier.fillMaxSize())
                    return@WeekyiiTheme
                }
                val navController = rememberNavController()
                val navItems = NavItem.items

                val repo = app.repository
                val timeProvider = app.timeProvider
                val mindStampRepo = remember { MindStampRepository(app.database.mindStampDao()) }

                val todayVm = remember {
                    TodayViewModel(repo, timeProvider, app.appStateStore, app.settingsStore, app.taskTypeDefinitionRepository, mindStampRepo, app.notificationService)
                }
                val pendingVm = remember { PendingViewModel(repo, WeekCalculator(), timeProvider, app.taskTypeDefinitionRepository) }
                val weekVm = remember { WeekViewModel(repo, timeProvider, app.taskTypeDefinitionRepository) }
                val pastVm = remember { PastViewModel(repo) }
                val extVm = remember {
                    ExtensionsViewModel(
                        ProjectRepository(
                            projectDao = app.database.projectDao(),
                            timeProvider = timeProvider,
                            weekDao = app.database.weekDao(),
                            dayDao = app.database.dayDao(),
                            taskDao = app.database.taskDao(),
                            weekCalculator = WeekCalculator(),
                            database = app.database
                        ),
                        mindStampRepo,
                        app.suspendedTaskRepository,
                        app.taskTypeDefinitionRepository,
                        app.settingsStore
                    )
                }
                val settingsVm = remember {
                    SettingsViewModel(app.settingsStore, app.taskTypeDefinitionRepository, app.dataArchiveRepository)
                }

                Scaffold(
                    bottomBar = {
                        val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
                        WeekyiiNavBar(navItems, currentRoute) { route ->
                            navController.navigate(route) {
                                popUpTo(navController.graph.startDestinationId) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                ) { padding ->
                    NavHost(navController, startDestination = NavItem.Today.route) {
                        composable(NavItem.Today.route) { TodayScreen(todayVm, padding, weekVm) }
                        composable(NavItem.Pending.route) { PendingScreen(pendingVm, padding) }
                        composable(NavItem.Past.route) { PastScreen(pastVm, padding) }
                        composable(NavItem.Extensions.route) { ExtensionsScreen(extVm, padding) }
                        composable(NavItem.Settings.route) { SettingsScreen(settingsVm, padding) }
                    }
                }
            }
        }
    }
}
