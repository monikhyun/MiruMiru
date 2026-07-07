package com.example.application.schedule

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.lecture.Lecture
import com.example.domain.lecture.LectureRepository
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import com.example.domain.schedule.ScheduleItem
import com.example.domain.schedule.ScheduleItemRepository
import com.example.domain.schedule.ScheduleItemType
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional
class ScheduleItemWriteService(
    private val memberRepository: MemberRepository,
    private val lectureRepository: LectureRepository,
    private val scheduleItemRepository: ScheduleItemRepository
) {
    fun create(command: ScheduleItemCommand.Create): ScheduleItemResult {
        val member = findMember(command.userId)
        val lecture = findLecture(member, command.lectureId)
        val item = ScheduleItem(
            member = member,
            lecture = lecture,
            type = parseType(command.type),
            title = command.title.trim(),
            memo = command.memo,
            dueAt = command.dueAt,
            completed = command.completed ?: false
        )
        return scheduleItemRepository.saveAndFlush(item).toResult()
    }

    fun update(command: ScheduleItemCommand.Update): ScheduleItemResult {
        val member = findMember(command.userId)
        val item = findOwnedItem(command.itemId, member.id)
        item.update(
            lecture = findLecture(member, command.lectureId),
            type = parseType(command.type),
            title = command.title,
            memo = command.memo,
            dueAt = command.dueAt,
            completed = command.completed
        )
        return scheduleItemRepository.saveAndFlush(item).toResult()
    }

    fun updateCompletion(command: ScheduleItemCommand.UpdateCompletion): ScheduleItemResult {
        val member = findMember(command.userId)
        val item = findOwnedItem(command.itemId, member.id)
        item.updateCompletion(command.completed)
        return scheduleItemRepository.saveAndFlush(item).toResult()
    }

    fun delete(command: ScheduleItemCommand.Delete) {
        val member = findMember(command.userId)
        scheduleItemRepository.delete(findOwnedItem(command.itemId, member.id))
    }

    private fun findMember(userId: String): Member {
        val memberId = userId.toLongOrNull()
            ?: throw BusinessException(ErrorCode.UNAUTHORIZED)
        return memberRepository.findById(memberId).orElseThrow {
            BusinessException(ErrorCode.USER_NOT_FOUND)
        }
    }

    private fun findLecture(member: Member, lectureId: Long?): Lecture? {
        if (lectureId == null) {
            return null
        }

        val lecture = lectureRepository.findById(lectureId).orElseThrow {
            BusinessException(ErrorCode.SCHEDULE_LECTURE_INVALID)
        }
        if (lecture.semester.university.id != member.university.id) {
            throw BusinessException(ErrorCode.SCHEDULE_LECTURE_INVALID)
        }
        return lecture
    }

    private fun findOwnedItem(itemId: Long, memberId: Long): ScheduleItem {
        return scheduleItemRepository.findByIdAndMemberId(itemId, memberId)
            ?: throw BusinessException(ErrorCode.SCHEDULE_ITEM_NOT_FOUND)
    }

    private fun parseType(type: String): ScheduleItemType {
        return try {
            ScheduleItemType.valueOf(type.uppercase())
        } catch (_: IllegalArgumentException) {
            throw BusinessException(
                ErrorCode.INVALID_INPUT,
                detail = mapOf("field" to "type", "reason" to "unsupported schedule item type")
            )
        }
    }
}
