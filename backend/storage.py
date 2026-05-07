"""
storage.py — PostgreSQL-based storage for EduPulse AI
Replaces CSV-based storage with database inserts.
"""

from datetime import datetime
from backend.database import get_connection, execute_insert, execute_query


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
