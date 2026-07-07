package com.example.domain.schedule

import com.example.domain.lecture.Lecture
import com.example.domain.member.Member
import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EntityListeners
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Index
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.Table
import org.springframework.data.annotation.CreatedDate
import org.springframework.data.annotation.LastModifiedDate
import org.springframework.data.jpa.domain.support.AuditingEntityListener
import java.time.Instant

@Entity
@EntityListeners(AuditingEntityListener::class)
@Table(
    name = "schedule_item",
    indexes = [
        Index(name = "idx_schedule_item_member_due", columnList = "member_id, due_at"),
        Index(name = "idx_schedule_item_member_completed", columnList = "member_id, completed")
    ]
)
class ScheduleItem(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "member_id", nullable = false)
    val member: Member,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "lecture_id")
    var lecture: Lecture? = null,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    var type: ScheduleItemType,

    @Column(nullable = false, length = 200)
    var title: String,

    @Column(length = 2000)
    var memo: String? = null,

    @Column(name = "due_at")
    var dueAt: Instant? = null,

    @Column(nullable = false)
    var completed: Boolean = false,

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    var createdAt: Instant? = null,

    @LastModifiedDate
    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant? = null
) {
    fun update(
        lecture: Lecture?,
        type: ScheduleItemType,
        title: String,
        memo: String?,
        dueAt: Instant?,
        completed: Boolean?
    ) {
        this.lecture = lecture
        this.type = type
        this.title = title.trim()
        this.memo = memo
        this.dueAt = dueAt
        completed?.let { this.completed = it }
    }

    fun updateCompletion(completed: Boolean) {
        this.completed = completed
    }
}

enum class ScheduleItemType {
    QUIZ,
    MINI_TEST,
    ASSIGNMENT,
    MEMO
}
