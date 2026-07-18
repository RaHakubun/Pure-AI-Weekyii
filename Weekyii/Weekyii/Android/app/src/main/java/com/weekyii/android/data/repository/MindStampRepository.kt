package com.weekyii.android.data.repository

import com.weekyii.android.data.db.dao.MindStampDao
import com.weekyii.android.data.db.entities.MindStampEntity
import com.weekyii.android.ui.model.MindStampUi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.UUID

class MindStampRepository(private val dao: MindStampDao) {
    fun observeAll(): Flow<List<MindStampUi>> = dao.observeAll().map { stamps -> stamps.map { it.toUi() } }

    suspend fun random(): MindStampUi? = dao.allMindStamps().filter { it.hasContent }.randomOrNull()?.toUi()

    suspend fun create(text: String, imageBlob: ByteArray?): UUID {
        require(text.isNotBlank() || imageBlob != null) { "MindStamp needs text or an image" }
        val stamp = MindStampEntity(text = text.trim(), imageBlob = imageBlob)
        dao.upsert(stamp)
        return stamp.id
    }

    suspend fun delete(id: UUID) {
        val stamp = dao.findById(id) ?: return
        dao.delete(stamp)
    }
}

private fun MindStampEntity.toUi() = MindStampUi(
    id = id,
    text = text,
    imageBlob = imageBlob,
    createdAt = createdAt.toInstant().atZone(java.time.ZoneId.systemDefault()).toLocalDateTime()
)
