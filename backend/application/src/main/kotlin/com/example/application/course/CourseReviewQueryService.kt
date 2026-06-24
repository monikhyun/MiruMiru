package com.example.application.course

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.course.CourseReview
import com.example.domain.course.CourseReviewRepository
import com.example.domain.course.CourseReviewTarget
import com.example.domain.course.CourseReviewTargetRepository
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Sort
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import kotlin.math.round

@Service
@Transactional(readOnly = true)
class CourseReviewQueryService(
    private val memberRepository: MemberRepository,
    private val courseReviewRepository: CourseReviewRepository,
    private val courseReviewTargetRepository: CourseReviewTargetRepository,
    private val courseReviewTargetService: CourseReviewTargetService
) {
    fun getSchoolCourseReviews(userId: String, page: Int, size: Int): CourseReviewQueryResult.CourseReviewFeedPage {
        validatePage(page)
        validateSize(size)

        val member = findMember(userId)
        val pageable = PageRequest.of(
            page,
            size.coerceAtMost(MAX_PAGE_SIZE),
            Sort.by(
                Sort.Order.desc("createdAt"),
                Sort.Order.desc("id")
            )
        )
        val reviewPage = courseReviewRepository.findAllByTargetCourseUniversityId(member.university.id, pageable)
        val totalElements = reviewPage.totalElements
        val totalPages = if (totalElements == 0L) 0 else ((totalElements + pageable.pageSize - 1) / pageable.pageSize).toInt()

        return CourseReviewQueryResult.CourseReviewFeedPage(
            items = reviewPage.content.map { review -> review.toFeedItem(member.id) },
            page = reviewPage.number,
            size = reviewPage.size,
            totalElements = totalElements,
            totalPages = totalPages,
            hasNext = reviewPage.hasNext()
        )
    }

    fun getCourseReviewTargets(userId: String, query: String, page: Int, size: Int): CourseReviewQueryResult.CourseReviewTargetPage {
        validatePage(page)
        validateSize(size)

        val member = findMember(userId)
        val pageable = PageRequest.of(page, size.coerceAtMost(MAX_PAGE_SIZE))
        val targetPage = courseReviewTargetRepository.searchByUniversityId(
            universityId = member.university.id,
            query = query.trim(),
            pageable = pageable
        )
        val totalElements = targetPage.totalElements
        val totalPages = if (totalElements == 0L) 0 else ((totalElements + pageable.pageSize - 1) / pageable.pageSize).toInt()

        return CourseReviewQueryResult.CourseReviewTargetPage(
            items = targetPage.content.map { target ->
                CourseReviewQueryResult.CourseReviewTargetItem(
                    targetId = target.targetId,
                    courseId = target.courseId,
                    courseCode = target.courseCode,
                    courseName = target.courseName,
                    professorDisplayName = target.professorDisplayName,
                    displayName = courseReviewTargetService.buildDisplayName(target.courseName, target.professorDisplayName)
                )
            },
            page = targetPage.number,
            size = targetPage.size,
            totalElements = totalElements,
            totalPages = totalPages,
            hasNext = targetPage.hasNext()
        )
    }

    fun getCourseReviews(userId: String, targetId: Long, page: Int, size: Int): CourseReviewQueryResult.CourseReviewPage {
        validatePage(page)
        validateSize(size)

        val member = findMember(userId)
        val target = findTarget(member, targetId)
        val pageable = PageRequest.of(
            page,
            size.coerceAtMost(MAX_PAGE_SIZE),
            Sort.by(
                Sort.Order.desc("createdAt"),
                Sort.Order.desc("id")
            )
        )
        val reviewPage = courseReviewRepository.findAllByTargetId(target.id, pageable)
        val summary = courseReviewRepository.summarizeByTargetId(target.id)
        val totalElements = reviewPage.totalElements
        val totalPages = if (totalElements == 0L) 0 else ((totalElements + pageable.pageSize - 1) / pageable.pageSize).toInt()

        return CourseReviewQueryResult.CourseReviewPage(
            summary = CourseReviewQueryResult.CourseReviewSummary(
                targetId = target.id,
                courseId = target.course.id,
                courseCode = target.course.code,
                courseName = target.course.name,
                professorDisplayName = target.professorDisplayName,
                displayName = courseReviewTargetService.buildDisplayName(target.course.name, target.professorDisplayName),
                reviewCount = summary.reviewCount,
                averageOverall = roundNullable(summary.averageOverall),
                averageProfessor = roundNullable(summary.averageProfessor),
                averageDifficulty = roundNullable(summary.averageDifficulty),
                averageWorkload = roundNullable(summary.averageWorkload),
                wouldTakeAgainRate = roundNullable(summary.wouldTakeAgainRate)
            ),
            reviews = reviewPage.content.map { review -> review.toItem(member.id) },
            page = reviewPage.number,
            size = reviewPage.size,
            totalElements = totalElements,
            totalPages = totalPages,
            hasNext = reviewPage.hasNext()
        )
    }

    fun getMyCourseReview(userId: String, targetId: Long): CourseReviewQueryResult.CourseReviewItem {
        val member = findMember(userId)
        val target = findTarget(member, targetId)
        val review = courseReviewRepository.findByTargetIdAndMemberId(target.id, member.id)
            ?: throw BusinessException(ErrorCode.COURSE_REVIEW_NOT_FOUND)

        return review.toItem(member.id)
    }

    private fun CourseReview.toFeedItem(memberId: Long): CourseReviewQueryResult.CourseReviewFeedItem {
        return CourseReviewQueryResult.CourseReviewFeedItem(
            reviewId = id,
            targetId = target.id,
            courseId = target.course.id,
            courseCode = target.course.code,
            courseName = target.course.name,
            professorDisplayName = professorDisplayName,
            displayName = courseReviewTargetService.buildDisplayName(target.course.name, professorDisplayName),
            overallRating = overallRating,
            professorRating = professorRating,
            difficulty = difficulty,
            workload = workload,
            wouldTakeAgain = wouldTakeAgain,
            content = content,
            professorContent = professorContent,
            academicYear = academicYear,
            term = term.name,
            isMine = member.id == memberId,
            createdAt = createdAt?.toString().orEmpty(),
            updatedAt = updatedAt?.toString().orEmpty()
        )
    }

    private fun CourseReview.toItem(memberId: Long): CourseReviewQueryResult.CourseReviewItem {
        return CourseReviewQueryResult.CourseReviewItem(
            reviewId = id,
            overallRating = overallRating,
            professorRating = professorRating,
            difficulty = difficulty,
            workload = workload,
            wouldTakeAgain = wouldTakeAgain,
            content = content,
            professorContent = professorContent,
            academicYear = academicYear,
            term = term.name,
            professorDisplayName = professorDisplayName,
            isMine = member.id == memberId,
            createdAt = createdAt?.toString().orEmpty(),
            updatedAt = updatedAt?.toString().orEmpty()
        )
    }

    private fun roundNullable(value: Double?): Double? {
        return value?.let { round(it * 10.0) / 10.0 }
    }

    private fun validatePage(page: Int) {
        if (page < 0) {
            throw BusinessException(ErrorCode.INVALID_INPUT)
        }
    }

    private fun validateSize(size: Int) {
        if (size <= 0) {
            throw BusinessException(ErrorCode.INVALID_INPUT)
        }
    }

    private fun findMember(userId: String): Member {
        val parsedUserId = userId.toLongOrNull()
            ?: throw BusinessException(ErrorCode.UNAUTHORIZED)

        return memberRepository.findById(parsedUserId).orElseThrow {
            BusinessException(ErrorCode.USER_NOT_FOUND)
        }
    }

    private fun findTarget(member: Member, targetId: Long): CourseReviewTarget {
        return courseReviewTargetRepository.findByIdAndCourseUniversityId(targetId, member.university.id)
            ?: throw BusinessException(ErrorCode.COURSE_REVIEW_TARGET_NOT_FOUND)
    }

    companion object {
        const val DEFAULT_PAGE_SIZE = 20
        const val MAX_PAGE_SIZE = 50
    }
}
