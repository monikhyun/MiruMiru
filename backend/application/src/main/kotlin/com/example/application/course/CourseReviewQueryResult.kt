package com.example.application.course

object CourseReviewQueryResult {
    data class CourseReviewFeedItem(
        val reviewId: Long,
        val targetId: Long,
        val courseId: Long,
        val courseCode: String,
        val courseName: String,
        val professorDisplayName: String,
        val displayName: String,
        val overallRating: Int,
        val professorRating: Int?,
        val difficulty: Int,
        val workload: Int,
        val wouldTakeAgain: Boolean,
        val content: String,
        val professorContent: String?,
        val academicYear: Int,
        val term: String,
        val isMine: Boolean,
        val createdAt: String,
        val updatedAt: String
    )

    data class CourseReviewFeedPage(
        val items: List<CourseReviewFeedItem>,
        val page: Int,
        val size: Int,
        val totalElements: Long,
        val totalPages: Int,
        val hasNext: Boolean
    )

    data class CourseReviewTargetItem(
        val targetId: Long,
        val courseId: Long,
        val courseCode: String,
        val courseName: String,
        val professorDisplayName: String,
        val displayName: String
    )

    data class CourseReviewTargetPage(
        val items: List<CourseReviewTargetItem>,
        val page: Int,
        val size: Int,
        val totalElements: Long,
        val totalPages: Int,
        val hasNext: Boolean
    )

    data class CourseReviewSummary(
        val targetId: Long,
        val courseId: Long,
        val courseCode: String,
        val courseName: String,
        val professorDisplayName: String,
        val displayName: String,
        val reviewCount: Long,
        val averageOverall: Double?,
        val averageProfessor: Double?,
        val averageDifficulty: Double?,
        val averageWorkload: Double?,
        val wouldTakeAgainRate: Double?
    )

    data class CourseReviewItem(
        val reviewId: Long,
        val overallRating: Int,
        val professorRating: Int?,
        val difficulty: Int,
        val workload: Int,
        val wouldTakeAgain: Boolean,
        val content: String,
        val professorContent: String?,
        val academicYear: Int,
        val term: String,
        val professorDisplayName: String,
        val isMine: Boolean,
        val createdAt: String,
        val updatedAt: String
    )

    data class CourseReviewPage(
        val summary: CourseReviewSummary,
        val reviews: List<CourseReviewItem>,
        val page: Int,
        val size: Int,
        val totalElements: Long,
        val totalPages: Int,
        val hasNext: Boolean
    )
}
