package com.example.application.schedule

import java.time.Instant

object ScheduleItemCommand {
    data class Create(
        val userId: String,
        val lectureId: Long?,
        val type: String,
        val title: String,
        val memo: String?,
        val dueAt: Instant?,
        val completed: Boolean?
    )

    data class Update(
        val userId: String,
        val itemId: Long,
        val lectureId: Long?,
        val type: String,
        val title: String,
        val memo: String?,
        val dueAt: Instant?,
        val completed: Boolean?
    )

    data class UpdateCompletion(
        val userId: String,
        val itemId: Long,
        val completed: Boolean
    )

    data class Delete(
        val userId: String,
        val itemId: Long
    )
}
