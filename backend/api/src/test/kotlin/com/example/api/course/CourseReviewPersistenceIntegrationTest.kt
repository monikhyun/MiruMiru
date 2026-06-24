package com.example.api.course

import com.example.ApiApplication
import com.example.domain.course.CourseReviewRepository
import com.example.domain.course.CourseReviewTargetRepository
import com.example.domain.lecture.LectureRepository
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Sort
import org.springframework.test.context.ActiveProfiles
import org.springframework.transaction.annotation.Transactional

@SpringBootTest(
    classes = [ApiApplication::class],
    properties = [
        "spring.mail.username=test@example.com",
        "spring.mail.password=test-password"
    ]
)
@ActiveProfiles("local")
@Transactional
class CourseReviewPersistenceIntegrationTest(
    @Autowired private val lectureRepository: LectureRepository,
    @Autowired private val courseReviewRepository: CourseReviewRepository,
    @Autowired private val courseReviewTargetRepository: CourseReviewTargetRepository
) {
    @Test
    fun `local bootstrap seeds review targets from lectures and keeps reviews by target`() {
        val springLecture = lectureRepository.findAll()
            .firstOrNull { it.course.code == "CS101" && it.professor == "Prof. Akiyama" }
        val fallLecture = lectureRepository.findAll()
            .firstOrNull { it.course.code == "CS101" && it.professor == "Prof. Ito" }

        assertNotNull(springLecture)
        assertNotNull(fallLecture)
        assertEquals(springLecture!!.course.id, fallLecture!!.course.id)

        val springTarget = courseReviewTargetRepository.findAll()
            .firstOrNull { it.course.id == springLecture.course.id && it.professorDisplayName == "Prof. Akiyama" }
        val fallTarget = courseReviewTargetRepository.findAll()
            .firstOrNull { it.course.id == fallLecture.course.id && it.professorDisplayName == "Prof. Ito" }

        assertNotNull(springTarget)
        assertNotNull(fallTarget)
        assertEquals(springLecture.course.id, springTarget!!.course.id)
        assertEquals(fallLecture.course.id, fallTarget!!.course.id)

        val reviews = courseReviewRepository.findAllByTargetId(
            fallTarget.id,
            PageRequest.of(
                0,
                10,
                Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id"))
            )
        )

        assertEquals(1, reviews.totalElements)
        assertEquals(2025, reviews.content.single().academicYear)
        assertEquals("Prof. Ito", reviews.content.single().professorDisplayName)
        assertEquals(10, reviews.content.single().overallRating)
        assertEquals(9, reviews.content.single().professorRating)
        assertEquals("Prof. Ito explains concepts clearly and gives helpful feedback.", reviews.content.single().professorContent)
    }

    @Test
    fun `local bootstrap school review feed includes multiple target reviews`() {
        val universityId = lectureRepository.findAll().first().semester.university.id

        val reviews = courseReviewRepository.findAllByTargetCourseUniversityId(
            universityId,
            PageRequest.of(
                0,
                20,
                Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id"))
            )
        )

        assertEquals(2, reviews.totalElements)
        assertEquals(2, reviews.content.map { it.target.id }.distinct().size)
    }
}
