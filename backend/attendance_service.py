"""
Database-backed attendance sessions for live camera recognition.
"""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from .database import get_connection


class AttendanceServiceError(RuntimeError):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def _json_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _lecture_context(cur, lecture_code: str) -> dict[str, Any]:
    cur.execute(
        """
        SELECT
            l.lecture_id,
            l.lecture_code,
            l.lecture_name,
            l.status::text AS lecture_status,
            a.group_id,
            sg.group_code,
            sg.group_name,
            lec.lecturer_code,
            COUNT(gm.student_id) AS expected_students
        FROM lectures l
        JOIN lecturer_course_assignments a ON a.assignment_id = l.assignment_id
        JOIN student_groups sg ON sg.group_id = a.group_id
        JOIN lecturers lec ON lec.lecturer_id = a.lecturer_id
        LEFT JOIN group_memberships gm ON gm.group_id = a.group_id
        WHERE l.lecture_code = %s
        GROUP BY l.lecture_id, l.lecture_code, l.lecture_name, l.status,
                 a.group_id, sg.group_code, sg.group_name, lec.lecturer_code
        """,
        (lecture_code,),
    )
    row = cur.fetchone()
    if row is None:
        raise AttendanceServiceError(f"Lecture {lecture_code} was not found", 404)
    return {
        "lecture_id": row[0],
        "lecture_code": row[1],
        "lecture_name": row[2],
        "lecture_status": row[3],
        "group_id": row[4],
        "group_code": row[5],
        "group_name": row[6],
        "lecturer_code": row[7],
        "expected_students": int(row[8] or 0),
    }


def _active_session_status(cur, lecture_id: int) -> str | None:
    cur.execute(
        """
        SELECT status
        FROM attendance_sessions
        WHERE lecture_id = %s
        """,
        (lecture_id,),
    )
    row = cur.fetchone()
    return row[0] if row else None


def _attendance_summary(cur, context: dict[str, Any]) -> dict[str, Any]:
    cur.execute(
        """
        SELECT
            s.student_code,
            s.full_name,
            COALESCE(ar.status::text, 'Absent') AS status,
            ar.first_seen_at,
            ar.last_seen_at,
            COALESCE(ar.total_absence_minutes, 0) AS total_absence_minutes,
            COALESCE(ar.attendance_pct, 0) AS attendance_pct
        FROM students s
        JOIN group_memberships gm ON gm.student_id = s.student_id
        LEFT JOIN attendance_records ar
            ON ar.student_id = s.student_id AND ar.lecture_id = %s
        WHERE gm.group_id = %s
        ORDER BY s.full_name, s.student_code
        """,
        (context["lecture_id"], context["group_id"]),
    )
    attendance = [
        {
            "student_id": row[0],
            "student_name": row[1],
            "status": row[2],
            "first_seen_at": _json_value(row[3]),
            "last_seen_at": _json_value(row[4]),
            "total_absence_minutes": int(row[5] or 0),
            "attendance_pct": _json_value(row[6]),
        }
        for row in cur.fetchall()
    ]
    present_count = sum(1 for row in attendance if row["status"] in {"Present", "Returned"})
    absent_count = sum(1 for row in attendance if row["status"] == "Absent")
    session_status = _active_session_status(cur, context["lecture_id"])
    return {
        **context,
        "session_status": session_status,
        "present_count": present_count,
        "absent_count": absent_count,
        "attendance": attendance,
    }


def start_attendance_session(lecture_code: str, started_by_user_id: int | None) -> dict[str, Any]:
    with get_connection() as conn:
        with conn.cursor() as cur:
            context = _lecture_context(cur, lecture_code)
            cur.execute(
                """
                INSERT INTO attendance_sessions (lecture_id, started_by, started_at, ended_at, status)
                VALUES (%s, %s, NOW(), NULL, 'active')
                ON CONFLICT (lecture_id) DO UPDATE SET
                    started_by = EXCLUDED.started_by,
                    started_at = NOW(),
                    ended_at = NULL,
                    status = 'active',
                    updated_at = NOW()
                """,
                (context["lecture_id"], started_by_user_id),
            )
            cur.execute(
                """
                INSERT INTO attendance_records (
                    student_id, lecture_id, status, first_seen_at, last_seen_at,
                    total_absence_minutes, attendance_pct
                )
                SELECT gm.student_id, %s, 'Absent'::attendance_status_type, NULL, NULL, 0, 0
                FROM group_memberships gm
                WHERE gm.group_id = %s
                ON CONFLICT (student_id, lecture_id) DO UPDATE SET
                    status = 'Absent'::attendance_status_type,
                    first_seen_at = NULL,
                    last_seen_at = NULL,
                    total_absence_minutes = 0,
                    attendance_pct = 0,
                    updated_at = NOW()
                """,
                (context["lecture_id"], context["group_id"]),
            )
            cur.execute(
                "UPDATE lectures SET status = 'in_progress', updated_at = NOW() WHERE lecture_id = %s",
                (context["lecture_id"],),
            )
            return {
                "message": f"Session started for lecture {lecture_code}",
                "status": "started",
                **_attendance_summary(cur, context),
            }


def stop_attendance_session(lecture_code: str) -> dict[str, Any]:
    with get_connection() as conn:
        with conn.cursor() as cur:
            context = _lecture_context(cur, lecture_code)
            cur.execute(
                """
                UPDATE attendance_sessions
                SET ended_at = NOW(), status = 'completed', updated_at = NOW()
                WHERE lecture_id = %s
                """,
                (context["lecture_id"],),
            )
            cur.execute(
                "UPDATE lectures SET status = 'analyzed', updated_at = NOW() WHERE lecture_id = %s",
                (context["lecture_id"],),
            )
            return {
                "message": f"Session stopped for lecture {lecture_code}",
                "status": "stopped",
                **_attendance_summary(cur, context),
            }


def get_attendance(lecture_code: str) -> dict[str, Any]:
    with get_connection() as conn:
        with conn.cursor() as cur:
            context = _lecture_context(cur, lecture_code)
            return _attendance_summary(cur, context)


def mark_student_present(
    lecture_code: str,
    student_code: str,
    emotion_data: dict[str, Any],
) -> dict[str, Any] | None:
    seen_at = datetime.now(timezone.utc)
    with get_connection() as conn:
        with conn.cursor() as cur:
            context = _lecture_context(cur, lecture_code)
            if _active_session_status(cur, context["lecture_id"]) != "active":
                raise AttendanceServiceError(
                    f"Attendance session for {lecture_code} is not active",
                    409,
                )
            cur.execute(
                """
                SELECT s.student_id, s.student_code, s.full_name
                FROM students s
                JOIN group_memberships gm ON gm.student_id = s.student_id
                WHERE s.student_code = %s AND gm.group_id = %s
                LIMIT 1
                """,
                (student_code, context["group_id"]),
            )
            student = cur.fetchone()
            if student is None:
                return None

            student_pk, resolved_code, student_name = student
            cur.execute(
                """
                INSERT INTO attendance_records (
                    student_id, lecture_id, status, first_seen_at, last_seen_at,
                    total_absence_minutes, attendance_pct
                )
                VALUES (%s, %s, 'Present', %s, %s, 0, 100)
                ON CONFLICT (student_id, lecture_id) DO UPDATE SET
                    status = 'Present',
                    first_seen_at = COALESCE(attendance_records.first_seen_at, EXCLUDED.first_seen_at),
                    last_seen_at = EXCLUDED.last_seen_at,
                    total_absence_minutes = 0,
                    attendance_pct = 100,
                    updated_at = NOW()
                """,
                (student_pk, context["lecture_id"], seen_at, seen_at),
            )
            cur.execute(
                """
                INSERT INTO emotion_records (
                    student_id, lecture_id, recorded_at, time_minute, emotion,
                    confidence, engagement_score, focus_score, is_present,
                    left_room, absence_duration_minutes, source, model_name
                )
                VALUES (%s, %s, %s, 0, %s, %s, %s, %s, TRUE, FALSE, 0,
                        'live_camera', 'EduPulse_v1.0')
                RETURNING record_id
                """,
                (
                    student_pk,
                    context["lecture_id"],
                    seen_at,
                    emotion_data.get("emotion", "Neutral"),
                    float(emotion_data.get("confidence", 0.5)),
                    float(emotion_data.get("engagement_score", 0.65)),
                    float(emotion_data.get("focus_score", 0.5)),
                ),
            )
            record_id = int(cur.fetchone()[0])
            return {
                "record_id": record_id,
                "student_id": resolved_code,
                "student_name": student_name,
                "lecture_id": lecture_code,
                "timestamp": seen_at.isoformat(),
                "emotion": emotion_data.get("emotion", "Neutral"),
                "confidence": float(emotion_data.get("confidence", 0.5)),
                "engagement_score": float(emotion_data.get("engagement_score", 0.65)),
                "focus_score": float(emotion_data.get("focus_score", 0.5)),
                "attendance_status": "Present",
                "is_present": True,
                "left_room": False,
                "absence_duration_minutes": 0,
            }
