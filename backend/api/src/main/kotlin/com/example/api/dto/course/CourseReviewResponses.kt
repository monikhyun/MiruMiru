package com.example.api.dto.course

import com.example.application.course.CourseReviewQueryResult

object CourseReviewResponses {
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
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewFeedItem): CourseReviewFeedItem {
                return CourseReviewFeedItem(
                    reviewId = result.reviewId,
                    targetId = result.targetId,
                    courseId = result.courseId,
                    courseCode = result.courseCode,
                    courseName = result.courseName,
                    professorDisplayName = result.professorDisplayName,
                    displayName = result.displayName,
                    overallRating = result.overallRating,
                    professorRating = result.professorRating,
                    difficulty = result.difficulty,
                    workload = result.workload,
                    wouldTakeAgain = result.wouldTakeAgain,
                    content = result.content,
                    professorContent = result.professorContent,
                    academicYear = result.academicYear,
                    term = result.term,
                    isMine = result.isMine,
                    createdAt = result.createdAt,
                    updatedAt = result.updatedAt
                )
            }
        }
    }

    data class CourseReviewFeedPageResponse(
        val items: List<CourseReviewFeedItem>,
        val page: Int,
        val size: Int,
        val totalElements: Long,
        val totalPages: Int,
        val hasNext: Boolean
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewFeedPage): CourseReviewFeedPageResponse {
                return CourseReviewFeedPageResponse(
                    items = result.items.map(CourseReviewFeedItem::from),
                    page = result.page,
                    size = result.size,
                    totalElements = result.totalElements,
                    totalPages = result.totalPages,
                    hasNext = result.hasNext
                )
            }
        }
    }

    data class CourseReviewTargetItem(
        val targetId: Long,
        val courseId: Long,
        val courseCode: String,
        val courseName: String,
        val professorDisplayName: String,
        val displayName: String
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewTargetItem): CourseReviewTargetItem {
                return CourseReviewTargetItem(
                    targetId = result.targetId,
                    courseId = result.courseId,
                    courseCode = result.courseCode,
                    courseName = result.courseName,
                    professorDisplayName = result.professorDisplayName,
                    displayName = result.displayName
                )
            }
        }
    }

    data class CourseReviewTargetPageResponse(
        val items: List<CourseReviewTargetItem>,
        val page: Int,
        val size: Int,
        val totalElements: Long,
        val totalPages: Int,
        val hasNext: Boolean
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewTargetPage): CourseReviewTargetPageResponse {
                return CourseReviewTargetPageResponse(
                    items = result.items.map(CourseReviewTargetItem::from),
                    page = result.page,
                    size = result.size,
                    totalElements = result.totalElements,
                    totalPages = result.totalPages,
                    hasNext = result.hasNext
                )
            }
        }
    }

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
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewSummary): CourseReviewSummary {
                return CourseReviewSummary(
                    targetId = result.targetId,
                    courseId = result.courseId,
                    courseCode = result.courseCode,
                    courseName = result.courseName,
                    professorDisplayName = result.professorDisplayName,
                    displayName = result.displayName,
                    reviewCount = result.reviewCount,
                    averageOverall = result.averageOverall,
                    averageProfessor = result.averageProfessor,
                    averageDifficulty = result.averageDifficulty,
                    averageWorkload = result.averageWorkload,
                    wouldTakeAgainRate = result.wouldTakeAgainRate
                )
            }
        }
    }

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
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewItem): CourseReviewItem {
                return CourseReviewItem(
                    reviewId = result.reviewId,
                    overallRating = result.overallRating,
                    professorRating = result.professorRating,
                    difficulty = result.difficulty,
                    workload = result.workload,
                    wouldTakeAgain = result.wouldTakeAgain,
                    content = result.content,
                    professorContent = result.professorContent,
                    academicYear = result.academicYear,
                    term = result.term,
                    professorDisplayName = result.professorDisplayName,
                    isMine = result.isMine,
                    createdAt = result.createdAt,
                    updatedAt = result.updatedAt
                )
            }
        }
    }

    data class CourseReviewPageResponse(
        val summary: CourseReviewSummary,
        val reviews: List<CourseReviewItem>,
        val page: Int,
        val size: Int,
        val totalElements: Long,
        val totalPages: Int,
        val hasNext: Boolean
    ) {
        companion object {
            fun from(result: CourseReviewQueryResult.CourseReviewPage): CourseReviewPageResponse {
                return CourseReviewPageResponse(
                    summary = CourseReviewSummary.from(result.summary),
                    reviews = result.reviews.map(CourseReviewItem::from),
                    page = result.page,
                    size = result.size,
                    totalElements = result.totalElements,
                    totalPages = result.totalPages,
                    hasNext = result.hasNext
                )
            }
        }
    }

    data class CourseReviewIdResponse(
        val reviewId: Long
    )
}
