package com.example.api.schedule

import com.example.ApiApplication
import com.example.application.security.TokenProvider
import com.example.domain.lecture.LectureRepository
import com.example.domain.member.MemberRepository
import com.example.domain.schedule.ScheduleItemRepository
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
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
import org.springframework.test.web.servlet.patch
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put
import java.time.Instant

@SpringBootTest(
    classes = [ApiApplication::class],
    properties = [
        "spring.mail.username=test@example.com",
        "spring.mail.password=test-password"
    ]
)
@AutoConfigureMockMvc
@ActiveProfiles("local", "test")
class ScheduleItemApiIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val memberRepository: MemberRepository,
    @Autowired private val lectureRepository: LectureRepository,
    @Autowired private val scheduleItemRepository: ScheduleItemRepository,
    @Autowired private val tokenProvider: TokenProvider
) {
    private lateinit var ownerToken: String
    private lateinit var otherToken: String
    private var lectureId: Long = 0L

    @BeforeEach
    fun setUp() {
        scheduleItemRepository.deleteAll()
        val owner = memberRepository.findByEmail("test@tokyo.ac.jp")!!
        val other = memberRepository.findByEmail("partner@tokyo.ac.jp")!!
        ownerToken = tokenProvider.createAccessToken(owner.id, owner.role)
        otherToken = tokenProvider.createAccessToken(other.id, other.role)
        lectureId = lectureRepository.findAll().first().id
    }

    @AfterEach
    fun tearDown() {
        scheduleItemRepository.deleteAll()
    }

    @Test
    fun `owner can create list update complete and delete schedule item`() {
        val created = createItem(
            token = ownerToken,
            body = """
                {
                  "lectureId": $lectureId,
                  "type": "ASSIGNMENT",
                  "title": "Submit report",
                  "memo": "PDF only",
                  "dueAt": "2026-07-05T09:00:00+09:00"
                }
            """.trimIndent()
        )
        val itemId = created.path("data").path("itemId").asLong()
        assertEquals(lectureId, created.path("data").path("lectureId").asLong())
        assertEquals("2026-07-05T00:00:00Z", created.path("data").path("dueAt").asText())
        assertFalse(created.path("data").path("completed").asBoolean())

        val listed = getItems(ownerToken, status = "open")
        assertEquals(listOf(itemId), listed.path("data").map { it.path("itemId").asLong() })

        val updateResponse = mockMvc.put("/api/v1/schedule-items/$itemId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
            contentType = MediaType.APPLICATION_JSON
            content = """
                {
                  "type": "QUIZ",
                  "title": "Updated quiz",
                  "memo": null,
                  "dueAt": "2026-07-06T12:00:00Z",
                  "completed": false
                }
            """.trimIndent()
        }.andReturn().response
        assertEquals(200, updateResponse.status)
        val updated = objectMapper.readTree(updateResponse.contentAsString).path("data")
        assertEquals("QUIZ", updated.path("type").asText())
        assertEquals("Updated quiz", updated.path("title").asText())
        assertTrue(updated.path("lectureId").isNull)

        val completionResponse = mockMvc.patch("/api/v1/schedule-items/$itemId/completion") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"completed":true}"""
        }.andReturn().response
        assertEquals(200, completionResponse.status)
        assertTrue(objectMapper.readTree(completionResponse.contentAsString).path("data").path("completed").asBoolean())

        val deleteResponse = mockMvc.delete("/api/v1/schedule-items/$itemId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
        }.andReturn().response
        assertEquals(200, deleteResponse.status)
        assertTrue(objectMapper.readTree(deleteResponse.contentAsString).path("success").asBoolean())

        val repeatedDelete = mockMvc.delete("/api/v1/schedule-items/$itemId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
        }.andReturn().response
        assertScheduleNotFound(repeatedDelete.status, repeatedDelete.contentAsString)
    }

    @Test
    fun `foreign user cannot list update complete or delete and foreign row survives`() {
        val title = "Owner private deadline"
        val itemId = createItem(
            token = ownerToken,
            body = """{"type":"MINI_TEST","title":"$title","dueAt":"2026-07-05T00:00:00Z"}"""
        ).path("data").path("itemId").asLong()

        val foreignList = getItems(otherToken)
        assertFalse(foreignList.path("data").any { it.path("itemId").asLong() == itemId })

        val updateResponse = mockMvc.put("/api/v1/schedule-items/$itemId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"type":"MEMO","title":"stolen"}"""
        }.andReturn().response
        assertScheduleNotFound(updateResponse.status, updateResponse.contentAsString)

        val completionResponse = mockMvc.patch("/api/v1/schedule-items/$itemId/completion") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"completed":true}"""
        }.andReturn().response
        assertScheduleNotFound(completionResponse.status, completionResponse.contentAsString)

        val deleteResponse = mockMvc.delete("/api/v1/schedule-items/$itemId") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $otherToken")
        }.andReturn().response
        assertScheduleNotFound(deleteResponse.status, deleteResponse.contentAsString)

        val survivingItem = scheduleItemRepository.findById(itemId).orElseThrow()
        assertEquals(title, survivingItem.title)
        assertFalse(survivingItem.completed)
    }

    @Test
    fun `range converts offsets to UTC includes undated memos and excludes exact upper bound`() {
        val insideId = createItem(
            ownerToken,
            """{"type":"ASSIGNMENT","title":"Inside","dueAt":"2026-07-05T00:30:00+09:00"}"""
        ).path("data").path("itemId").asLong()
        val exactUpperId = createItem(
            ownerToken,
            """{"type":"QUIZ","title":"Exact upper","dueAt":"2026-07-05T01:00:00+09:00"}"""
        ).path("data").path("itemId").asLong()
        val beforeId = createItem(
            ownerToken,
            """{"type":"MINI_TEST","title":"Before","dueAt":"2026-07-04T23:59:59+09:00"}"""
        ).path("data").path("itemId").asLong()
        val undatedId = createItem(
            ownerToken,
            """{"type":"MEMO","title":"Undated","completed":true}"""
        ).path("data").path("itemId").asLong()

        assertEquals(
            Instant.parse("2026-07-04T15:30:00Z"),
            scheduleItemRepository.findById(insideId).orElseThrow().dueAt
        )

        val allItems = getItems(
            ownerToken,
            from = "2026-07-04T16:00:00+01:00",
            to = "2026-07-05T01:00:00+09:00"
        ).path("data")
        val allIds = allItems.map { it.path("itemId").asLong() }
        assertTrue(allIds.contains(insideId))
        assertTrue(allIds.contains(undatedId))
        assertFalse(allIds.contains(exactUpperId))
        assertFalse(allIds.contains(beforeId))

        val openIds = getItems(
            ownerToken,
            from = "2026-07-04T15:00:00Z",
            to = "2026-07-04T16:00:00Z",
            status = "open"
        ).path("data").map { it.path("itemId").asLong() }
        assertEquals(listOf(insideId), openIds)

        val completedIds = getItems(
            ownerToken,
            from = "2026-07-04T15:00:00Z",
            to = "2026-07-04T16:00:00Z",
            status = "completed"
        ).path("data").map { it.path("itemId").asLong() }
        assertEquals(listOf(undatedId), completedIds)
    }

    @Test
    fun `invalid lecture and invalid query inputs return typed client errors`() {
        val invalidLectureResponse = mockMvc.post("/api/v1/schedule-items") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
            contentType = MediaType.APPLICATION_JSON
            content = """{"lectureId":999999,"type":"MEMO","title":"Invalid"}"""
        }.andReturn().response
        assertEquals(400, invalidLectureResponse.status)
        assertTrue(invalidLectureResponse.contentAsString.contains("SCHEDULE_002"))

        val invalidStatusResponse = mockMvc.get("/api/v1/schedule-items") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
            param("from", "2026-07-04T00:00:00Z")
            param("to", "2026-07-05T00:00:00Z")
            param("status", "archived")
        }.andReturn().response
        assertEquals(400, invalidStatusResponse.status)
        assertTrue(invalidStatusResponse.contentAsString.contains("COMMON_001"))

        val invalidRangeResponse = mockMvc.get("/api/v1/schedule-items") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $ownerToken")
            param("from", "2026-07-05T00:00:00Z")
            param("to", "2026-07-04T00:00:00Z")
        }.andReturn().response
        assertEquals(400, invalidRangeResponse.status)
        assertTrue(invalidRangeResponse.contentAsString.contains("COMMON_001"))
    }

    private fun createItem(token: String, body: String): JsonNode {
        val response = mockMvc.post("/api/v1/schedule-items") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
            contentType = MediaType.APPLICATION_JSON
            content = body
        }.andReturn().response
        assertEquals(200, response.status, response.contentAsString)
        return objectMapper.readTree(response.contentAsString)
    }

    private fun getItems(
        token: String,
        from: String = "2026-07-01T00:00:00Z",
        to: String = "2026-08-01T00:00:00Z",
        status: String = "all"
    ): JsonNode {
        val response = mockMvc.get("/api/v1/schedule-items") {
            header(HttpHeaders.AUTHORIZATION, "Bearer $token")
            param("from", from)
            param("to", to)
            param("status", status)
        }.andReturn().response
        assertEquals(200, response.status, response.contentAsString)
        return objectMapper.readTree(response.contentAsString)
    }

    private fun assertScheduleNotFound(status: Int, content: String) {
        assertEquals(404, status, content)
        assertTrue(content.contains("SCHEDULE_001"), content)
    }
}
