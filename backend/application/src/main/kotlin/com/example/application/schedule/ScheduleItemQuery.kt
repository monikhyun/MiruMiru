package com.example.application.schedule

import java.time.Instant

data class ScheduleItemQuery(
    val userId: String,
    val from: Instant,
    val to: Instant,
    val status: String
)
