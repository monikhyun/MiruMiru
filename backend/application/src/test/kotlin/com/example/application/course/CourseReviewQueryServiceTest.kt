package com.example.application.course

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.course.Course
import com.example.domain.course.CourseReview
import com.example.domain.course.CourseReviewRepository
import com.example.domain.course.CourseReviewSummaryProjection
import com.example.domain.course.CourseReviewTarget
import com.example.domain.course.CourseReviewTargetRepository
import com.example.domain.course.CourseReviewTargetSearchProjection
import com.example.domain.major.Major
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import com.example.domain.semester.SemesterTerm
import com.example.domain.university.University
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.springframework.data.domain.PageImpl
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Sort
import java.time.LocalDateTime
import java.util.Optional

class CourseReviewQueryServiceTest {
    private lateinit var memberRepository: MemberRepository
    private lateinit var courseReviewRepository: CourseReviewRepository
    private lateinit var courseReviewTargetRepository: CourseReviewTargetRepository
    private lateinit var courseReviewTargetService: CourseReviewTargetService
    private lateinit var courseReviewQueryService: CourseReviewQueryService

    @BeforeEach
    fun setUp() {
        memberRepository = mock(MemberRepository::class.java)
        courseReviewRepository = mock(CourseReviewRepository::class.java)
        courseReviewTargetRepository = mock(CourseReviewTargetRepository::class.java)
        courseReviewTargetService = CourseReviewTargetService(courseReviewTargetRepository)
        courseReviewQueryService = CourseReviewQueryService(
            memberRepository = memberRepository,
            courseReviewRepository = courseReviewRepository,
            courseReviewTargetRepository = courseReviewTargetRepository,
            courseReviewTargetService = courseReviewTargetService
        )
    }

    @Test
    fun `get course review targets returns paged display items`() {
        val university = university()
        val member = member(id = 2L, university = university)
        val pageable = PageRequest.of(
            0,
            20
        )

        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(courseReviewTargetRepository.searchByUniversityId(university.id, "cs", pageable))
            .thenReturn(
                PageImpl(
                    listOf(
                        CourseReviewTargetSearchProjection(
                            targetId = 10L,
                            courseId = 20L,
                            courseCode = "CS101",
                            courseName = "Introduction to Computer Science",
                            professorDisplayName = "Prof. Akiyama"
                        )
                    ),
                    pageable,
                    1
                )
            )

        val result = courseReviewQueryService.getCourseReviewTargets(member.id.toString(), "cs", 0, 20)

        assertEquals(1, result.items.size)
        assertEquals("Introduction to Computer Science: Prof. Akiyama", result.items.single().displayName)
        assertEquals(false, result.hasNext)
    }

    @Test
    fun `get school course reviews returns latest reviews in same university`() {
        val university = university()
        val member = member(id = 2L, university = university)
        val firstTarget = target(id = 10L, university = university, courseCode = "CS101", courseName = "Introduction to Computer Science", professorDisplayName = "Prof. Akiyama")
        val secondTarget = target(id = 11L, university = university, courseCode = "ENG220", courseName = "Academic English", professorDisplayName = "Prof. Wilson")
        val pageable = PageRequest.of(
            0,
            20,
            Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id"))
        )
        val newestReview = review(
            id = 20L,
            target = secondTarget,
            member = member,
            academicYear = 2026,
            term = SemesterTerm.SPRING,
            content = "Newest review",
            createdAt = LocalDateTime.of(2026, 3, 5, 9, 0),
            updatedAt = LocalDateTime.of(2026, 3, 5, 10, 0)
        )
        val olderReview = review(
            id = 19L,
            target = firstTarget,
            member = member(id = 3L, university = university),
            academicYear = 2025,
            term = SemesterTerm.FALL,
            content = "Older review",
            createdAt = LocalDateTime.of(2026, 3, 1, 9, 0),
            updatedAt = LocalDateTime.of(2026, 3, 1, 10, 0)
        )

        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(courseReviewRepository.findAllByTargetCourseUniversityId(university.id, pageable))
            .thenReturn(PageImpl(listOf(newestReview, olderReview), pageable, 2))

        val result = courseReviewQueryService.getSchoolCourseReviews(member.id.toString(), 0, 20)

        assertEquals(2, result.items.size)
        assertEquals(listOf(20L, 19L), result.items.map { it.reviewId })
        assertEquals(secondTarget.id, result.items.first().targetId)
        assertEquals("Academic English: Prof. Wilson", result.items.first().displayName)
        assertEquals(true, result.items.first().isMine)
        assertEquals(false, result.items.last().isMine)
    }

    @Test
    fun `get course reviews returns paged reviews and rounded summary`() {
        val university = university()
        val member = member(id = 2L, university = university)
        val target = target(id = 10L, university = university, courseCode = "CS101", courseName = "Introduction to Computer Science", professorDisplayName = "Prof. Akiyama")
        val pageable = PageRequest.of(
            0,
            20,
            Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id"))
        )
        val firstReview = review(
            id = 20L,
            target = target,
            member = member,
            academicYear = 2026,
            term = SemesterTerm.SPRING,
            content = "Great class",
            createdAt = LocalDateTime.of(2026, 3, 1, 9, 0),
            updatedAt = LocalDateTime.of(2026, 3, 2, 9, 0)
        )
        val secondReview = review(
            id = 21L,
            target = target,
            member = member(id = 3L, university = university),
            academicYear = 2025,
            term = SemesterTerm.FALL,
            content = "Old but helpful review",
            createdAt = LocalDateTime.of(2026, 2, 1, 9, 0),
            updatedAt = LocalDateTime.of(2026, 2, 1, 10, 0)
        )

        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(courseReviewTargetRepository.findByIdAndCourseUniversityId(target.id, university.id)).thenReturn(target)
        `when`(courseReviewRepository.findAllByTargetId(target.id, pageable))
            .thenReturn(PageImpl(listOf(firstReview, secondReview), pageable, 2))
        `when`(courseReviewRepository.summarizeByTargetId(target.id))
            .thenReturn(CourseReviewSummaryProjection(2, 8.44, 9.15, 3.55, 2.49, 87.66))

        val result = courseReviewQueryService.getCourseReviews(member.id.toString(), target.id, 0, 20)

        assertEquals(target.id, result.summary.targetId)
        assertEquals(target.course.id, result.summary.courseId)
        assertEquals("Prof. Akiyama", result.summary.professorDisplayName)
        assertEquals(8.4, result.summary.averageOverall)
        assertEquals(9.2, result.summary.averageProfessor)
        assertEquals(3.6, result.summary.averageDifficulty)
        assertEquals(2.5, result.summary.averageWorkload)
        assertEquals(87.7, result.summary.wouldTakeAgainRate)
        assertEquals(listOf(20L, 21L), result.reviews.map { it.reviewId })
        assertEquals(true, result.reviews.first().isMine)
        assertEquals(8, result.reviews.first().professorRating)
        assertEquals("Helpful office hours", result.reviews.first().professorContent)
    }

    @Test
    fun `get course reviews returns null summary values when no reviews exist`() {
        val university = university()
        val member = member(id = 2L, university = university)
        val target = target(id = 10L, university = university, courseCode = "ENG220", courseName = "Academic English", professorDisplayName = "Prof. Wilson")
        val pageable = PageRequest.of(0, 1, Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id")))

        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(courseReviewTargetRepository.findByIdAndCourseUniversityId(target.id, university.id)).thenReturn(target)
        `when`(courseReviewRepository.findAllByTargetId(target.id, pageable)).thenReturn(PageImpl(emptyList(), pageable, 0))
        `when`(courseReviewRepository.summarizeByTargetId(target.id)).thenReturn(CourseReviewSummaryProjection(0, null, null, null, null, null))

        val result = courseReviewQueryService.getCourseReviews(member.id.toString(), target.id, 0, 1)

        assertEquals(0, result.summary.reviewCount)
        assertNull(result.summary.averageOverall)
        assertNull(result.summary.averageProfessor)
        assertNull(result.summary.averageDifficulty)
        assertNull(result.summary.averageWorkload)
        assertNull(result.summary.wouldTakeAgainRate)
        assertEquals(0, result.totalPages)
    }

    @Test
    fun `get course reviews keeps legacy nullable professor fields readable`() {
        val university = university()
        val member = member(id = 2L, university = university)
        val target = target(id = 10L, university = university, courseCode = "CS101", courseName = "Introduction to Computer Science", professorDisplayName = "Prof. Akiyama")
        val pageable = PageRequest.of(0, 20, Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id")))
        val legacyReview = review(
            id = 20L,
            target = target,
            member = member,
            academicYear = 2024,
            term = SemesterTerm.FALL,
            content = "Legacy review",
            professorRating = null,
            professorContent = null,
            createdAt = LocalDateTime.of(2026, 2, 1, 9, 0),
            updatedAt = LocalDateTime.of(2026, 2, 1, 10, 0)
        )

        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(courseReviewTargetRepository.findByIdAndCourseUniversityId(target.id, university.id)).thenReturn(target)
        `when`(courseReviewRepository.findAllByTargetId(target.id, pageable))
            .thenReturn(PageImpl(listOf(legacyReview), pageable, 1))
        `when`(courseReviewRepository.summarizeByTargetId(target.id))
            .thenReturn(CourseReviewSummaryProjection(1, 8.0, null, 3.0, 2.0, 100.0))

        val result = courseReviewQueryService.getCourseReviews(member.id.toString(), target.id, 0, 20)

        assertNull(result.reviews.single().professorRating)
        assertNull(result.reviews.single().professorContent)
        assertNull(result.summary.averageProfessor)
    }

    @Test
    fun `get course review targets fails for negative page`() {
        val exception = assertThrows(BusinessException::class.java) {
            courseReviewQueryService.getCourseReviewTargets("1", "", -1, 20)
        }

        assertEquals(ErrorCode.INVALID_INPUT, exception.errorCode)
    }

    @Test
    fun `get school course reviews fails for invalid size`() {
        val exception = assertThrows(BusinessException::class.java) {
            courseReviewQueryService.getSchoolCourseReviews("1", 0, 0)
        }

        assertEquals(ErrorCode.INVALID_INPUT, exception.errorCode)
    }

    private fun university(): University {
        return University(id = 1L, name = "The University of Tokyo", emailDomain = "tokyo.ac.jp")
    }

    private fun member(id: Long, university: University): Member {
        return Member(
            id = id,
            university = university,
            major = Major(id = 11L, university = university, code = "CS", name = "Computer Science"),
            email = "user$id@tokyo.ac.jp",
            password = "encoded",
            nickname = "user-$id"
        )
    }

    private fun target(
        id: Long,
        university: University,
        courseCode: String,
        courseName: String,
        professorDisplayName: String
    ): CourseReviewTarget {
        return CourseReviewTarget(
            id = id,
            course = Course(id = 30L + id, university = university, code = courseCode, name = courseName),
            professorDisplayName = professorDisplayName,
            professorKey = professorDisplayName.lowercase()
        )
    }

    private fun review(
        id: Long,
        target: CourseReviewTarget,
        member: Member,
        academicYear: Int,
        term: SemesterTerm,
        content: String,
        professorRating: Int? = 8,
        professorContent: String? = "Helpful office hours",
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime
    ): CourseReview {
        return CourseReview(
            id = id,
            target = target,
            member = member,
            academicYear = academicYear,
            term = term,
            professorDisplayName = target.professorDisplayName,
            overallRating = 4,
            professorRating = professorRating,
            difficulty = 3,
            workload = 2,
            wouldTakeAgain = true,
            content = content,
            professorContent = professorContent
        ).apply {
            this.createdAt = createdAt
            this.updatedAt = updatedAt
        }
    }
}
