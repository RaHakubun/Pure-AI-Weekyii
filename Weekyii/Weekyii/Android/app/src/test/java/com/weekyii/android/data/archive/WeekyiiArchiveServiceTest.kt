package com.weekyii.android.data.archive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WeekyiiArchiveServiceTest {
    @Test
    fun encodedArchiveRoundTripsAndReportsCounts() {
        val payload = WeekyiiArchiveService.Payload(
            weeks = listOf(WeekyiiArchiveService.WeekRecord("2026-W30", 0, 6, "present")),
            days = listOf(WeekyiiArchiveService.DayRecord("2026-07-20", "2026-W30", 0, "MON", "draft", 20, 0)),
            tasks = listOf(
                WeekyiiArchiveService.TaskRecord(
                    id = "task-1",
                    dayId = "2026-07-20",
                    title = "Write",
                    taskType = "regular",
                    taskTypeIdRaw = "regular",
                    order = 1,
                    zone = "draft"
                )
            ),
            projects = listOf(WeekyiiArchiveService.ProjectRecord("project-1", "Weekyii", "planning", 0, 1)),
            taskTypes = listOf(WeekyiiArchiveService.TaskTypeRecord("regular", "常规", "check_circle", "#4A90A4", "regular", 0, true, false))
        )

        val archive = WeekyiiArchiveService.encode(payload, exportedAt = 1_000)
        val inspection = WeekyiiArchiveService.inspect(archive)

        assertEquals(1, inspection.weekCount)
        assertEquals(1, inspection.dayCount)
        assertEquals(1, inspection.taskCount)
        assertEquals(1, inspection.projectCount)
        assertEquals(1, inspection.taskTypeCount)
    }

    @Test
    fun tamperedPayloadIsRejectedByChecksum() {
        val archive = WeekyiiArchiveService.encode(WeekyiiArchiveService.Payload())
        val text = archive.decodeToString()
        val payloadStart = text.indexOf("\"payload\":\"") + "\"payload\":\"".length
        val replacement = if (text[payloadStart] == 'A') 'B' else 'A'
        val tampered = text.replaceRange(payloadStart, payloadStart + 1, replacement.toString()).encodeToByteArray()

        assertThrows(WeekyiiArchiveException.ChecksumMismatch::class.java) {
            WeekyiiArchiveService.inspect(tampered)
        }
    }

    @Test
    fun duplicateIdsAndDanglingReferencesAreRejected() {
        val duplicateWeeks = WeekyiiArchiveService.Payload(
            weeks = listOf(
                WeekyiiArchiveService.WeekRecord("same", 0, 1, "present"),
                WeekyiiArchiveService.WeekRecord("same", 0, 1, "past")
            )
        )
        assertThrows(WeekyiiArchiveException.InvalidData::class.java) {
            WeekyiiArchiveService.inspect(WeekyiiArchiveService.encode(duplicateWeeks))
        }

        val danglingDay = WeekyiiArchiveService.Payload(
            days = listOf(WeekyiiArchiveService.DayRecord("2026-07-20", "missing", 0, "MON", "draft", 20, 0))
        )
        assertThrows(WeekyiiArchiveException.InvalidData::class.java) {
            WeekyiiArchiveService.inspect(WeekyiiArchiveService.encode(danglingDay))
        }
    }

    @Test
    fun invalidKillTimeIsRejected() {
        val invalid = WeekyiiArchiveService.Payload(
            days = listOf(WeekyiiArchiveService.DayRecord("2026-07-20", null, 0, "MON", "draft", 24, 0))
        )

        assertThrows(WeekyiiArchiveException.InvalidData::class.java) {
            WeekyiiArchiveService.inspect(WeekyiiArchiveService.encode(invalid))
        }
    }

    @Test
    fun unsupportedFormatVersionIsRejectedBeforePayloadImport() {
        val archive = WeekyiiArchiveService.encode(WeekyiiArchiveService.Payload()).decodeToString()
        val future = archive.replace("\"formatVersion\":1", "\"formatVersion\":99").encodeToByteArray()

        assertThrows(WeekyiiArchiveException.UnsupportedVersion::class.java) {
            WeekyiiArchiveService.inspect(future)
        }
    }
}
