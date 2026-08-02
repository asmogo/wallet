package com.cashu.me.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

class RelativeTimeTest {

    private val zone: ZoneId = ZoneId.of("UTC")
    private val now: ZonedDateTime = Instant.parse("2026-08-02T12:00:00Z").atZone(zone)
    private val nowMillis = now.toInstant().toEpochMilli()

    private fun recency(ageMillis: Long): String =
        formatRelativeRecency(nowMillis - ageMillis, nowMillis, zone)

    @Test
    fun zeroAgeReadsNow() {
        assertEquals("now", recency(0))
    }

    @Test
    fun futureTimestampClampsToNow() {
        assertEquals("now", recency(-TimeUnit.MINUTES.toMillis(5)))
    }

    @Test
    fun secondsAgo() {
        assertEquals("1 sec ago", recency(TimeUnit.SECONDS.toMillis(1)))
        assertEquals("45 sec ago", recency(TimeUnit.SECONDS.toMillis(45)))
    }

    @Test
    fun minutesAgo() {
        assertEquals("1 min ago", recency(TimeUnit.MINUTES.toMillis(1)))
        assertEquals("5 min ago", recency(TimeUnit.MINUTES.toMillis(5)))
        assertEquals("59 min ago", recency(TimeUnit.MINUTES.toMillis(59)))
    }

    @Test
    fun hoursAgo() {
        assertEquals("1 hr ago", recency(TimeUnit.MINUTES.toMillis(90)))
        assertEquals("2 hr ago", recency(TimeUnit.HOURS.toMillis(2)))
    }

    @Test
    fun daysAgo() {
        assertEquals("1 day ago", recency(TimeUnit.HOURS.toMillis(25)))
        assertEquals("6 days ago", recency(TimeUnit.DAYS.toMillis(6)))
    }

    @Test
    fun weeksAgo() {
        assertEquals("1 wk ago", recency(TimeUnit.DAYS.toMillis(13)))
        assertEquals("3 wk ago", recency(TimeUnit.DAYS.toMillis(27)))
    }

    @Test
    fun monthsAgo() {
        assertEquals("1 mo ago", recency(TimeUnit.DAYS.toMillis(40)))
        assertEquals("2 mo ago", recency(TimeUnit.DAYS.toMillis(75)))
    }

    @Test
    fun yearsAgo() {
        assertEquals("1 yr ago", recency(TimeUnit.DAYS.toMillis(400)))
    }

    @Test
    fun stalePriceTimestampStaysAccurate() {
        val stale = formatRelativeRecency(
            epochMillis = nowMillis - TimeUnit.HOURS.toMillis(2),
            nowMillis = nowMillis,
            zone = zone,
        )
        assertEquals("2 hr ago", stale)
    }
}
