package com.example.application.schedule

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import com.example.domain.schedule.ScheduleItemRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional(readOnly = true)
class ScheduleItemQueryService(
    private val memberRepository: MemberRepository,
    private val scheduleItemRepository: ScheduleItemRepository
) {
    fun getScheduleItems(query: ScheduleItemQuery): List<ScheduleItemResult> {
        if (!query.from.isBefore(query.to)) {
            throw BusinessException(
                ErrorCode.INVALID_INPUT,
                detail = mapOf("field" to "from", "reason" to "from must be before to")
            )
        }

        val member = findMember(query.userId)
        val completed = when (query.status.lowercase()) {
            "all" -> null
            "open" -> false
            "completed" -> true
            else -> throw BusinessException(
                ErrorCode.INVALID_INPUT,
                detail = mapOf("field" to "status", "reason" to "status must be all, open, or completed")
            )
        }

        return scheduleItemRepository.findAllForMemberInRange(
            memberId = member.id,
            from = query.from,
            to = query.to,
            completed = completed
        ).map { it.toResult() }
    }

    private fun findMember(userId: String): Member {
        val memberId = userId.toLongOrNull()
            ?: throw BusinessException(ErrorCode.UNAUTHORIZED)
        return memberRepository.findById(memberId).orElseThrow {
            BusinessException(ErrorCode.USER_NOT_FOUND)
        }
    }
}
