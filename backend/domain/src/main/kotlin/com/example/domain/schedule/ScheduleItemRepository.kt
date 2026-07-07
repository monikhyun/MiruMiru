package com.example.domain.schedule

import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.time.Instant

interface ScheduleItemRepository : JpaRepository<ScheduleItem, Long> {
    @EntityGraph(attributePaths = ["lecture"])
    fun findByIdAndMemberId(id: Long, memberId: Long): ScheduleItem?

    @EntityGraph(attributePaths = ["lecture"])
    @Query(
        """
        select item
        from ScheduleItem item
        where item.member.id = :memberId
          and (item.dueAt is null or (item.dueAt >= :fromInstant and item.dueAt < :toInstant))
          and (:completed is null or item.completed = :completed)
        order by
          case when item.dueAt is null then 1 else 0 end,
          item.dueAt asc,
          item.createdAt desc
        """
    )
    fun findAllForMemberInRange(
        @Param("memberId") memberId: Long,
        @Param("fromInstant") from: Instant,
        @Param("toInstant") to: Instant,
        @Param("completed") completed: Boolean?
    ): List<ScheduleItem>
}
