package com.weekyii.android.data.db

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE days ADD COLUMN follows_default_kill_time INTEGER NOT NULL DEFAULT 1")
        db.execSQL("ALTER TABLE days ADD COLUMN execution_mode_raw TEXT NOT NULL DEFAULT 'strict'")
        db.execSQL("ALTER TABLE days ADD COLUMN is_draft_zone_unlocked INTEGER NOT NULL DEFAULT 0")
        db.execSQL("ALTER TABLE tasks ADD COLUMN task_type_id_raw TEXT NOT NULL DEFAULT 'regular'")
        db.execSQL("ALTER TABLE projects ADD COLUMN tile_size_raw TEXT NOT NULL DEFAULT 'medium'")
        db.execSQL("ALTER TABLE projects ADD COLUMN tile_order INTEGER NOT NULL DEFAULT 0")

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS task_type_definitions (
                id_raw TEXT NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                icon_name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                base_kind TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                is_built_in INTEGER NOT NULL,
                is_archived INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS suspended_tasks (
                id TEXT NOT NULL PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                task_type TEXT NOT NULL,
                task_type_id_raw TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                decision_deadline INTEGER NOT NULL,
                preferred_countdown_days INTEGER NOT NULL,
                snooze_count INTEGER NOT NULL,
                status TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS suspended_task_steps (
                stepId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                title TEXT NOT NULL,
                is_completed INTEGER NOT NULL,
                sort_order INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                suspended_task_owner_id TEXT NOT NULL,
                FOREIGN KEY(suspended_task_owner_id) REFERENCES suspended_tasks(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS index_suspended_task_steps_suspended_task_owner_id ON suspended_task_steps(suspended_task_owner_id)")
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS suspended_task_attachments (
                attachmentId INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                data BLOB,
                file_name TEXT NOT NULL,
                file_type TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                suspended_task_owner_id TEXT NOT NULL,
                FOREIGN KEY(suspended_task_owner_id) REFERENCES suspended_tasks(id) ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS index_suspended_task_attachments_suspended_task_owner_id ON suspended_task_attachments(suspended_task_owner_id)")
    }
}
