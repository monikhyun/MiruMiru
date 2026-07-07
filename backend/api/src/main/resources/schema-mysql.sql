CREATE TABLE IF NOT EXISTS chat_block (
    id BIGINT NOT NULL AUTO_INCREMENT,
    member_1_id BIGINT NOT NULL,
    member_2_id BIGINT NOT NULL,
    blocked_by_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uk_chat_block_member_pair_by_owner UNIQUE (member_1_id, member_2_id, blocked_by_id),
    CONSTRAINT fk_chat_block_member_1 FOREIGN KEY (member_1_id) REFERENCES member (id),
    CONSTRAINT fk_chat_block_member_2 FOREIGN KEY (member_2_id) REFERENCES member (id),
    CONSTRAINT fk_chat_block_blocked_by FOREIGN KEY (blocked_by_id) REFERENCES member (id),
    INDEX idx_chat_block_member1 (member_1_id),
    INDEX idx_chat_block_member2 (member_2_id)
);

SET @chat_block_pair_unique_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_block'
      AND index_name = 'uk_chat_block_member_pair'
);

SET @chat_block_pair_by_owner_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_block'
      AND index_name = 'uk_chat_block_member_pair_by_owner'
);

SET @chat_block_pair_migration_sql := IF(
    @chat_block_pair_unique_exists > 0 AND @chat_block_pair_by_owner_exists = 0,
    'ALTER TABLE chat_block DROP INDEX uk_chat_block_member_pair, ADD CONSTRAINT uk_chat_block_member_pair_by_owner UNIQUE (member_1_id, member_2_id, blocked_by_id)',
    'SELECT 1'
);
PREPARE chat_block_pair_stmt FROM @chat_block_pair_migration_sql;
EXECUTE chat_block_pair_stmt;
DEALLOCATE PREPARE chat_block_pair_stmt;

CREATE TABLE IF NOT EXISTS schema_migration_marker (
    id VARCHAR(100) NOT NULL,
    applied_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id)
);

SET @course_review_table_exists := (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'course_review'
);

SET @course_review_professor_rating_exists := (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'course_review'
      AND column_name = 'professor_rating'
);

SET @course_review_professor_rating_sql := IF(
    @course_review_table_exists > 0 AND @course_review_professor_rating_exists = 0,
    'ALTER TABLE course_review ADD COLUMN professor_rating INT NULL',
    'SELECT 1'
);
PREPARE course_review_professor_rating_stmt FROM @course_review_professor_rating_sql;
EXECUTE course_review_professor_rating_stmt;
DEALLOCATE PREPARE course_review_professor_rating_stmt;

SET @course_review_professor_content_exists := (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'course_review'
      AND column_name = 'professor_content'
);

SET @course_review_professor_content_sql := IF(
    @course_review_table_exists > 0 AND @course_review_professor_content_exists = 0,
    'ALTER TABLE course_review ADD COLUMN professor_content TEXT NULL',
    'SELECT 1'
);
PREPARE course_review_professor_content_stmt FROM @course_review_professor_content_sql;
EXECUTE course_review_professor_content_stmt;
DEALLOCATE PREPARE course_review_professor_content_stmt;

SET @course_review_rating_scale_migrated := (
    SELECT COUNT(*)
    FROM schema_migration_marker
    WHERE id = '20260620_course_review_rating_10_scale'
);

SET @course_review_rating_scale_sql := IF(
    @course_review_table_exists > 0 AND @course_review_rating_scale_migrated = 0,
    'UPDATE course_review SET overall_rating = overall_rating * 2 WHERE overall_rating BETWEEN 1 AND 5',
    'SELECT 1'
);
PREPARE course_review_rating_scale_stmt FROM @course_review_rating_scale_sql;
EXECUTE course_review_rating_scale_stmt;
DEALLOCATE PREPARE course_review_rating_scale_stmt;

INSERT IGNORE INTO schema_migration_marker (id)
SELECT '20260620_course_review_rating_10_scale'
WHERE @course_review_table_exists > 0;

CREATE TABLE IF NOT EXISTS chat_report (
    id BIGINT NOT NULL AUTO_INCREMENT,
    reporter_id BIGINT NOT NULL,
    target_id BIGINT NOT NULL,
    room_id BIGINT NULL,
    message_id BIGINT NULL,
    reason VARCHAR(100) NOT NULL,
    detail TEXT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT fk_chat_report_reporter FOREIGN KEY (reporter_id) REFERENCES member (id),
    CONSTRAINT fk_chat_report_target FOREIGN KEY (target_id) REFERENCES member (id),
    INDEX idx_chat_report_reporter_created (reporter_id, created_at),
    INDEX idx_chat_report_target_created (target_id, created_at)
);

CREATE TABLE IF NOT EXISTS schedule_item (
    id BIGINT NOT NULL AUTO_INCREMENT,
    member_id BIGINT NOT NULL,
    lecture_id BIGINT NULL,
    type VARCHAR(20) NOT NULL,
    title VARCHAR(200) NOT NULL,
    memo VARCHAR(2000) NULL,
    due_at DATETIME(6) NULL,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT fk_schedule_item_member FOREIGN KEY (member_id) REFERENCES member (id),
    CONSTRAINT fk_schedule_item_lecture FOREIGN KEY (lecture_id) REFERENCES lecture (id),
    INDEX idx_schedule_item_member_due (member_id, due_at),
    INDEX idx_schedule_item_member_completed (member_id, completed)
);
