package com.weekyii.android.ui.screens.extensions

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.weekyii.android.ui.viewmodel.ExtensionsViewModel

@Composable
fun ExtensionsScreen(viewModel: ExtensionsViewModel, padding: PaddingValues) {
    Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
        Text("拓展：项目 / MindStamp 等功能待接入")
    }
}
