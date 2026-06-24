package com.example.domain.course

data class CourseReviewSummaryProjection(
    val reviewCount: Long,
    val averageOverall: Double?,
    val averageProfessor: Double?,
    val averageDifficulty: Double?,
    val averageWorkload: Double?,
    val wouldTakeAgainRate: Double?
)
