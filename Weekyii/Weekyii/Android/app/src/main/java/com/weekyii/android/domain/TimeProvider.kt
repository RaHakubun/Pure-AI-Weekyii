package com.weekyii.android.domain

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date

interface TimeProvider {
    val nowInstant: Instant
    val now: Date get() = Date.from(nowInstant)
    val today: LocalDate get() = nowInstant.atZone(zoneId).toLocalDate()
    val zoneId: ZoneId
    val currentWeekId: String
}

class DefaultTimeProvider(private val zone: ZoneId = ZoneId.systemDefault()) : TimeProvider {
    override val zoneId: ZoneId = zone
    override val nowInstant: Instant get() = Instant.now()
    override val currentWeekId: String
        get() {
            val date = today
            val week = date.get(java.time.temporal.WeekFields.ISO.weekOfYear())
            val year = date.get(java.time.temporal.WeekFields.ISO.weekBasedYear())
            return String.format("%04d-W%02d", year, week)
        }
}
