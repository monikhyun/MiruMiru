package com.example.api.schedule

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ScheduleItemMigrationSqlTest {
    @Test
    fun `mysql schema creates schedule item table with ownership and range indexes`() {
        val sql = readResource("schema-mysql.sql")

        assertTrue(sql.contains("CREATE TABLE IF NOT EXISTS schedule_item"))
        assertTrue(sql.contains("FOREIGN KEY (member_id) REFERENCES member (id)"))
        assertTrue(sql.contains("FOREIGN KEY (lecture_id) REFERENCES lecture (id)"))
        assertTrue(sql.contains("idx_schedule_item_member_due"))
    }

    @Test
    fun `postgres migration stores schedule timestamps with time zone`() {
        val sql = readResource("migrations/20260704_schedule_items_postgresql.sql")

        assertTrue(sql.contains("CREATE TABLE IF NOT EXISTS schedule_item"))
        assertTrue(sql.contains("due_at TIMESTAMPTZ NULL"))
        assertTrue(sql.contains("created_at TIMESTAMPTZ NOT NULL"))
        assertTrue(sql.contains("idx_schedule_item_member_completed"))
    }

    private fun readResource(path: String): String {
        return requireNotNull(javaClass.classLoader.getResource(path)) {
            "Missing test resource: $path"
        }.readText()
    }
}
