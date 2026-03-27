package com.luma3.ptt_watch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                PttScreen(autoRecordOnLaunch = intent.getBooleanExtra(EXTRA_AUTO_RECORD, false))
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    companion object {
        const val EXTRA_AUTO_RECORD = "auto_record"

        fun hasRecordAudioPermission(context: Context): Boolean {
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        }
    }
}

@Composable
private fun PttScreen(
    autoRecordOnLaunch: Boolean,
    viewModel: PttViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    val backgroundColor = when (uiState.status) {
        PttStatus.Idle -> Color.Black
        PttStatus.Recording -> Color(0x88FF0000)
        PttStatus.Thinking -> Color(0x880064FF)
        PttStatus.Speaking -> Color(0x8800C853)
        PttStatus.Error -> Color(0x88FF8C00)
    }

    var hasPermission by remember { mutableStateOf(MainActivity.hasRecordAudioPermission(context)) }
    var shouldAutoRecord by remember { mutableStateOf(autoRecordOnLaunch) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
        if (granted && shouldAutoRecord) {
            viewModel.startRecordingIfIdle()
            shouldAutoRecord = false
        }
    }

    LaunchedEffect(autoRecordOnLaunch, hasPermission) {
        if (!autoRecordOnLaunch || !shouldAutoRecord) return@LaunchedEffect
        if (hasPermission) {
            viewModel.startRecordingIfIdle()
            shouldAutoRecord = false
        } else {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundColor)
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = uiState.status.label,
                color = Color.White,
                textAlign = TextAlign.Center,
                fontSize = 13.sp,
                modifier = Modifier.padding(top = 4.dp)
            )

            BoxWithConstraints(
                contentAlignment = Alignment.Center,
                modifier = Modifier.weight(1f)
            ) {
                val diameter = maxWidth * 0.4f
                Button(
                    onClick = {
                        hasPermission = MainActivity.hasRecordAudioPermission(context)
                        if (!hasPermission) {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        } else {
                            viewModel.onMicTap()
                        }
                    },
                    modifier = Modifier.size(diameter),
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = Color.White,
                        contentColor = Color.Black
                    )
                ) {
                    Icon(
                        imageVector = if (uiState.status == PttStatus.Recording) Icons.Filled.Stop else Icons.Filled.Mic,
                        contentDescription = null
                    )
                }
            }

            Box(
                modifier = Modifier
                    .height(56.dp)
                    .verticalScroll(rememberScrollState()),
                contentAlignment = Alignment.TopCenter
            ) {
                Text(
                    text = when {
                        uiState.status == PttStatus.Recording && uiState.partialText.isNotEmpty() -> uiState.partialText
                        uiState.status == PttStatus.Thinking && uiState.partialText.isNotEmpty() -> "\"${uiState.partialText}\""
                        else -> uiState.lastReply
                    },
                    color = if (uiState.status == PttStatus.Recording) Color(0xFFFFCCCC) else Color.White,
                    maxLines = 3,
                    textAlign = TextAlign.Center,
                    fontSize = 12.sp
                )
            }
        }
    }
}
