package com.example.api.course

import com.example.ApiApplication
import com.example.application.security.TokenProvider
import com.example.domain.course.CourseReviewRepository
import com.example.domain.course.CourseReviewTargetRepository
import com.example.domain.member.MemberRepository
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put

@SpringBootTest(
    classes = [ApiApplication::class],
    properties = [
        "spring.mail.username=test@example.com",
        "spring.mail.password=test-password"
    ]
)
@AutoConfigureMockMvc
@ActiveProfiles("local")
class CourseReviewApiIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val memberRepository: MemberRepository,
    @Autowired private val courseReviewRepository: CourseReviewRepository,
    @Autowired private val courseReviewTargetRepository: CourseReviewTargetRepository,
    @Autowired private val tokenProvider: TokenProvider
) {
    private lateinit var accessToken: String
    private lateinit var emptyAccessToken: String
    private var testMemberId: Long = 0L
    private var emptyMemberId: Long = 0L
    private var cs101ItoTargetId: Long = 0L
    private var eng220TargetId: Long = 0L

    @BeforeEach
    fun setUp() {
        val member = memberRepository.findByEmail("test@tokyo.ac.jp")!!
        val emptyMember = memberRepository.findByEmail("empty@tokyo.ac.jp")!!
        testMemberId = member.id
        emptyMemberId = emptyMember.id
        accessToken = tokenProvider.createAccessToken(member.id, member.role)
        emptyAccessToken = tokenProvider.createAccessToken(emptyMember.id, emptyMember.role)

        cs101ItoTargetId = courseReviewTargetRepository.findAll()
            .first { it.course.code == "CS101" && it.professorDisplayName == "Prof. Ito" }
            .id
        eng220TargetId = courseReviewTargetRepository.findAll()
            .first { it.course.code == "ENG220" && it.professorDisplayName == "Prof. Wilson" }
            .id
    }

    @AfterEach
    fun tearDown() {
        courseReviewRepository.findByTargetIdAndMemberId(eng220TargetId, testMemberId)?.let(courseReviewRepository::delete)
        courseReviewRepository.findByTargetIdAndMemberId(eng220TargetId, emptyMemberId)?.let(courseReviewRepository::delete)
    }

    @Test
    fun `get course review targets returns selectable display names`() {
        val response = mockMvc.get("/api/v1/course-review-targets") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("query", "CS101")
        }.andReturn().response

        assertEquals(200, response.status)
        assertTrue(response.contentAsString.contains("\"targetId\":$cs101ItoTargetId"))
        assertTrue(response.contentAsString.contains("\"courseCode\":\"CS101\""))
        assertTrue(response.contentAsString.contains("\"professorDisplayName\":\"Prof. Ito\""))
        assertTrue(response.contentAsString.contains("\"displayName\":\"Introduction to Computer Science: Prof. Ito\""))
    }

    @Test
    fun `get school course reviews returns university feed in latest order`() {
        val response = mockMvc.get("/api/v1/course-reviews") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("page", "0")
            param("size", "20")
        }.andReturn().response

        assertEquals(200, response.status)
        assertTrue(response.contentAsString.contains("\"targetId\":$cs101ItoTargetId"))
        assertTrue(response.contentAsString.contains("\"courseCode\":\"CS101\""))
        assertTrue(response.contentAsString.contains("\"courseName\":\"Introduction to Computer Science\""))
        assertTrue(response.contentAsString.contains("\"professorDisplayName\":\"Prof. Ito\""))
        assertTrue(response.contentAsString.contains("\"displayName\":\"Introduction to Computer Science: Prof. Ito\""))
        assertTrue(response.contentAsString.contains("\"reviewId\":"))
        assertTrue(response.contentAsString.contains("\"items\":"))
    }

    @Test
    fun `get target reviews returns paginated summary for seeded target`() {
        val response = mockMvc.get("/api/v1/course-review-targets/$cs101ItoTargetId/reviews") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $accessToken")
            param("page", "0")
            param("size", "20")
        }.andReturn().response

        assertEquals(200, response.status)
        assertTrue(response.contentAsString.contains("\"targetId\":$cs101ItoTargetId"))
        assertTrue(response.contentAsString.contains("\"reviewCount\":1"))
        assertTrue(response.contentAsString.contains("\"professorDisplayName\":\"Prof. Ito\""))
        assertTrue(response.contentAsString.contains("\"averageProfessor\":"))
        assertTrue(response.contentAsString.contains("\"academicYear\":2025"))
    }

    @Test
    fun `post put delete target review manages my review lifecycle`() {
        val currentYear = java.time.LocalDate.now().year

        val createResponse = mockMvc.post("/api/v1/course-review-targets/$eng220TargetId/reviews") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "academicYear": $currentYear,
                  "term": "SPRING",
                  "overallRating": 8,
                  "professorRating": 9,
                  "difficulty": 2,
                  "workload": 3,
                  "wouldTakeAgain": true,
                  "content": "  [test] good elective  ",
                  "professorContent": "  [test] clear professor  "
                }
            """.trimIndent()
        }.andReturn().response

        assertEquals(201, createResponse.status)
        assertTrue(createResponse.contentAsString.contains("\"reviewId\":"))

        val myReviewResponse = mockMvc.get("/api/v1/course-review-targets/$eng220TargetId/reviews/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
        }.andReturn().response

        assertEquals(200, myReviewResponse.status)
        assertTrue(myReviewResponse.contentAsString.contains("\"content\":\"[test] good elective\""))
        assertTrue(myReviewResponse.contentAsString.contains("\"professorRating\":9"))
        assertTrue(myReviewResponse.contentAsString.contains("\"professorContent\":\"[test] clear professor\""))
        assertTrue(myReviewResponse.contentAsString.contains("\"professorDisplayName\":\"Prof. Wilson\""))

        val updateResponse = mockMvc.put("/api/v1/course-review-targets/$eng220TargetId/reviews/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "academicYear": ${currentYear - 1},
                  "term": "FALL",
                  "overallRating": 9,
                  "professorRating": 8,
                  "difficulty": 3,
                  "workload": 4,
                  "wouldTakeAgain": false,
                  "content": "[test] updated review",
                  "professorContent": "[test] updated professor"
                }
            """.trimIndent()
        }.andReturn().response

        assertEquals(200, updateResponse.status)

        val listResponse = mockMvc.get("/api/v1/course-review-targets/$eng220TargetId/reviews") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
        }.andReturn().response

        assertEquals(200, listResponse.status)
        assertTrue(listResponse.contentAsString.contains("\"reviewCount\":1"))
        assertTrue(listResponse.contentAsString.contains("\"academicYear\":${currentYear - 1}"))
        assertTrue(listResponse.contentAsString.contains("\"term\":\"FALL\""))
        assertTrue(listResponse.contentAsString.contains("\"wouldTakeAgain\":false"))
        assertTrue(listResponse.contentAsString.contains("\"professorRating\":8"))

        val deleteResponse = mockMvc.delete("/api/v1/course-review-targets/$eng220TargetId/reviews/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
        }.andReturn().response

        assertEquals(200, deleteResponse.status)

        val missingResponse = mockMvc.get("/api/v1/course-review-targets/$eng220TargetId/reviews/me") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
        }.andReturn().response

        assertEquals(404, missingResponse.status)
        assertTrue(missingResponse.contentAsString.contains("COURSE_002"))
    }

    @Test
    fun `post target review rejects ratings outside ten point range`() {
        val currentYear = java.time.LocalDate.now().year

        val response = mockMvc.post("/api/v1/course-review-targets/$eng220TargetId/reviews") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "academicYear": $currentYear,
                  "term": "SPRING",
                  "overallRating": 11,
                  "professorRating": 0,
                  "difficulty": 3,
                  "workload": 4,
                  "wouldTakeAgain": true,
                  "content": "[test] invalid review",
                  "professorContent": null
                }
            """.trimIndent()
        }.andReturn().response

        assertEquals(400, response.status)
    }

    @Test
    fun `post target review requires professor rating`() {
        val currentYear = java.time.LocalDate.now().year

        val response = mockMvc.post("/api/v1/course-review-targets/$eng220TargetId/reviews") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $emptyAccessToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "academicYear": $currentYear,
                  "term": "SPRING",
                  "overallRating": 8,
                  "difficulty": 3,
                  "workload": 4,
                  "wouldTakeAgain": true,
                  "content": "[test] missing professor rating",
                  "professorContent": null
                }
            """.trimIndent()
        }.andReturn().response

        assertEquals(400, response.status)
    }

    @Test
    fun `get course review targets requires authentication`() {
        val response = mockMvc.get("/api/v1/course-review-targets")
            .andReturn().response

        assertEquals(401, response.status)
    }

    @Test
    fun `get school course reviews requires authentication`() {
        val response = mockMvc.get("/api/v1/course-reviews")
            .andReturn().response

        assertEquals(401, response.status)
    }
}
