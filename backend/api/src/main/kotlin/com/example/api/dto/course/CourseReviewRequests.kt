package com.example.api.dto.course

import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull

object CourseReviewRequests {
    data class UpsertCourseReviewRequest(
        @field:NotNull(message = "academicYear는 필수입니다")
        val academicYear: Int?,

        @field:NotBlank(message = "term은 필수입니다")
        val term: String,

        @field:NotNull(message = "overallRating은 필수입니다")
        @field:Min(value = 1, message = "overallRating은 1 이상이어야 합니다")
        @field:Max(value = 10, message = "overallRating은 10 이하여야 합니다")
        val overallRating: Int?,

        @field:NotNull(message = "professorRating은 필수입니다")
        @field:Min(value = 1, message = "professorRating은 1 이상이어야 합니다")
        @field:Max(value = 10, message = "professorRating은 10 이하여야 합니다")
        val professorRating: Int?,

        @field:NotNull(message = "difficulty는 필수입니다")
        @field:Min(value = 1, message = "difficulty는 1 이상이어야 합니다")
        @field:Max(value = 5, message = "difficulty는 5 이하여야 합니다")
        val difficulty: Int?,

        @field:NotNull(message = "workload는 필수입니다")
        @field:Min(value = 1, message = "workload는 1 이상이어야 합니다")
        @field:Max(value = 5, message = "workload는 5 이하여야 합니다")
        val workload: Int?,

        @field:NotNull(message = "wouldTakeAgain은 필수입니다")
        val wouldTakeAgain: Boolean?,

        @field:NotBlank(message = "리뷰 내용을 입력해주세요")
        val content: String,

        val professorContent: String?
    )
}
