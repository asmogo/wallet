package com.cashu.me.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.cashu.me.R
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/**
 * Third-party notices.
 *
 * The SIL Open Font License requires the copyright notice and licence text to
 * travel with the font, so bundling Geist obliges the app to surface this. The
 * text is read from `res/raw` rather than `assets` so it is R-referenced and
 * cannot be dropped by resource shrinking without the build failing first.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LicensesScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val oflGeist = remember {
        context.resources.openRawResource(R.raw.ofl_geist)
            .bufferedReader()
            .use { it.readText() }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Licenses", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(
                            Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = CashuTheme.spacing.comfortable),
        ) {
            SectionHeader("Geist")
            Text(
                text = "Geist and Geist Mono set every surface of this wallet. " +
                    "Copyright © 2023 Vercel, Inc.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = oflGeist,
                // The licence is a legal text, not prose the reader is being
                // invited into: set it small, quiet, and monospaced so it is
                // legible and unmistakably not app copy.
                style = CashuTheme.type.monoCaption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = CashuTheme.spacing.comfortable),
            )
        }
    }
}
