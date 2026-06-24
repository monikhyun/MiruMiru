package com.example.api.controller

import com.example.api.common.ApiResponse
import com.example.api.dto.course.CourseReviewRequests
import com.example.api.dto.course.CourseReviewResponses
import com.example.application.course.CourseReviewCommand
import com.example.application.course.CourseReviewQueryService
import com.example.application.course.CourseReviewWriteService
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/course-review-targets")
class CourseReviewController(
    private val courseReviewQueryService: CourseReviewQueryService,
    private val courseReviewWriteService: CourseReviewWriteService
) {
    @GetMapping
    fun getCourseReviewTargets(
        @AuthenticationPrincipal userId: String,
        @RequestParam(defaultValue = "") query: String,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): ResponseEntity<ApiResponse<CourseReviewResponses.CourseReviewTargetPageResponse>> {
        val response = courseReviewQueryService.getCourseReviewTargets(userId, query, page, size)
        return ResponseEntity.ok(ApiResponse.ok(CourseReviewResponses.CourseReviewTargetPageResponse.from(response)))
    }

    @GetMapping("/{targetId}/reviews")
    fun getCourseReviews(
        @AuthenticationPrincipal userId: String,
        @PathVariable targetId: Long,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): ResponseEntity<ApiResponse<CourseReviewResponses.CourseReviewPageResponse>> {
        val response = courseReviewQueryService.getCourseReviews(userId, targetId, page, size)
        return ResponseEntity.ok(ApiResponse.ok(CourseReviewResponses.CourseReviewPageResponse.from(response)))
    }

    @GetMapping("/{targetId}/reviews/me")
    fun getMyCourseReview(
        @AuthenticationPrincipal userId: String,
        @PathVariable targetId: Long
    ): ResponseEntity<ApiResponse<CourseReviewResponses.CourseReviewItem>> {
        val response = courseReviewQueryService.getMyCourseReview(userId, targetId)
        return ResponseEntity.ok(ApiResponse.ok(CourseReviewResponses.CourseReviewItem.from(response)))
    }

    @PostMapping("/{targetId}/reviews")
    fun createCourseReview(
        @AuthenticationPrincipal userId: String,
        @PathVariable targetId: Long,
        @Valid @RequestBody request: CourseReviewRequests.UpsertCourseReviewRequest
    ): ResponseEntity<ApiResponse<CourseReviewResponses.CourseReviewIdResponse>> {
        val reviewId = courseReviewWriteService.createCourseReview(
            CourseReviewCommand.CreateCourseReview(
                userId = userId,
                targetId = targetId,
                academicYear = request.academicYear!!,
                term = request.term,
                overallRating = request.overallRating!!,
                professorRating = request.professorRating!!,
                difficulty = request.difficulty!!,
                workload = request.workload!!,
                wouldTakeAgain = request.wouldTakeAgain!!,
                content = request.content,
                professorContent = request.professorContent
            )
        )
        return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(ApiResponse.ok(CourseReviewResponses.CourseReviewIdResponse(reviewId)))
    }

    @PutMapping("/{targetId}/reviews/me")
    fun updateCourseReview(
        @AuthenticationPrincipal userId: String,
        @PathVariable targetId: Long,
        @Valid @RequestBody request: CourseReviewRequests.UpsertCourseReviewRequest
    ): ResponseEntity<ApiResponse<CourseReviewResponses.CourseReviewIdResponse>> {
        val reviewId = courseReviewWriteService.updateCourseReview(
            CourseReviewCommand.UpdateCourseReview(
                userId = userId,
                targetId = targetId,
                academicYear = request.academicYear!!,
                term = request.term,
                overallRating = request.overallRating!!,
                professorRating = request.professorRating!!,
                difficulty = request.difficulty!!,
                workload = request.workload!!,
                wouldTakeAgain = request.wouldTakeAgain!!,
                content = request.content,
                professorContent = request.professorContent
            )
        )
        return ResponseEntity.ok(ApiResponse.ok(CourseReviewResponses.CourseReviewIdResponse(reviewId)))
    }

    @DeleteMapping("/{targetId}/reviews/me")
    fun deleteCourseReview(
        @AuthenticationPrincipal userId: String,
        @PathVariable targetId: Long
    ): ResponseEntity<ApiResponse<Unit>> {
        courseReviewWriteService.deleteCourseReview(
            CourseReviewCommand.DeleteCourseReview(
                userId = userId,
                targetId = targetId
            )
        )
        return ResponseEntity.ok(ApiResponse.empty(Unit))
    }
}
