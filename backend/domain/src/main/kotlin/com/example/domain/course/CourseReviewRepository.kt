package com.example.domain.course

import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query

interface CourseReviewRepository : JpaRepository<CourseReview, Long> {
    @EntityGraph(attributePaths = ["member", "target", "target.course"])
    fun findAllByTargetCourseUniversityId(universityId: Long, pageable: Pageable): Page<CourseReview>

    @EntityGraph(attributePaths = ["member", "target", "target.course"])
    fun findAllByTargetId(targetId: Long, pageable: Pageable): Page<CourseReview>

    @EntityGraph(attributePaths = ["member", "target", "target.course"])
    fun findByTargetIdAndMemberId(targetId: Long, memberId: Long): CourseReview?

    @Query(
        """
        select new com.example.domain.course.CourseReviewSummaryProjection(
            count(review),
            avg(review.overallRating),
            avg(review.professorRating),
            avg(review.difficulty),
            avg(review.workload),
            avg(case when review.wouldTakeAgain = true then 100.0 else 0.0 end)
        )
        from CourseReview review
        where review.target.id = :targetId
        """
    )
    fun summarizeByTargetId(targetId: Long): CourseReviewSummaryProjection
}
