package com.weekyii.android.data.repository

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.WeekFields
import java.util.Locale

class WeekCalculator {
    private val isoWeekFields = WeekFields.ISO

    fun weekId(date: LocalDate): String {
        val week = date.get(isoWeekFields.weekOfYear())
        val year = date.get(isoWeekFields.weekBasedYear())
        return String.format(Locale.US, "%04d-W%02d", year, week)
    }

    fun weekRange(date: LocalDate): Pair<LocalDate, LocalDate> {
        val start = date.with(DayOfWeek.MONDAY)
        val end = start.plusDays(6)
        return start to end
    }

    fun weekStartDate(weekId: String): LocalDate? {
        val normalized = weekId.uppercase(Locale.US)
        val parts = normalized.split("-")
        if (parts.size != 2) return null
        val yearPart = parts[0]
        val weekPart = parts[1]
        if (yearPart.length != 4 || weekPart.length != 3 || weekPart.first() != 'W') return null
        val weekNumber = weekPart.drop(1).toIntOrNull() ?: return null
        if (weekNumber !in 1..53) return null
        val year = yearPart.toIntOrNull() ?: return null
        val firstWeek = LocalDate.now().withYear(year).with(isoWeekFields.weekOfYear(), weekNumber.toLong())
        val start = firstWeek.with(DayOfWeek.MONDAY)
        return if (weekId(start) == normalized) start else null
    }
}
