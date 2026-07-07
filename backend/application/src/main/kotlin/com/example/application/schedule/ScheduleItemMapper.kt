package com.example.application.schedule

import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.domain.schedule.ScheduleItem

internal fun ScheduleItem.toResult(): ScheduleItemResult {
    return ScheduleItemResult(
        itemId = id,
        lectureId = lecture?.id,
        lectureName = lecture?.name,
        type = type.name,
        title = title,
        memo = memo,
        dueAt = dueAt,
        completed = completed,
        createdAt = createdAt ?: throw BusinessException(ErrorCode.INTERNAL_ERROR),
        updatedAt = updatedAt ?: throw BusinessException(ErrorCode.INTERNAL_ERROR)
    )
}
