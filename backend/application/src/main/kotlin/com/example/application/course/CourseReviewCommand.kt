package com.example.application.course

object CourseReviewCommand {
    data class CreateCourseReview(
        val userId: String,
        val targetId: Long,
        val academicYear: Int,
        val term: String,
        val overallRating: Int,
        val professorRating: Int,
        val difficulty: Int,
        val workload: Int,
        val wouldTakeAgain: Boolean,
        val content: String,
        val professorContent: String?
    )

    data class UpdateCourseReview(
        val userId: String,
        val targetId: Long,
        val academicYear: Int,
        val term: String,
        val overallRating: Int,
        val professorRating: Int,
        val difficulty: Int,
        val workload: Int,
        val wouldTakeAgain: Boolean,
        val content: String,
        val professorContent: String?
    )

    data class DeleteCourseReview(
        val userId: String,
        val targetId: Long
    )
}
