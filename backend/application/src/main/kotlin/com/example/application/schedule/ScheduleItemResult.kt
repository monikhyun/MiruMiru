package com.example.application.schedule

import java.time.Instant

data class ScheduleItemResult(
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
)
