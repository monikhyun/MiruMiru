-- PostgreSQL reference migration for PR2 course-review professor ratings.
-- The application currently does not run a PostgreSQL migration framework; keep
-- this file as the production SQL mirror of schema-mysql.sql.

CREATE TABLE IF NOT EXISTS schema_migration_marker (
    id VARCHAR(100) PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE course_review ADD COLUMN IF NOT EXISTS professor_rating INTEGER;
ALTER TABLE course_review ADD COLUMN IF NOT EXISTS professor_content TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM schema_migration_marker
        WHERE id = '20260620_course_review_rating_10_scale'
    ) THEN
        UPDATE course_review
        SET overall_rating = overall_rating * 2
        WHERE overall_rating BETWEEN 1 AND 5;

        INSERT INTO schema_migration_marker (id)
        VALUES ('20260620_course_review_rating_10_scale')
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

-- Emergency rollback only:
-- DELETE FROM schema_migration_marker WHERE id = '20260620_course_review_rating_10_scale';
-- UPDATE course_review SET overall_rating = CEIL(overall_rating / 2.0)::INTEGER WHERE overall_rating BETWEEN 1 AND 10;
-- ALTER TABLE course_review DROP COLUMN IF EXISTS professor_content;
-- ALTER TABLE course_review DROP COLUMN IF EXISTS professor_rating;
