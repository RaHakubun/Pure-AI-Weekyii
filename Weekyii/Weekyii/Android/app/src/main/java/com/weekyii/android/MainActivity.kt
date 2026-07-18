package com.weekyii.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
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
import com.weekyii.android.data.repository.WeekCalculator
import com.weekyii.android.data.repository.WeekyiiRepository
import com.weekyii.android.domain.DefaultTimeProvider
import com.weekyii.android.domain.StateMachine
import com.weekyii.android.domain.InMemoryAppStateStore
import com.weekyii.android.domain.TimeProvider
import com.weekyii.android.ui.viewmodel.TodayViewModel
import com.weekyii.android.ui.viewmodel.PendingViewModel
import com.weekyii.android.ui.viewmodel.PastViewModel
import com.weekyii.android.ui.viewmodel.ExtensionsViewModel
import com.weekyii.android.ui.viewmodel.SettingsViewModel

/**
 * 临时手动装配（未接入 Hilt），仅为界面跑通。依赖 Room/DB 初始化后应替换为 Application 级单例。
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WeekyiiTheme {
                val navController = rememberNavController()
                val navItems = NavItem.items

                // TODO: 替换为真正的 Room 实例
                val dummyRepo = remember { StubRepoFactory.makeRepository(applicationContext) }
                val timeProvider: TimeProvider = remember { DefaultTimeProvider() }
                val appState = remember { InMemoryAppStateStore() }
                remember { StateMachine(dummyRepo, timeProvider, appState) }.processStateTransitions()

                val todayVm = remember { TodayViewModel(dummyRepo, timeProvider) }
                val pendingVm = remember { PendingViewModel(dummyRepo, WeekCalculator(), timeProvider) }
                val pastVm = remember { PastViewModel(dummyRepo) }
                val extVm = remember { ExtensionsViewModel() }
                val settingsVm = remember { SettingsViewModel() }

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
                        composable(NavItem.Today.route) { TodayScreen(todayVm, padding) }
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

// --- 临时仓库工厂：无 Room 环境下占位，方便界面代码编译 ---
object StubRepoFactory {
    fun makeRepository(context: android.content.Context): WeekyiiRepository {
        throw IllegalStateException("Room 数据库尚未初始化，请接入实际 DB")
    }
}
