package com.example.api.schedule

import com.example.api.common.ApiResponse
import com.example.application.exception.ErrorCode
import com.example.application.exception.business.BusinessException
import com.example.application.schedule.ScheduleItemCommand
import com.example.application.schedule.ScheduleItemQuery
import com.example.application.schedule.ScheduleItemQueryService
import com.example.application.schedule.ScheduleItemWriteService
import jakarta.validation.Valid
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

@RestController
@RequestMapping("/api/v1/schedule-items")
class ScheduleItemController(
    private val scheduleItemQueryService: ScheduleItemQueryService,
    private val scheduleItemWriteService: ScheduleItemWriteService
) {
    @GetMapping
    fun getScheduleItems(
        @AuthenticationPrincipal userId: String,
        @RequestParam from: String,
        @RequestParam to: String,
        @RequestParam(defaultValue = "all") status: String
    ): ResponseEntity<ApiResponse<List<ScheduleItemResponses.Item>>> {
        val items = scheduleItemQueryService.getScheduleItems(
            ScheduleItemQuery(
                userId = userId,
                from = parseInstant("from", from),
                to = parseInstant("to", to),
                status = status
            )
        )
        return ResponseEntity.ok(ApiResponse.ok(items.map(ScheduleItemResponses.Item::from)))
    }

    @PostMapping
    fun createScheduleItem(
        @AuthenticationPrincipal userId: String,
        @Valid @RequestBody request: ScheduleItemRequests.Upsert
    ): ResponseEntity<ApiResponse<ScheduleItemResponses.Item>> {
        val item = scheduleItemWriteService.create(
            ScheduleItemCommand.Create(
                userId = userId,
                lectureId = request.lectureId,
                type = request.type,
                title = request.title,
                memo = request.memo,
                dueAt = request.dueAt?.toInstant(),
                completed = request.completed
            )
        )
        return ResponseEntity.ok(ApiResponse.ok(ScheduleItemResponses.Item.from(item)))
    }

    @PutMapping("/{itemId}")
    fun updateScheduleItem(
        @AuthenticationPrincipal userId: String,
        @PathVariable itemId: Long,
        @Valid @RequestBody request: ScheduleItemRequests.Upsert
    ): ResponseEntity<ApiResponse<ScheduleItemResponses.Item>> {
        val item = scheduleItemWriteService.update(
            ScheduleItemCommand.Update(
                userId = userId,
                itemId = itemId,
                lectureId = request.lectureId,
                type = request.type,
                title = request.title,
                memo = request.memo,
                dueAt = request.dueAt?.toInstant(),
                completed = request.completed
            )
        )
        return ResponseEntity.ok(ApiResponse.ok(ScheduleItemResponses.Item.from(item)))
    }

    @PatchMapping("/{itemId}/completion")
    fun updateScheduleItemCompletion(
        @AuthenticationPrincipal userId: String,
        @PathVariable itemId: Long,
        @Valid @RequestBody request: ScheduleItemRequests.Completion
    ): ResponseEntity<ApiResponse<ScheduleItemResponses.Item>> {
        val item = scheduleItemWriteService.updateCompletion(
            ScheduleItemCommand.UpdateCompletion(
                userId = userId,
                itemId = itemId,
                completed = request.completed!!
            )
        )
        return ResponseEntity.ok(ApiResponse.ok(ScheduleItemResponses.Item.from(item)))
    }

    @DeleteMapping("/{itemId}")
    fun deleteScheduleItem(
        @AuthenticationPrincipal userId: String,
        @PathVariable itemId: Long
    ): ResponseEntity<ApiResponse<Unit>> {
        scheduleItemWriteService.delete(
            ScheduleItemCommand.Delete(
                userId = userId,
                itemId = itemId
            )
        )
        return ResponseEntity.ok(ApiResponse.empty(Unit))
    }

    private fun parseInstant(field: String, value: String): Instant {
        return try {
            OffsetDateTime.parse(value).toInstant()
        } catch (_: DateTimeParseException) {
            throw BusinessException(
                ErrorCode.INVALID_INPUT,
                detail = mapOf("field" to field, "reason" to "$field must be an ISO-8601 timestamp with offset")
            )
        }
    }
}
