package com.cashu.me.ui.components

import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.VisualTransformation

// The Singular TextField: a filled M3 TextField restyled onto the app's rounded
// shape language — large-radius container on all corners with the underline
// indicator removed (the stock M3 filled field squares the bottom corners
// around an indicator line, which reads foreign next to the app's capsule
// buttons and rounded menus; iOS uses rounded material containers with no
// indicator). Focus still reads through the cursor, label, and container
// tokens; errors read through the error label/supporting text. Every app input
// flows through this so the treatment stays uniform.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CashuTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle = MaterialTheme.typography.bodyLarge,
    label: String? = null,
    placeholder: String? = null,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    supportingText: String? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    minLines: Int = 1,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        // TalkBack announces the field as invalid and reads the reason. Owned
        // here so every field-attached error gets it without the call site
        // remembering to ask.
        modifier = if (isError && supportingText != null) {
            modifier.semantics { error(supportingText) }
        } else {
            modifier
        },
        enabled = enabled,
        readOnly = readOnly,
        textStyle = textStyle,
        label = label?.let { { Text(it) } },
        // Soft placeholder (iOS secondary-ish field hint) — lighter than the
        // default onSurfaceVariant so it recedes behind typed content.
        placeholder = placeholder?.let {
            {
                Text(
                    text = it,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
                )
            }
        },
        leadingIcon = leadingIcon,
        trailingIcon = trailingIcon,
        supportingText = supportingText?.let { { Text(it) } },
        isError = isError,
        visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        singleLine = singleLine,
        minLines = minLines,
        maxLines = maxLines,
        shape = MaterialTheme.shapes.large,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            // With the indicator gone, error state reads through the Material
            // error container + red label/supporting text. Use the role rather
            // than deriving an alpha, so this cannot drift from the notice tint
            // the way the old error.copy(alpha = 0.12f) did.
            errorContainerColor = MaterialTheme.colorScheme.errorContainer,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            errorIndicatorColor = Color.Transparent,
            cursorColor = MaterialTheme.colorScheme.primary,
            focusedLabelColor = MaterialTheme.colorScheme.primary,
            unfocusedLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
            focusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
            unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
        ),
    )
}
