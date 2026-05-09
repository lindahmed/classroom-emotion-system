-- =============================================================================
-- EduPulse AI — PostgreSQL Database Schema
-- Full university classroom emotion detection system
-- =============================================================================

-- Drop existing objects in reverse dependency order
DROP VIEW IF EXISTS vw_confusion_spikes CASCADE;
DROP VIEW IF EXISTS vw_lecture_summary CASCADE;
DROP VIEW IF EXISTS vw_student_engagement CASCADE;
DROP VIEW IF EXISTS vw_emotion_records_flat CASCADE;
DROP VIEW IF EXISTS vw_lecture_schedule CASCADE;

DROP TABLE IF EXISTS system_settings CASCADE;
DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS alert_recipients CASCADE;
DROP TABLE IF EXISTS alerts CASCADE;
DROP TABLE IF EXISTS reports CASCADE;
DROP TABLE IF EXISTS password_reset_tokens CASCADE;
DROP TABLE IF EXISTS login_sessions CASCADE;
DROP TABLE IF EXISTS attendance_sessions CASCADE;
DROP TABLE IF EXISTS attendance_records CASCADE;
DROP TABLE IF EXISTS emotion_records CASCADE;
DROP TABLE IF EXISTS lectures CASCADE;
DROP TABLE IF EXISTS lecturer_course_assignments CASCADE;
DROP TABLE IF EXISTS group_memberships CASCADE;
DROP TABLE IF EXISTS student_groups CASCADE;
DROP TABLE IF EXISTS semester_weeks CASCADE;
DROP TABLE IF EXISTS courses CASCADE;
DROP TABLE IF EXISTS student_face_photos CASCADE;
DROP TABLE IF EXISTS students CASCADE;
DROP TABLE IF EXISTS lecturers CASCADE;
DROP TABLE IF EXISTS admins CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS semesters CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;
DROP TABLE IF EXISTS departments CASCADE;

DROP TYPE IF EXISTS report_status CASCADE;
DROP TYPE IF EXISTS report_type CASCADE;
DROP TYPE IF EXISTS alert_type CASCADE;
DROP TYPE IF EXISTS alert_severity CASCADE;
DROP TYPE IF EXISTS source_type CASCADE;
DROP TYPE IF EXISTS assignment_role CASCADE;
DROP TYPE IF EXISTS attendance_status_type CASCADE;
DROP TYPE IF EXISTS week_status CASCADE;
DROP TYPE IF EXISTS lecture_status CASCADE;
DROP TYPE IF EXISTS emotion_type CASCADE;
DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS degree_level CASCADE;

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- ENUM TYPES
-- =============================================================================

CREATE TYPE user_role AS ENUM ('admin', 'lecturer', 'student');
CREATE TYPE emotion_type AS ENUM ('Happy', 'Neutral', 'Confused', 'Bored');
CREATE TYPE lecture_status AS ENUM ('scheduled', 'in_progress', 'analyzed', 'cancelled');
CREATE TYPE week_status AS ENUM ('scheduled', 'active', 'completed');
CREATE TYPE attendance_status_type AS ENUM ('Present', 'Absent', 'Left', 'Returned');
CREATE TYPE assignment_role AS ENUM ('primary', 'co_teacher', 'assistant');
CREATE TYPE source_type AS ENUM ('mock_video', 'live_camera', 'video_file', 'manual');
CREATE TYPE alert_severity AS ENUM ('info', 'warning', 'critical');
CREATE TYPE alert_type AS ENUM ('confusion_spike', 'boredom_spike', 'low_engagement', 'absence', 'system');
CREATE TYPE report_type AS ENUM ('lecture_summary', 'student_report', 'weekly_summary', 'semester_report', 'course_report');
CREATE TYPE report_status AS ENUM ('generating', 'completed', 'failed');
CREATE TYPE degree_level AS ENUM ('Undergraduate', 'Graduate', 'PhD');

-- =============================================================================
-- TABLES (creation order — dependencies first)
-- =============================================================================

-- 1. Departments
CREATE TABLE departments (
    department_id    SERIAL PRIMARY KEY,
    department_name  VARCHAR(100) NOT NULL UNIQUE,
    department_code  VARCHAR(10) NOT NULL UNIQUE,
    building         VARCHAR(100),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE departments IS 'University academic departments';

-- 2. Rooms
CREATE TABLE rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(20) NOT NULL,
    building         VARCHAR(100),
    capacity         INTEGER DEFAULT 30,
    room_type        VARCHAR(50) DEFAULT 'Lecture Hall',
    equipment        TEXT[],
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (room_number, building)
);
COMMENT ON TABLE rooms IS 'Classroom and lecture hall inventory';

-- 3. Semesters
CREATE TABLE semesters (
    semester_id      VARCHAR(20) PRIMARY KEY,
    semester_name    VARCHAR(50) NOT NULL,
    start_date       DATE NOT NULL,
    end_date         DATE NOT NULL,
    is_active        BOOLEAN DEFAULT FALSE,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT chk_semester_dates CHECK (end_date > start_date)
);
COMMENT ON TABLE semesters IS 'Academic semester definitions';

-- 4. Users (unified authentication)
CREATE TABLE users (
    user_id          SERIAL PRIMARY KEY,
    username         VARCHAR(50) NOT NULL UNIQUE,
    email            VARCHAR(255) NOT NULL UNIQUE,
    password_hash    VARCHAR(255) NOT NULL,
    role             user_role NOT NULL DEFAULT 'student',
    institution_id   VARCHAR(20) UNIQUE,
    is_active        BOOLEAN DEFAULT TRUE,
    last_login_at    TIMESTAMP WITH TIME ZONE,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE users IS 'Unified user accounts for all system roles';

-- 5. Admins (1:1 extension)
CREATE TABLE admins (
    admin_id         SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    full_name        VARCHAR(100) NOT NULL,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE admins IS 'Admin profiles linked to user accounts';

-- 6. Lecturers
CREATE TABLE lecturers (
    lecturer_id      SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    lecturer_code    VARCHAR(10) NOT NULL UNIQUE,
    full_name        VARCHAR(100) NOT NULL,
    department_id    INTEGER REFERENCES departments(department_id) ON DELETE SET NULL,
    title            VARCHAR(50),
    specialization   VARCHAR(200),
    phone            VARCHAR(20),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE lecturers IS 'Lecturer profiles linked to user accounts';

-- 7. Students
CREATE TABLE students (
    student_id       SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    student_code     VARCHAR(20) NOT NULL UNIQUE,
    full_name        VARCHAR(100) NOT NULL,
    department_id    INTEGER REFERENCES departments(department_id) ON DELETE SET NULL,
    enrollment_year  INTEGER,
    degree_level     degree_level DEFAULT 'Undergraduate',
    phone            VARCHAR(20),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE students IS 'Student profiles linked to user accounts';

-- 8. Student Face Photos
CREATE TABLE student_face_photos (
    photo_id         BIGSERIAL PRIMARY KEY,
    student_id       INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    source_url       TEXT NOT NULL,
    source_file_id   VARCHAR(128),
    local_path       VARCHAR(500),
    is_downloaded    BOOLEAN NOT NULL DEFAULT FALSE,
    download_error   TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (student_id, source_url)
);
COMMENT ON TABLE student_face_photos IS 'Known-face photo metadata imported from StudentPicsDataset.csv';

-- 9. Courses
CREATE TABLE courses (
    course_id        SERIAL PRIMARY KEY,
    course_code      VARCHAR(20) NOT NULL UNIQUE,
    course_name      VARCHAR(200) NOT NULL,
    department_id    INTEGER REFERENCES departments(department_id) ON DELETE SET NULL,
    credit_hours     INTEGER NOT NULL DEFAULT 3,
    description      TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT chk_credits CHECK (credit_hours > 0 AND credit_hours <= 6)
);
COMMENT ON TABLE courses IS 'Course catalog';

-- 10. Semester Weeks
CREATE TABLE semester_weeks (
    week_id          SERIAL PRIMARY KEY,
    semester_id      VARCHAR(20) NOT NULL REFERENCES semesters(semester_id) ON DELETE CASCADE,
    academic_week    INTEGER NOT NULL,
    week_label       VARCHAR(20) NOT NULL,
    start_date       DATE NOT NULL,
    end_date         DATE NOT NULL,
    status           week_status DEFAULT 'scheduled',
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (semester_id, academic_week),
    CONSTRAINT chk_week_dates CHECK (end_date > start_date)
);
COMMENT ON TABLE semester_weeks IS 'Week definitions within a semester';

-- 11. Student Groups
CREATE TABLE student_groups (
    group_id         SERIAL PRIMARY KEY,
    group_code       VARCHAR(20) NOT NULL,
    group_name       VARCHAR(50) NOT NULL,
    course_id        INTEGER NOT NULL REFERENCES courses(course_id) ON DELETE CASCADE,
    semester_id      VARCHAR(20) NOT NULL REFERENCES semesters(semester_id) ON DELETE CASCADE,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (group_code, semester_id)
);
COMMENT ON TABLE student_groups IS 'Student groups/sections per course per semester';

-- 12. Group Memberships
CREATE TABLE group_memberships (
    membership_id    SERIAL PRIMARY KEY,
    group_id         INTEGER NOT NULL REFERENCES student_groups(group_id) ON DELETE CASCADE,
    student_id       INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    joined_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (group_id, student_id)
);
COMMENT ON TABLE group_memberships IS 'Which students belong to which groups';

-- 13. Lecturer Course Assignments
CREATE TABLE lecturer_course_assignments (
    assignment_id    SERIAL PRIMARY KEY,
    lecturer_id      INTEGER NOT NULL REFERENCES lecturers(lecturer_id) ON DELETE CASCADE,
    course_id        INTEGER NOT NULL REFERENCES courses(course_id) ON DELETE CASCADE,
    group_id         INTEGER NOT NULL REFERENCES student_groups(group_id) ON DELETE CASCADE,
    semester_id      VARCHAR(20) NOT NULL REFERENCES semesters(semester_id) ON DELETE CASCADE,
    role             assignment_role DEFAULT 'primary',
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (lecturer_id, course_id, group_id, semester_id)
);
COMMENT ON TABLE lecturer_course_assignments IS 'Which lecturer teaches which course-group in which semester';

-- 14. Lectures
CREATE TABLE lectures (
    lecture_id       SERIAL PRIMARY KEY,
    lecture_code     VARCHAR(10) NOT NULL UNIQUE,
    lecture_name     VARCHAR(200) NOT NULL,
    assignment_id    INTEGER NOT NULL REFERENCES lecturer_course_assignments(assignment_id) ON DELETE CASCADE,
    semester_id      VARCHAR(20) NOT NULL REFERENCES semesters(semester_id) ON DELETE CASCADE,
    academic_week    INTEGER NOT NULL,
    lecture_date     DATE NOT NULL,
    day_name         VARCHAR(10) NOT NULL,
    start_time       TIME NOT NULL,
    end_time         TIME NOT NULL,
    room_id          INTEGER REFERENCES rooms(room_id) ON DELETE SET NULL,
    status           lecture_status DEFAULT 'scheduled',
    notes            TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT chk_lecture_times CHECK (end_time > start_time)
);
COMMENT ON TABLE lectures IS 'Individual lecture sessions. assignment_id resolves lecturer, course, and group via FK chain.';

-- 15. Emotion Records (core fact table)
CREATE TABLE emotion_records (
    record_id              BIGSERIAL PRIMARY KEY,
    student_id             INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    lecture_id             INTEGER NOT NULL REFERENCES lectures(lecture_id) ON DELETE CASCADE,
    recorded_at            TIMESTAMP WITH TIME ZONE NOT NULL,
    time_minute            INTEGER NOT NULL DEFAULT 0,
    emotion                emotion_type NOT NULL,
    confidence             DECIMAL(5,4) NOT NULL,
    engagement_score       DECIMAL(5,4) NOT NULL,
    focus_score            DECIMAL(5,4) NOT NULL,
    is_present             BOOLEAN NOT NULL DEFAULT TRUE,
    left_room              BOOLEAN NOT NULL DEFAULT FALSE,
    absence_duration_minutes INTEGER DEFAULT 0,
    source                 source_type DEFAULT 'live_camera',
    model_name             VARCHAR(50) DEFAULT 'EduPulse_v1.0',
    created_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT chk_confidence CHECK (confidence >= 0 AND confidence <= 1),
    CONSTRAINT chk_engagement CHECK (engagement_score >= 0 AND engagement_score <= 1),
    CONSTRAINT chk_focus CHECK (focus_score >= 0 AND focus_score <= 1),
    CONSTRAINT chk_absence CHECK (absence_duration_minutes >= 0)
);
COMMENT ON TABLE emotion_records IS 'Core emotion detection records. All context resolved via lecture_id -> assignment_id FK chain.';

-- 16. Attendance Records
CREATE TABLE attendance_records (
    attendance_id           BIGSERIAL PRIMARY KEY,
    student_id              INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
    lecture_id              INTEGER NOT NULL REFERENCES lectures(lecture_id) ON DELETE CASCADE,
    status                  attendance_status_type NOT NULL DEFAULT 'Present',
    first_seen_at           TIMESTAMP WITH TIME ZONE,
    last_seen_at            TIMESTAMP WITH TIME ZONE,
    total_absence_minutes   INTEGER DEFAULT 0,
    attendance_pct          DECIMAL(5,2),
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at              TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (student_id, lecture_id)
);
COMMENT ON TABLE attendance_records IS 'Per-student per-lecture attendance summary';

-- 17. Attendance Sessions
CREATE TABLE attendance_sessions (
    session_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    lecture_id       INTEGER NOT NULL UNIQUE REFERENCES lectures(lecture_id) ON DELETE CASCADE,
    started_by       INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    started_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    ended_at         TIMESTAMP WITH TIME ZONE,
    status           VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT chk_attendance_session_status CHECK (status IN ('active', 'completed', 'cancelled')),
    CONSTRAINT chk_attendance_session_times CHECK (ended_at IS NULL OR ended_at >= started_at)
);
COMMENT ON TABLE attendance_sessions IS 'Live attendance camera sessions per lecture';

-- 18. Login Sessions
CREATE TABLE login_sessions (
    session_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    token_hash       VARCHAR(255) NOT NULL,
    ip_address       INET,
    user_agent       TEXT,
    expires_at       TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at       TIMESTAMP WITH TIME ZONE
);
COMMENT ON TABLE login_sessions IS 'Active login sessions for token-based auth';

-- 19. Password Reset Tokens
CREATE TABLE password_reset_tokens (
    reset_id         SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    token_hash       VARCHAR(255) NOT NULL UNIQUE,
    expires_at       TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at          TIMESTAMP WITH TIME ZONE,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 20. Alerts
CREATE TABLE alerts (
    alert_id              BIGSERIAL PRIMARY KEY,
    lecture_id            INTEGER REFERENCES lectures(lecture_id) ON DELETE CASCADE,
    triggered_by_user_id  INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    alert_type            alert_type NOT NULL,
    severity              alert_severity NOT NULL DEFAULT 'warning',
    title                 VARCHAR(200) NOT NULL,
    message               TEXT NOT NULL,
    threshold_value       DECIMAL(5,4),
    actual_value          DECIMAL(5,4),
    time_minute           INTEGER,
    is_read               BOOLEAN DEFAULT FALSE,
    resolved_at           TIMESTAMP WITH TIME ZONE,
    created_at            TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE alerts IS 'Confusion spike alerts, low engagement warnings, system notifications';

-- 21. Alert Recipients
CREATE TABLE alert_recipients (
    recipient_id     BIGSERIAL PRIMARY KEY,
    alert_id         BIGINT NOT NULL REFERENCES alerts(alert_id) ON DELETE CASCADE,
    user_id          INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    is_read          BOOLEAN DEFAULT FALSE,
    read_at          TIMESTAMP WITH TIME ZONE,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (alert_id, user_id)
);

-- 22. Reports
CREATE TABLE reports (
    report_id        SERIAL PRIMARY KEY,
    generated_by     INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    report_type      report_type NOT NULL,
    title            VARCHAR(200) NOT NULL,
    parameters       JSONB,
    file_path        VARCHAR(500),
    status           report_status DEFAULT 'generating',
    started_at       TIMESTAMP WITH TIME ZONE,
    completed_at     TIMESTAMP WITH TIME ZONE,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE reports IS 'Generated reports with metadata';

-- 23. Audit Log
CREATE TABLE audit_log (
    log_id           BIGSERIAL PRIMARY KEY,
    user_id          INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    action           VARCHAR(100) NOT NULL,
    entity_type      VARCHAR(50),
    entity_id        VARCHAR(50),
    old_values       JSONB,
    new_values       JSONB,
    ip_address       INET,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE audit_log IS 'Immutable audit trail of important system actions';

-- 24. System Settings
CREATE TABLE system_settings (
    setting_id       SERIAL PRIMARY KEY,
    setting_key      VARCHAR(100) NOT NULL UNIQUE,
    setting_value    TEXT NOT NULL,
    setting_type     VARCHAR(20) DEFAULT 'string',
    description      TEXT,
    updated_by       INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
COMMENT ON TABLE system_settings IS 'System-wide configuration key-value store';

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Emotion records (most queried, largest table)
CREATE INDEX idx_emotion_records_lecture_id ON emotion_records(lecture_id);
CREATE INDEX idx_emotion_records_student_id ON emotion_records(student_id);
CREATE INDEX idx_emotion_records_recorded_at ON emotion_records(recorded_at);
CREATE INDEX idx_emotion_records_emotion ON emotion_records(emotion);
CREATE INDEX idx_emotion_records_lecture_student ON emotion_records(lecture_id, student_id);
CREATE INDEX idx_emotion_records_lecture_minute ON emotion_records(lecture_id, time_minute);

-- Lectures
CREATE INDEX idx_lectures_assignment_id ON lectures(assignment_id);
CREATE INDEX idx_lectures_semester_week ON lectures(semester_id, academic_week);
CREATE INDEX idx_lectures_date ON lectures(lecture_date);
CREATE INDEX idx_lectures_status ON lectures(status);
CREATE INDEX idx_lectures_room ON lectures(room_id);
CREATE INDEX idx_lectures_semester_week_status ON lectures(semester_id, academic_week, status);

-- Attendance
CREATE INDEX idx_attendance_lecture_id ON attendance_records(lecture_id);
CREATE INDEX idx_attendance_student_id ON attendance_records(student_id);
CREATE INDEX idx_attendance_sessions_lecture ON attendance_sessions(lecture_id);
CREATE INDEX idx_attendance_sessions_status ON attendance_sessions(status);

-- Face photos
CREATE INDEX idx_student_face_photos_student ON student_face_photos(student_id);
CREATE INDEX idx_student_face_photos_file_id ON student_face_photos(source_file_id);

-- Login sessions
CREATE INDEX idx_sessions_user_id ON login_sessions(user_id);
CREATE INDEX idx_sessions_token ON login_sessions(token_hash);
CREATE INDEX idx_sessions_expires ON login_sessions(expires_at);

-- Alerts
CREATE INDEX idx_alerts_lecture_id ON alerts(lecture_id);
CREATE INDEX idx_alerts_created_at ON alerts(created_at);
CREATE INDEX idx_alert_recipients_user ON alert_recipients(user_id, is_read);

-- Audit log
CREATE INDEX idx_audit_user_id ON audit_log(user_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_created_at ON audit_log(created_at);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);

-- Group memberships
CREATE INDEX idx_group_memberships_student ON group_memberships(student_id);
CREATE INDEX idx_group_memberships_group ON group_memberships(group_id);

-- Lecturer assignments
CREATE INDEX idx_assignments_lecturer ON lecturer_course_assignments(lecturer_id);
CREATE INDEX idx_assignments_course ON lecturer_course_assignments(course_id);
CREATE INDEX idx_assignments_semester ON lecturer_course_assignments(semester_id);

-- Semester weeks
CREATE INDEX idx_semester_weeks_semester ON semester_weeks(semester_id, academic_week);

-- Password resets
CREATE INDEX idx_password_reset_token ON password_reset_tokens(token_hash);
CREATE INDEX idx_password_reset_user ON password_reset_tokens(user_id);

-- =============================================================================
-- VIEWS (backward-compatible with current CSV column names)
-- =============================================================================

-- View 1: Replaces lecture_schedule.csv (column-compatible)
-- NOTE: Shiny expects lecture_id to be the lecture_code string and status column name to be `status`.
CREATE OR REPLACE VIEW vw_lecture_schedule AS
SELECT
    l.lecture_code  AS lecture_id,
    l.lecture_name,
    l.semester_id,
    l.academic_week,
    l.lecture_date,
    l.day_name,
    TO_CHAR(l.start_time, 'HH24:MI') AS start_time,
    TO_CHAR(l.end_time,   'HH24:MI') AS end_time,
    c.course_id,
    c.course_code,
    c.course_name,
    sg.group_id,
    sg.group_code,
    sg.group_name,
    lec.lecturer_code AS lecturer_id,
    lec.full_name     AS lecturer_name,
    r.room_number     AS room,
    (SELECT COUNT(*) FROM group_memberships gm WHERE gm.group_id = sg.group_id) AS expected_students,
    l.status::text    AS status,
    l.lecture_id      AS lecture_db_id,
    lec.lecturer_id   AS lecturer_db_id
FROM lectures l
JOIN lecturer_course_assignments a ON l.assignment_id = a.assignment_id
JOIN courses c ON a.course_id = c.course_id
JOIN student_groups sg ON a.group_id = sg.group_id
JOIN lecturers lec ON a.lecturer_id = lec.lecturer_id
LEFT JOIN rooms r ON l.room_id = r.room_id;

-- View 2: Replaces emotion_records.csv (same column names)
CREATE VIEW vw_emotion_records_flat AS
SELECT
    er.record_id,
    s.student_code   AS student_id,
    s.full_name      AS student_name,
    l.lecture_code   AS lecture_id,
    l.lecture_name,
    lec.lecturer_code AS lecturer_id,
    lec.full_name    AS lecturer_name,
    c.course_id,
    c.course_code,
    c.course_name,
    sg.group_id,
    sg.group_name,
    l.academic_week,
    er.recorded_at   AS timestamp,
    TO_CHAR(er.recorded_at, 'HH24:MI') AS time,
    er.time_minute,
    er.emotion,
    er.confidence,
    er.engagement_score,
    er.focus_score,
    CASE
        WHEN NOT er.is_present THEN 'Absent'
        WHEN er.left_room THEN 'Left'
        ELSE 'Present'
    END              AS attendance_status,
    er.is_present,
    er.left_room,
    er.absence_duration_minutes,
    er.source        AS source_type,
    er.model_name
FROM emotion_records er
JOIN students s ON er.student_id = s.student_id
JOIN lectures l ON er.lecture_id = l.lecture_id
JOIN lecturer_course_assignments a ON l.assignment_id = a.assignment_id
JOIN courses c ON a.course_id = c.course_id
JOIN student_groups sg ON a.group_id = sg.group_id
JOIN lecturers lec ON a.lecturer_id = lec.lecturer_id;

-- View 3: Student engagement metrics for reports/clustering
CREATE VIEW vw_student_engagement AS
SELECT
    s.student_id,
    s.student_code,
    s.full_name      AS student_name,
    sg.group_id,
    sg.group_code,
    c.course_id,
    c.course_code,
    COUNT(er.record_id) AS total_records,
    AVG(er.engagement_score) AS avg_engagement,
    AVG(er.focus_score) AS avg_focus,
    AVG(er.confidence) AS avg_confidence,
    COALESCE(SUM(CASE WHEN er.emotion = 'Confused' THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*)::FLOAT, 0), 0) AS confusion_rate,
    COALESCE(SUM(CASE WHEN er.emotion = 'Bored' THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*)::FLOAT, 0), 0) AS boredom_rate,
    COALESCE(SUM(CASE WHEN er.emotion = 'Happy' THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*)::FLOAT, 0), 0) AS happiness_rate,
    COALESCE(SUM(er.absence_duration_minutes), 0) AS total_absence_minutes
FROM students s
JOIN group_memberships gm ON s.student_id = gm.student_id
JOIN student_groups sg ON gm.group_id = sg.group_id
JOIN courses c ON sg.course_id = c.course_id
LEFT JOIN emotion_records er ON s.student_id = er.student_id
GROUP BY s.student_id, s.student_code, s.full_name, sg.group_id, sg.group_code, c.course_id, c.course_code;

-- View 4: Dashboard metric cards
CREATE VIEW vw_lecture_summary AS
SELECT
    l.lecture_id,
    l.lecture_code,
    l.lecture_name,
    l.academic_week,
    l.lecture_date,
    c.course_code,
    lec.full_name    AS lecturer_name,
    COUNT(DISTINCT er.student_id) AS total_students,
    SUM(CASE WHEN er.is_present THEN 1 ELSE 0 END) AS present_count,
    AVG(er.engagement_score) AS avg_engagement,
    AVG(er.focus_score) AS avg_focus,
    COALESCE(SUM(CASE WHEN er.emotion = 'Confused' THEN 1 ELSE 0 END)::DECIMAL /
        NULLIF(SUM(CASE WHEN er.is_present THEN 1 ELSE 0 END), 0), 0) AS confusion_rate,
    MODE() WITHIN GROUP (ORDER BY er.emotion) AS dominant_emotion
FROM lectures l
JOIN lecturer_course_assignments a ON l.assignment_id = a.assignment_id
JOIN courses c ON a.course_id = c.course_id
JOIN lecturers lec ON a.lecturer_id = lec.lecturer_id
LEFT JOIN emotion_records er ON l.lecture_id = er.lecture_id
GROUP BY l.lecture_id, l.lecture_code, l.lecture_name, l.academic_week, l.lecture_date, c.course_code, lec.full_name;

-- View 5: Confusion spike detection
CREATE VIEW vw_confusion_spikes AS
SELECT
    er.lecture_id,
    l.lecture_name,
    er.time_minute,
    SUM(CASE WHEN er.emotion = 'Confused' THEN 1 ELSE 0 END) AS confusion_count,
    SUM(CASE WHEN er.is_present THEN 1 ELSE 0 END) AS total_present,
    ROUND(
        SUM(CASE WHEN er.emotion = 'Confused' THEN 1 ELSE 0 END)::DECIMAL /
        GREATEST(1, SUM(CASE WHEN er.is_present THEN 1 ELSE 0 END)),
        3
    ) AS confusion_rate
FROM emotion_records er
JOIN lectures l ON er.lecture_id = l.lecture_id
GROUP BY er.lecture_id, l.lecture_name, er.time_minute
HAVING ROUND(
    SUM(CASE WHEN er.emotion = 'Confused' THEN 1 ELSE 0 END)::DECIMAL /
    GREATEST(1, SUM(CASE WHEN er.is_present THEN 1 ELSE 0 END)),
    3
) > 0.30;

-- =============================================================================
-- TRIGGER: auto-update updated_at
-- =============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables with updated_at
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT table_name FROM information_schema.columns
        WHERE column_name = 'updated_at'
        AND table_schema = 'public'
        GROUP BY table_name
    LOOP
        EXECUTE format('
            CREATE TRIGGER set_updated_at
                BEFORE UPDATE ON %I
                FOR EACH ROW
                EXECUTE FUNCTION update_updated_at();
        ', t);
    END LOOP;
END;
$$;
