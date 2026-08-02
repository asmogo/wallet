package com.cashu.me.ui.components

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Smart relative timestamp matching iOS HistoryView.formatRelativeDate:
 *   < 1 min       → "Now"
 *   same day, < 1h → "$N min ago"
 *   same day, ≥ 1h → "HH:mm"  (e.g. "22:57")
 *   yesterday     → "Yesterday HH:mm"
 *   same year     → "MMM d"   (e.g. "May 22")
 *   older         → "MMM d yyyy"
 */
fun formatRelativeTimestamp(
    epochMillis: Long,
    nowMillis: Long = System.currentTimeMillis(),
    zone: ZoneId = ZoneId.systemDefault(),
    locale: Locale = Locale.getDefault(),
): String {
    val deltaMs = (nowMillis - epochMillis).coerceAtLeast(0)
    if (TimeUnit.MILLISECONDS.toSeconds(deltaMs) < 60) return "Now"

    val nowZoned = Instant.ofEpochMilli(nowMillis).atZone(zone)
    val thenZoned = Instant.ofEpochMilli(epochMillis).atZone(zone)
    val nowDate: LocalDate = nowZoned.toLocalDate()
    val thenDate: LocalDate = thenZoned.toLocalDate()

    val shortTime = DateTimeFormatter.ofPattern("HH:mm", locale)
    val sameYearDate = DateTimeFormatter.ofPattern("MMM d", locale)
    val differentYearDate = DateTimeFormatter.ofPattern("MMM d yyyy", locale)

    return when {
        thenDate == nowDate -> {
            val minutes = TimeUnit.MILLISECONDS.toMinutes(deltaMs)
            if (minutes < 60) "$minutes min ago" else shortTime.format(thenZoned)
        }
        thenDate == nowDate.minusDays(1) -> "Yesterday ${shortTime.format(thenZoned)}"
        thenDate.year == nowDate.year -> sameYearDate.format(thenZoned)
        else -> differentYearDate.format(thenZoned)
    }
}

/**
 * Abbreviated relative recency matching iOS RelativeDateTimeFormatter(.abbreviated),
 * used for "Updated X ago" beside the BTC price. Always relative (never clock or
 * calendar dates) so stale values stay accurate:
 *   0 s     → "now"
 *   < 1 min → "N sec ago"
 *   < 1 hr  → "N min ago"
 *   < 1 day → "N hr ago"
 *   < 1 wk  → "N day(s) ago"
 *   < 1 mo  → "N wk ago"
 *   < 1 yr  → "N mo ago"
 *   else    → "N yr ago"
 * Future timestamps (clock skew) clamp to "now".
 */
fun formatRelativeRecency(
    epochMillis: Long,
    nowMillis: Long = System.currentTimeMillis(),
    zone: ZoneId = ZoneId.systemDefault(),
): String {
    val then = Instant.ofEpochMilli(epochMillis).atZone(zone)
    val now = Instant.ofEpochMilli(nowMillis.coerceAtLeast(epochMillis)).atZone(zone)

    var cursor = then
    val years = ChronoUnit.YEARS.between(cursor, now)
    cursor = cursor.plusYears(years)
    val months = ChronoUnit.MONTHS.between(cursor, now)
    cursor = cursor.plusMonths(months)
    val days = ChronoUnit.DAYS.between(cursor, now)
    cursor = cursor.plusDays(days)
    val hours = ChronoUnit.HOURS.between(cursor, now)
    cursor = cursor.plusHours(hours)
    val minutes = ChronoUnit.MINUTES.between(cursor, now)
    cursor = cursor.plusMinutes(minutes)
    val seconds = ChronoUnit.SECONDS.between(cursor, now)

    fun ago(value: Long, singular: String, plural: String = singular): String =
        "$value ${if (value == 1L) singular else plural} ago"

    return when {
        years > 0 -> ago(years, "yr")
        months > 0 -> ago(months, "mo")
        days >= 7 -> ago(days / 7, "wk")
        days > 0 -> ago(days, "day", "days")
        hours > 0 -> ago(hours, "hr")
        minutes > 0 -> ago(minutes, "min")
        seconds > 0 -> ago(seconds, "sec")
        else -> "now"
    }
}
