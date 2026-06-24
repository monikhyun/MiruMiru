package com.example.domain.course

import com.example.domain.common.BaseTimeEntity
import com.example.domain.member.Member
import com.example.domain.semester.SemesterTerm
import jakarta.persistence.Column
import jakarta.persistence.Entity
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
import jakarta.persistence.UniqueConstraint

@Entity
@Table(
    name = "course_review",
    uniqueConstraints = [
        UniqueConstraint(
            name = "uk_course_review_target_member",
            columnNames = ["course_review_target_id", "member_id"]
        )
    ],
    indexes = [
        Index(name = "idx_course_review_target_created", columnList = "course_review_target_id, created_at"),
        Index(name = "idx_course_review_member_created", columnList = "member_id, created_at")
    ]
)
class CourseReview(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "course_review_target_id", nullable = false)
    val target: CourseReviewTarget,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "member_id", nullable = false)
    val member: Member,

    @Column(name = "academic_year", nullable = false)
    var academicYear: Int,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    var term: SemesterTerm,

    @Column(name = "professor_display_name", nullable = false)
    var professorDisplayName: String,

    @Column(name = "overall_rating", nullable = false)
    var overallRating: Int,

    @Column(nullable = false)
    var difficulty: Int,

    @Column(nullable = false)
    var workload: Int,

    @Column(name = "would_take_again", nullable = false)
    var wouldTakeAgain: Boolean,

    @Column(nullable = false, columnDefinition = "TEXT")
    var content: String,

    @Column(name = "professor_rating")
    var professorRating: Int? = null,

    @Column(name = "professor_content", columnDefinition = "TEXT")
    var professorContent: String? = null
) : BaseTimeEntity() {
    fun update(
        academicYear: Int,
        term: SemesterTerm,
        professorDisplayName: String,
        overallRating: Int,
        difficulty: Int,
        workload: Int,
        wouldTakeAgain: Boolean,
        content: String,
        professorRating: Int?,
        professorContent: String?
    ) {
        this.academicYear = academicYear
        this.term = term
        this.professorDisplayName = professorDisplayName
        this.overallRating = overallRating
        this.difficulty = difficulty
        this.workload = workload
        this.wouldTakeAgain = wouldTakeAgain
        this.content = content
        this.professorRating = professorRating
        this.professorContent = professorContent
    }
}
