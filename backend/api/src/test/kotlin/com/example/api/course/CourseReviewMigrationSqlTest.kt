package com.example.api.course

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CourseReviewMigrationSqlTest {
    @Test
    fun `mysql course review migration is guarded and one shot`() {
        val sql = readResource("schema-mysql.sql")

        assertTrue(sql.contains("CREATE TABLE IF NOT EXISTS schema_migration_marker"))
        assertTrue(sql.contains("ALTER TABLE course_review ADD COLUMN professor_rating INT NULL"))
        assertTrue(sql.contains("ALTER TABLE course_review ADD COLUMN professor_content TEXT NULL"))
        assertTrue(sql.contains("WHERE id = '20260620_course_review_rating_10_scale'"))
        assertTrue(sql.contains("@course_review_rating_scale_migrated = 0"))
        assertTrue(sql.contains("UPDATE course_review SET overall_rating = overall_rating * 2 WHERE overall_rating BETWEEN 1 AND 5"))
        assertTrue(sql.contains("INSERT IGNORE INTO schema_migration_marker (id)"))
    }

    @Test
    fun `postgres course review migration mirrors marker guarded scaling and rollback notes`() {
        val sql = readResource("migrations/20260620_course_review_rating_10_scale_postgresql.sql")

        assertTrue(sql.contains("CREATE TABLE IF NOT EXISTS schema_migration_marker"))
        assertTrue(sql.contains("ALTER TABLE course_review ADD COLUMN IF NOT EXISTS professor_rating INTEGER"))
        assertTrue(sql.contains("ALTER TABLE course_review ADD COLUMN IF NOT EXISTS professor_content TEXT"))
        assertTrue(sql.contains("WHERE id = '20260620_course_review_rating_10_scale'"))
        assertTrue(sql.contains("UPDATE course_review"))
        assertTrue(sql.contains("SET overall_rating = overall_rating * 2"))
        assertTrue(sql.contains("WHERE overall_rating BETWEEN 1 AND 5"))
        assertTrue(sql.contains("ON CONFLICT (id) DO NOTHING"))
        assertTrue(sql.contains("Emergency rollback only"))
    }

    private fun readResource(path: String): String {
        val resource = requireNotNull(javaClass.classLoader.getResource(path)) {
            "Missing test resource: $path"
        }
        return resource.readText()
    }
}
