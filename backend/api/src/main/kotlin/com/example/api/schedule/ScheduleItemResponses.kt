package com.example.api.schedule

import com.example.application.schedule.ScheduleItemResult
import java.time.Instant

object ScheduleItemResponses {
    data class Item(
        val itemId: Long,
        val lectureId: Long?,
        val lectureName: String?,
        val type: String,
        val title: String,
        val memo: String?,
        val dueAt: Instant?,
        val completed: Boolean,
        val createdAt: Instant,
        val updatedAt: Instant
    ) {
        companion object {
            fun from(result: ScheduleItemResult): Item {
                return Item(
                    itemId = result.itemId,
                    lectureId = result.lectureId,
                    lectureName = result.lectureName,
                    type = result.type,
                    title = result.title,
                    memo = result.memo,
                    dueAt = result.dueAt,
                    completed = result.completed,
                    createdAt = result.createdAt,
                    updatedAt = result.updatedAt
                )
            }
        }
    }
}
