package com.example.api.schedule

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Positive
import jakarta.validation.constraints.Size
import java.time.OffsetDateTime

object ScheduleItemRequests {
    data class Upsert(
        @field:Positive(message = "lectureId는 양수여야 합니다")
        val lectureId: Long?,

        @field:NotBlank(message = "type은 필수입니다")
        val type: String,

        @field:NotBlank(message = "title은 필수입니다")
        @field:Size(max = 200, message = "title은 200자 이하여야 합니다")
        val title: String,

        @field:Size(max = 2000, message = "memo는 2000자 이하여야 합니다")
        val memo: String?,

        val dueAt: OffsetDateTime?,
        val completed: Boolean?
    )

    data class Completion(
        @field:NotNull(message = "completed는 필수입니다")
        val completed: Boolean?
    )
}
