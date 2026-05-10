"""
storage.py — PostgreSQL-based storage for EduPulse AI
Replaces CSV-based storage with database inserts.
Dual-write: every insert also appends to the corresponding CSV file.
"""

import csv
import io
import threading
from datetime import datetime
from pathlib import Path

from .database import get_connection, execute_insert, execute_query

_DATA_DIR = Path(__file__).resolve().parents[1] / "data"
_csv_lock = threading.Lock()


def upsert_lecture_session_start(lecture_code: str, started_at: datetime | None = None):
    """Create/update a session start time for a lecture (by lecture_code)."""
    sql = """
        INSERT INTO lecture_sessions (lecture_id, started_at, status)
        SELECT
            l.lecture_id,
            %(started_at)s,
            'started'
        FROM lectures l
        WHERE l.lecture_code = %(lecture_code)s
        ON CONFLICT (lecture_id) DO UPDATE SET
            started_at = EXCLUDED.started_at,
            ended_at = NULL,
            status = 'started'
        RETURNING started_at
    """
    params = {
        "lecture_code": lecture_code,
        "started_at": started_at or datetime.now(),
    }
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                row = cur.fetchone()
                return row[0] if row else None
    except Exception:
        # If DB is not initialized (tests) or lecture doesn't exist, treat as no-op.
        return None


def get_lecture_session_start(lecture_code: str):
    """Fetch started_at for a lecture session (by lecture_code)."""
    sql = """
        SELECT ls.started_at
        FROM lecture_sessions ls
        JOIN lectures l ON l.lecture_id = ls.lecture_id
        WHERE l.lecture_code = %s
        LIMIT 1
    """
    rows = execute_query(sql, (lecture_code,))
    if not rows:
        return None
    return rows[0].get("started_at")


def get_attendance_row(student_code: str, lecture_code: str):
    """Fetch a single attendance record (if any) for a student+lecture by codes."""
    sql = """
        SELECT
            ar.status::text AS status,
            ar.first_seen_at,
            ar.last_seen_at,
            COALESCE(ar.total_absence_minutes, 0) AS total_absence_minutes
        FROM attendance_records ar
        JOIN students s ON s.student_id = ar.student_id
        JOIN lectures l ON l.lecture_id = ar.lecture_id
        WHERE s.student_code = %s AND l.lecture_code = %s
        LIMIT 1
    """
    rows = execute_query(sql, (student_code, lecture_code))
    return rows[0] if rows else None


def get_session_attendance(lecture_code: str):
    """Return all attendance rows for a lecture (for session-status)."""
    sql = """
        SELECT
            s.student_code AS student_id,
            ar.status::text AS status,
            ar.last_seen_at,
            COALESCE(ar.total_absence_minutes, 0) AS total_absence_minutes
        FROM attendance_records ar
        JOIN students s ON s.student_id = ar.student_id
        JOIN lectures l ON l.lecture_id = ar.lecture_id
        WHERE l.lecture_code = %s
        ORDER BY s.student_code
    """
    return execute_query(sql, (lecture_code,))


def append_record(record: dict):
    """Insert an emotion detection record into PostgreSQL.

    Args:
        record: dict with keys matching emotion record fields.
                Expected keys: student_code, lecture_code, recorded_at,
                emotion, confidence, engagement_score, focus_score, etc.
    """
    sql = """
        INSERT INTO emotion_records (
            student_id, lecture_id, recorded_at, time_minute,
            emotion, confidence, engagement_score, focus_score,
            is_present, left_room, absence_duration_minutes,
            source, model_name
        ) VALUES (
            (SELECT student_id FROM students WHERE student_code = %(student_code)s),
            (SELECT lecture_id FROM lectures WHERE lecture_code = %(lecture_code)s),
            %(recorded_at)s, %(time_minute)s,
            %(emotion)s, %(confidence)s, %(engagement_score)s, %(focus_score)s,
            %(is_present)s, %(left_room)s, %(absence_duration_minutes)s,
            %(source)s, %(model_name)s
        )
    """

    params = {
        "student_code": record.get("student_code", record.get("student_id")),
        "lecture_code": record.get("lecture_code", record.get("lecture_id")),
        "recorded_at": record.get("recorded_at", record.get("timestamp", datetime.now())),
        "time_minute": record.get("time_minute", 0),
        "emotion": record.get("emotion", "Neutral"),
        "confidence": record.get("confidence", 0.0),
        "engagement_score": record.get("engagement_score", 0.0),
        "focus_score": record.get("focus_score", 0.0),
        "is_present": record.get("is_present", True),
        "left_room": record.get("left_room", False),
        "absence_duration_minutes": record.get("absence_duration_minutes", 0),
        "source": record.get("source", record.get("source_type", "live_camera")),
        "model_name": record.get("model_name", "EduPulse_v1.0"),
    }

    return execute_insert(sql, params)


def upsert_attendance(student_code: str, lecture_code: str, status: str = "Present",
                       first_seen_at: datetime = None, last_seen_at: datetime = None,
                       total_absence_minutes: int = 0):
    """Insert or update an attendance record for a student in a lecture."""
    sql = """
        INSERT INTO attendance_records (
            student_id, lecture_id, status, first_seen_at, last_seen_at,
            total_absence_minutes, attendance_pct
        ) VALUES (
            (SELECT student_id FROM students WHERE student_code = %(student_code)s),
            (SELECT lecture_id FROM lectures WHERE lecture_code = %(lecture_code)s),
            %(status)s::attendance_status_type,
            %(first_seen_at)s, %(last_seen_at)s,
            %(total_absence_minutes)s,
            GREATEST(0, 100.0 - (%(total_absence_minutes)s::DECIMAL / 60.0 * 100.0))
        )
        ON CONFLICT (student_id, lecture_id) DO UPDATE SET
            status = EXCLUDED.status,
            last_seen_at = EXCLUDED.last_seen_at,
            total_absence_minutes = EXCLUDED.total_absence_minutes,
            attendance_pct = EXCLUDED.attendance_pct,
            updated_at = NOW()
    """

    params = {
        "student_code": student_code,
        "lecture_code": lecture_code,
        "status": status,
        "first_seen_at": first_seen_at or datetime.now(),
        "last_seen_at": last_seen_at or datetime.now(),
        "total_absence_minutes": total_absence_minutes,
    }

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.rowcount


def check_and_create_alert(lecture_code: str, time_minute: int,
                            confusion_threshold: float = 0.30):
    """Check if confusion rate exceeds threshold and create an alert if so."""
    sql = """
        SELECT
            COUNT(*) FILTER (WHERE er.emotion = 'Confused') AS confused_count,
            COUNT(*) FILTER (WHERE er.is_present) AS present_count
        FROM emotion_records er
        JOIN lectures l ON er.lecture_id = l.lecture_id
        WHERE l.lecture_code = %s AND er.time_minute = %s
    """

    result = execute_query(sql, (lecture_code, time_minute))
    if not result:
        return None

    row = result[0]
    confused = row["confused_count"]
    present = row["present_count"]

    if present == 0:
        return None

    rate = confused / present
    if rate > confusion_threshold:
        alert_sql = """
            INSERT INTO alerts (lecture_id, alert_type, severity, title, message,
                                threshold_value, actual_value, time_minute)
            VALUES (
                (SELECT lecture_id FROM lectures WHERE lecture_code = %s),
                'confusion_spike', 'warning',
                'Confusion Spike Detected',
                %s,
                %s, %s, %s
            ) RETURNING alert_id
        """
        msg = f"Confusion rate: {rate:.1%} ({confused}/{present} students) at minute {time_minute}"
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(alert_sql, (lecture_code, msg, confusion_threshold, rate, time_minute))
                return cur.fetchone()[0]

    return None


def get_lecture_emotion_summary(lecture_code: str):
    """Get emotion summary for a specific lecture."""
    sql = """
        SELECT * FROM vw_lecture_summary WHERE lecture_code = %s
    """
    result = execute_query(sql, (lecture_code,))
    return result[0] if result else None


# ---------------------------------------------------------------------------
# CSV dual-write helpers
# ---------------------------------------------------------------------------

_EMOTION_CSV_FIELDS = [
    "record_id", "student_id", "student_name", "lecture_id", "lecture_name",
    "lecturer_id", "lecturer_name", "course_id", "course_code", "course_name",
    "group_id", "group_name", "academic_week", "timestamp", "time",
    "time_minute", "emotion", "confidence", "engagement_score", "focus_score",
    "attendance_status", "is_present", "left_room", "absence_duration_minutes",
    "source_type", "model_name",
]


def append_record_csv(record: dict) -> None:
    """Append one emotion record to data/emotion_records.csv (thread-safe)."""
    row = {
        "record_id": record.get("record_id", ""),
        "student_id": record.get("student_code", record.get("student_id", "")),
        "student_name": record.get("student_name", ""),
        "lecture_id": record.get("lecture_code", record.get("lecture_id", "")),
        "lecture_name": record.get("lecture_name", ""),
        "lecturer_id": record.get("lecturer_id", ""),
        "lecturer_name": record.get("lecturer_name", ""),
        "course_id": record.get("course_id", ""),
        "course_code": record.get("course_code", ""),
        "course_name": record.get("course_name", ""),
        "group_id": record.get("group_id", ""),
        "group_name": record.get("group_name", ""),
        "academic_week": record.get("academic_week", ""),
        "timestamp": record.get("timestamp", record.get("recorded_at", datetime.now().isoformat())),
        "time": record.get("time", datetime.now().strftime("%H:%M")),
        "time_minute": record.get("time_minute", 0),
        "emotion": record.get("emotion", "Neutral"),
        "confidence": record.get("confidence", 0.0),
        "engagement_score": record.get("engagement_score", 0.0),
        "focus_score": record.get("focus_score", 0.0),
        "attendance_status": record.get("attendance_status", "Unknown"),
        "is_present": record.get("is_present", True),
        "left_room": record.get("left_room", False),
        "absence_duration_minutes": record.get("absence_duration_minutes", 0),
        "source_type": record.get("source_type", "live_camera"),
        "model_name": record.get("model_name", "EduPulse_v1.0"),
    }

    csv_path = _DATA_DIR / "emotion_records.csv"
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    with _csv_lock:
        write_header = not csv_path.exists() or csv_path.stat().st_size == 0
        with open(csv_path, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=_EMOTION_CSV_FIELDS)
            if write_header:
                writer.writeheader()
            writer.writerow(row)


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    """Overwrite a CSV file with the given rows (thread-safe)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with _csv_lock:
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(rows)


def sync_all_csvs() -> None:
    """Dump all database tables to their corresponding CSV files."""
    _sync_students_csv()
    _sync_lecturers_csv()
    _sync_courses_csv()
    _sync_groups_csv()
    _sync_assignments_csv()
    _sync_semester_weeks_csv()
    _sync_lecture_schedule_csv()
    _sync_emotion_records_csv()


def _sync_students_csv() -> None:
    rows = execute_query("SELECT student_code AS student_id, full_name AS student_name, "
                         "'N/A' AS \"group\" FROM students ORDER BY student_code")
    if rows is not None:
        _write_csv(_DATA_DIR / "students.csv", ["student_id", "student_name", "group"], rows)


def _sync_lecturers_csv() -> None:
    rows = execute_query("SELECT lecturer_code AS lecturer_id, full_name AS lecturer_name, "
                         "d.department_name AS department, u.email "
                         "FROM lecturers lec "
                         "LEFT JOIN departments d ON d.department_id = lec.department_id "
                         "LEFT JOIN users u ON u.user_id = lec.user_id "
                         "ORDER BY lec.lecturer_code")
    if rows is not None:
        _write_csv(_DATA_DIR / "lecturers.csv",
                   ["lecturer_id", "lecturer_name", "department", "email"], rows)


def _sync_courses_csv() -> None:
    rows = execute_query("SELECT course_id, course_code, course_name, department_id, "
                         "credit_hours, description, created_at, updated_at "
                         "FROM courses ORDER BY course_id")
    if rows is not None:
        _write_csv(_DATA_DIR / "courses.csv",
                   ["course_id", "course_code", "course_name", "department_id",
                    "credit_hours", "description", "created_at", "updated_at"], rows)


def _sync_groups_csv() -> None:
    rows = execute_query("SELECT sg.group_id, sg.group_name, a.course_id, a.semester_id, "
                         "COUNT(gm.student_id) AS student_count "
                         "FROM student_groups sg "
                         "JOIN lecturer_course_assignments a ON a.group_id = sg.group_id "
                         "LEFT JOIN group_memberships gm ON gm.group_id = sg.group_id "
                         "GROUP BY sg.group_id, sg.group_name, a.course_id, a.semester_id "
                         "ORDER BY sg.group_id")
    if rows is not None:
        _write_csv(_DATA_DIR / "groups.csv",
                   ["group_id", "group_name", "course_id", "semester_id", "student_count"], rows)


def _sync_assignments_csv() -> None:
    rows = execute_query("SELECT assignment_id, lecturer_id, course_id, group_id, semester_id "
                         "FROM lecturer_course_assignments ORDER BY assignment_id")
    if rows is not None:
        _write_csv(_DATA_DIR / "lecturer_course_assignments.csv",
                   ["assignment_id", "lecturer_id", "course_id", "group_id", "semester_id"], rows)


def _sync_semester_weeks_csv() -> None:
    rows = execute_query("SELECT semester_id, academic_week, week_label, "
                         "start_date, end_date, status::text AS status "
                         "FROM semester_weeks ORDER BY semester_id, academic_week")
    if rows is not None:
        _write_csv(_DATA_DIR / "semester_weeks.csv",
                   ["semester_id", "academic_week", "week_label",
                    "start_date", "end_date", "status"], rows)


def _sync_lecture_schedule_csv() -> None:
    rows = execute_query(
        "SELECT l.lecture_code AS lecture_id, l.lecture_name, "
        "a.semester_id, sw.academic_week, l.lecture_date, "
        "TO_CHAR(l.lecture_date, 'Day') AS day_name, "
        "l.start_time, l.end_time, "
        "c.course_id, c.course_code, c.course_name, "
        "a.group_id, sg.group_code, sg.group_name, "
        "lec.lecturer_id, lec.lecturer_code AS lecturer_name, "
        "r.room_name AS room, "
        "0 AS expected_students, l.status::text AS status, "
        "l.lecture_id AS lecture_db_id, lec.lecturer_id AS lecturer_db_id "
        "FROM lectures l "
        "JOIN lecturer_course_assignments a ON a.assignment_id = l.assignment_id "
        "JOIN courses c ON c.course_id = a.course_id "
        "JOIN student_groups sg ON sg.group_id = a.group_id "
        "JOIN lecturers lec ON lec.lecturer_id = a.lecturer_id "
        "LEFT JOIN rooms r ON r.room_id = l.room_id "
        "LEFT JOIN semester_weeks sw ON sw.semester_id = a.semester_id "
        "   AND sw.start_date <= l.lecture_date AND sw.end_date >= l.lecture_date "
        "ORDER BY l.lecture_date, l.start_time"
    )
    if rows is not None:
        fields = ["lecture_id", "lecture_name", "semester_id", "academic_week",
                   "lecture_date", "day_name", "start_time", "end_time",
                   "course_id", "course_code", "course_name",
                   "group_id", "group_code", "group_name",
                   "lecturer_id", "lecturer_name", "room", "expected_students",
                   "status", "lecture_db_id", "lecturer_db_id"]
        _write_csv(_DATA_DIR / "lecture_schedule.csv", fields, rows)


def _sync_emotion_records_csv() -> None:
    rows = execute_query(
        "SELECT er.record_id, s.student_code AS student_id, s.full_name AS student_name, "
        "l.lecture_code AS lecture_id, l.lecture_name, "
        "lec.lecturer_code AS lecturer_id, lec.full_name AS lecturer_name, "
        "c.course_id, c.course_code, c.course_name, "
        "sg.group_id, sg.group_name, "
        "sw.academic_week, "
        "er.recorded_at AS timestamp, "
        "TO_CHAR(er.recorded_at, 'HH24:MI') AS time, "
        "er.time_minute, er.emotion, "
        "er.confidence, er.engagement_score, er.focus_score, "
        "COALESCE(ar.status::text, 'Unknown') AS attendance_status, "
        "er.is_present, er.left_room, er.absence_duration_minutes, "
        "er.source AS source_type, er.model_name "
        "FROM emotion_records er "
        "JOIN students s ON s.student_id = er.student_id "
        "JOIN lectures l ON l.lecture_id = er.lecture_id "
        "JOIN lecturer_course_assignments a ON a.assignment_id = l.assignment_id "
        "JOIN courses c ON c.course_id = a.course_id "
        "JOIN student_groups sg ON sg.group_id = a.group_id "
        "JOIN lecturers lec ON lec.lecturer_id = a.lecturer_id "
        "LEFT JOIN attendance_records ar ON ar.student_id = er.student_id "
        "   AND ar.lecture_id = er.lecture_id "
        "LEFT JOIN semester_weeks sw ON sw.semester_id = a.semester_id "
        "   AND sw.start_date <= er.recorded_at::date AND sw.end_date >= er.recorded_at::date "
        "ORDER BY er.record_id"
    )
    if rows is not None:
        _write_csv(_DATA_DIR / "emotion_records.csv", _EMOTION_CSV_FIELDS, rows)
