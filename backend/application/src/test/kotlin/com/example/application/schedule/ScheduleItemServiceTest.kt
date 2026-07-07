package com.example.application.schedule

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.course.Course
import com.example.domain.lecture.Lecture
import com.example.domain.lecture.LectureRepository
import com.example.domain.major.Major
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import com.example.domain.schedule.ScheduleItem
import com.example.domain.schedule.ScheduleItemRepository
import com.example.domain.schedule.ScheduleItemType
import com.example.domain.semester.Semester
import com.example.domain.semester.SemesterTerm
import com.example.domain.university.University
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import java.time.Instant
import java.util.Optional

class ScheduleItemServiceTest {
    private lateinit var memberRepository: MemberRepository
    private lateinit var lectureRepository: LectureRepository
    private lateinit var scheduleItemRepository: ScheduleItemRepository
    private lateinit var writeService: ScheduleItemWriteService
    private lateinit var queryService: ScheduleItemQueryService

    private val now = Instant.parse("2026-07-04T02:00:00Z")

    @BeforeEach
    fun setUp() {
        memberRepository = mock(MemberRepository::class.java)
        lectureRepository = mock(LectureRepository::class.java)
        scheduleItemRepository = mock(ScheduleItemRepository::class.java)
        writeService = ScheduleItemWriteService(memberRepository, lectureRepository, scheduleItemRepository)
        queryService = ScheduleItemQueryService(memberRepository, scheduleItemRepository)
    }

    @Test
    fun `create stores UTC instant and lecture for member university`() {
        val member = member()
        val lecture = lecture(member.university)
        val dueAt = Instant.parse("2026-07-08T03:00:00Z")
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(lectureRepository.findById(lecture.id)).thenReturn(Optional.of(lecture))
        stubAuditedSave()

        val result = writeService.create(
            ScheduleItemCommand.Create(
                userId = member.id.toString(),
                lectureId = lecture.id,
                type = "ASSIGNMENT",
                title = "  Final report  ",
                memo = "Upload PDF",
                dueAt = dueAt,
                completed = null
            )
        )

        assertEquals(lecture.id, result.lectureId)
        assertEquals("Final report", result.title)
        assertEquals(dueAt, result.dueAt)
        assertFalse(result.completed)
    }

    @Test
    fun `create rejects lecture outside member university`() {
        val member = member()
        val foreignLecture = lecture(university(id = 99L, domain = "kyoto.ac.jp"))
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(lectureRepository.findById(foreignLecture.id)).thenReturn(Optional.of(foreignLecture))

        val exception = assertThrows(BusinessException::class.java) {
            writeService.create(
                ScheduleItemCommand.Create(
                    userId = member.id.toString(),
                    lectureId = foreignLecture.id,
                    type = "MEMO",
                    title = "Memo",
                    memo = null,
                    dueAt = null,
                    completed = null
                )
            )
        }

        assertEquals(ErrorCode.SCHEDULE_LECTURE_INVALID, exception.errorCode)
        verify(scheduleItemRepository, never()).saveAndFlush(any(ScheduleItem::class.java))
    }

    @Test
    fun `update hides foreign owned item as not found`() {
        val member = member()
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(scheduleItemRepository.findByIdAndMemberId(77L, member.id)).thenReturn(null)

        val exception = assertThrows(BusinessException::class.java) {
            writeService.update(
                ScheduleItemCommand.Update(
                    userId = member.id.toString(),
                    itemId = 77L,
                    lectureId = null,
                    type = "QUIZ",
                    title = "Hidden",
                    memo = null,
                    dueAt = null,
                    completed = null
                )
            )
        }

        assertEquals(ErrorCode.SCHEDULE_ITEM_NOT_FOUND, exception.errorCode)
        verify(scheduleItemRepository, never()).saveAndFlush(any(ScheduleItem::class.java))
    }

    @Test
    fun `completion patch changes only owned item completion`() {
        val member = member()
        val item = scheduleItem(member = member, completed = false)
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(scheduleItemRepository.findByIdAndMemberId(item.id, member.id)).thenReturn(item)
        stubAuditedSave()

        val result = writeService.updateCompletion(
            ScheduleItemCommand.UpdateCompletion(
                userId = member.id.toString(),
                itemId = item.id,
                completed = true
            )
        )

        assertTrue(result.completed)
        assertEquals("Original", result.title)
    }

    @Test
    fun `delete missing or foreign owned item returns schedule not found`() {
        val member = member()
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(scheduleItemRepository.findByIdAndMemberId(77L, member.id)).thenReturn(null)

        val exception = assertThrows(BusinessException::class.java) {
            writeService.delete(ScheduleItemCommand.Delete(member.id.toString(), 77L))
        }

        assertEquals(ErrorCode.SCHEDULE_ITEM_NOT_FOUND, exception.errorCode)
        verify(scheduleItemRepository, never()).delete(any(ScheduleItem::class.java))
    }

    @Test
    fun `query passes UTC range and open status through owner scoped repository`() {
        val member = member()
        val from = Instant.parse("2026-07-03T15:00:00Z")
        val to = Instant.parse("2026-07-04T15:00:00Z")
        val item = scheduleItem(member = member, dueAt = Instant.parse("2026-07-04T03:00:00Z"))
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))
        `when`(scheduleItemRepository.findAllForMemberInRange(member.id, from, to, false))
            .thenReturn(listOf(item))

        val results = queryService.getScheduleItems(
            ScheduleItemQuery(member.id.toString(), from, to, "open")
        )

        assertEquals(listOf(item.id), results.map { it.itemId })
        verify(scheduleItemRepository).findAllForMemberInRange(member.id, from, to, false)
    }

    @Test
    fun `query rejects reversed range before repository access`() {
        val instant = Instant.parse("2026-07-04T00:00:00Z")

        val exception = assertThrows(BusinessException::class.java) {
            queryService.getScheduleItems(
                ScheduleItemQuery("1", instant, instant, "all")
            )
        }

        assertEquals(ErrorCode.INVALID_INPUT, exception.errorCode)
        verify(memberRepository, never()).findById(1L)
    }

    @Test
    fun `query rejects unsupported status`() {
        val member = member()
        `when`(memberRepository.findById(member.id)).thenReturn(Optional.of(member))

        val exception = assertThrows(BusinessException::class.java) {
            queryService.getScheduleItems(
                ScheduleItemQuery(
                    member.id.toString(),
                    Instant.parse("2026-07-04T00:00:00Z"),
                    Instant.parse("2026-07-05T00:00:00Z"),
                    "archived"
                )
            )
        }

        assertEquals(ErrorCode.INVALID_INPUT, exception.errorCode)
        verify(scheduleItemRepository, never()).findAllForMemberInRange(
            member.id,
            Instant.parse("2026-07-04T00:00:00Z"),
            Instant.parse("2026-07-05T00:00:00Z"),
            null
        )
    }

    private fun stubAuditedSave() {
        `when`(scheduleItemRepository.saveAndFlush(any(ScheduleItem::class.java))).thenAnswer { invocation ->
            (invocation.arguments[0] as ScheduleItem).apply {
                createdAt = createdAt ?: now
                updatedAt = now
            }
        }
    }

    private fun scheduleItem(
        member: Member,
        dueAt: Instant? = null,
        completed: Boolean = false
    ): ScheduleItem {
        return ScheduleItem(
            id = 50L,
            member = member,
            type = ScheduleItemType.ASSIGNMENT,
            title = "Original",
            dueAt = dueAt,
            completed = completed,
            createdAt = now,
            updatedAt = now
        )
    }

    private fun member(university: University = university()): Member {
        return Member(
            id = 2L,
            university = university,
            major = major(university),
            email = "test@${university.emailDomain}",
            nickname = "test-user"
        )
    }

    private fun lecture(university: University): Lecture {
        val semester = Semester(
            id = 5L + university.id,
            university = university,
            academicYear = 2026,
            term = SemesterTerm.SPRING
        )
        return Lecture(
            id = 20L + university.id,
            semester = semester,
            major = major(university),
            course = Course(id = 30L + university.id, university = university, code = "CS101", name = "CS"),
            code = "CS101",
            name = "Introduction to CS",
            professor = "Prof. Akiyama",
            credit = 3
        )
    }

    private fun university(id: Long = 1L, domain: String = "tokyo.ac.jp"): University {
        return University(id = id, name = domain, emailDomain = domain)
    }

    private fun major(university: University): Major {
        return Major(id = 10L + university.id, university = university, code = "CS", name = "Computer Science")
    }
}
