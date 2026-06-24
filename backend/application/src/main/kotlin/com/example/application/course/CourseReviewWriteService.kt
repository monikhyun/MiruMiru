package com.example.application.course

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.course.CourseReview
import com.example.domain.course.CourseReviewRepository
import com.example.domain.course.CourseReviewTarget
import com.example.domain.course.CourseReviewTargetRepository
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import com.example.domain.semester.SemesterTerm
import org.springframework.dao.DataIntegrityViolationException
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDate

@Service
@Transactional
class CourseReviewWriteService(
    private val memberRepository: MemberRepository,
    private val courseReviewRepository: CourseReviewRepository,
    private val courseReviewTargetRepository: CourseReviewTargetRepository
) {
    fun createCourseReview(command: CourseReviewCommand.CreateCourseReview): Long {
        val member = findMember(command.userId)
        val target = findTarget(member, command.targetId)
        val term = parseTerm(command.term)
        validateAcademicYear(command.academicYear)
        validateRatings(command.overallRating, command.professorRating, command.difficulty, command.workload)
        val content = command.content.trim()
        validateContent(content)
        val professorContent = command.professorContent.cleanedOptional()

        if (courseReviewRepository.findByTargetIdAndMemberId(target.id, member.id) != null) {
            throw BusinessException(ErrorCode.COURSE_REVIEW_ALREADY_EXISTS)
        }

        return try {
            courseReviewRepository.save(
                CourseReview(
                    target = target,
                    member = member,
                    academicYear = command.academicYear,
                    term = term,
                    professorDisplayName = target.professorDisplayName,
                    overallRating = command.overallRating,
                    difficulty = command.difficulty,
                    workload = command.workload,
                    wouldTakeAgain = command.wouldTakeAgain,
                    content = content,
                    professorRating = command.professorRating,
                    professorContent = professorContent
                )
            ).id
        } catch (_: DataIntegrityViolationException) {
            throw BusinessException(ErrorCode.COURSE_REVIEW_ALREADY_EXISTS)
        }
    }

    fun updateCourseReview(command: CourseReviewCommand.UpdateCourseReview): Long {
        val member = findMember(command.userId)
        val target = findTarget(member, command.targetId)
        val term = parseTerm(command.term)
        validateAcademicYear(command.academicYear)
        validateRatings(command.overallRating, command.professorRating, command.difficulty, command.workload)
        val content = command.content.trim()
        validateContent(content)
        val professorContent = command.professorContent.cleanedOptional()

        val review = courseReviewRepository.findByTargetIdAndMemberId(target.id, member.id)
            ?: throw BusinessException(ErrorCode.COURSE_REVIEW_NOT_FOUND)

        review.update(
            academicYear = command.academicYear,
            term = term,
            professorDisplayName = target.professorDisplayName,
            overallRating = command.overallRating,
            difficulty = command.difficulty,
            workload = command.workload,
            wouldTakeAgain = command.wouldTakeAgain,
            content = content,
            professorRating = command.professorRating,
            professorContent = professorContent
        )

        return review.id
    }

    fun deleteCourseReview(command: CourseReviewCommand.DeleteCourseReview) {
        val member = findMember(command.userId)
        val target = findTarget(member, command.targetId)
        val review = courseReviewRepository.findByTargetIdAndMemberId(target.id, member.id)
            ?: throw BusinessException(ErrorCode.COURSE_REVIEW_NOT_FOUND)

        courseReviewRepository.delete(review)
    }

    private fun validateRatings(overallRating: Int, professorRating: Int, difficulty: Int, workload: Int) {
        if (overallRating !in MIN_RATING..MAX_COURSE_RATING ||
            professorRating !in MIN_RATING..MAX_COURSE_RATING ||
            difficulty !in MIN_RATING..MAX_CHARACTERISTIC_RATING ||
            workload !in MIN_RATING..MAX_CHARACTERISTIC_RATING
        ) {
            throw BusinessException(ErrorCode.INVALID_INPUT)
        }
    }

    private fun validateContent(content: String) {
        if (content.isBlank()) {
            throw BusinessException(ErrorCode.INVALID_INPUT)
        }
    }

    private fun validateAcademicYear(academicYear: Int) {
        val currentYear = LocalDate.now().year
        if (academicYear !in (currentYear - YEAR_LOOKBACK_RANGE)..(currentYear + FUTURE_YEAR_ALLOWANCE)) {
            throw BusinessException(ErrorCode.INVALID_INPUT)
        }
    }

    private fun parseTerm(term: String): SemesterTerm {
        return runCatching { SemesterTerm.valueOf(term.trim().uppercase()) }
            .getOrElse { throw BusinessException(ErrorCode.INVALID_INPUT) }
    }

    private fun String?.cleanedOptional(): String? {
        return this?.trim()?.takeIf { it.isNotEmpty() }
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
        private const val MIN_RATING = 1
        private const val MAX_COURSE_RATING = 10
        private const val MAX_CHARACTERISTIC_RATING = 5
        private const val YEAR_LOOKBACK_RANGE = 30
        private const val FUTURE_YEAR_ALLOWANCE = 1
    }
}
