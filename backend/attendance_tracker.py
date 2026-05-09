from __future__ import annotations

import time
from datetime import datetime, timezone

from .storage import get_attendance_row, get_lecture_session_start, get_session_attendance, upsert_attendance

class AttendanceTracker:
    def __init__(self):
        # Kept for backward compatibility, but source of truth is now DB.
        self.sessions = {}

    def start_session(self, lecture_id: str) -> None:
        """Mark a lecture session as started (used to compute time_minute)."""
        self.sessions.setdefault(lecture_id, {})
        self.sessions[lecture_id]["__started_at_ts"] = time.time()

    def get_time_minute(self, lecture_id: str) -> int:
        started = self.sessions.get(lecture_id, {}).get("__started_at_ts")
        if not started:
            # Fallback to DB session start (survives restarts).
            started_at = get_lecture_session_start(lecture_id)
            if not started_at:
                return 0
            # Cache for future calls.
            try:
                started_ts = float(started_at.timestamp())
            except Exception:
                return 0
            self.sessions.setdefault(lecture_id, {})
            self.sessions[lecture_id]["__started_at_ts"] = started_ts
            started = started_ts
        return max(0, int((time.time() - float(started)) // 60))

    def update_attendance(self, lecture_id, student_id):
        """Update attendance in DB based on time since last seen."""
        now_ts = time.time()
        now_dt = datetime.now(timezone.utc)

        cached = self.sessions.get(lecture_id, {}).get(student_id)
        if cached:
            prev_status = cached.get("status") or "Absent"
            total_absence = int(cached.get("total_absence_minutes") or 0)
            last_seen_ts = cached.get("last_seen")
            delta_seconds = max(0.0, now_ts - float(last_seen_ts or now_ts))
        else:
            row = get_attendance_row(student_id, lecture_id)
            if not row:
                upsert_attendance(
                    student_code=student_id,
                    lecture_code=lecture_id,
                    status="Present",
                    first_seen_at=now_dt,
                    last_seen_at=now_dt,
                    total_absence_minutes=0,
                )
                self._cache(lecture_id, student_id, now_ts, "Present", 0)
                return

            last_seen_at = row.get("last_seen_at")
            prev_status = row.get("status") or "Absent"
            total_absence = int(row.get("total_absence_minutes") or 0)

            if last_seen_at is None:
                delta_seconds = 0
            else:
                delta_seconds = max(0.0, (now_dt - last_seen_at).total_seconds())

        # This function is only called when the student is seen NOW.
        # If it has been a while since last seen, they are returning/present — not leaving.
        if delta_seconds > 30:
            new_status = "Returned" if prev_status in ("Left", "Absent") else "Present"
            total_absence += max(1, int(delta_seconds // 60))
        else:
            new_status = "Returned" if prev_status == "Left" else "Present"

        upsert_attendance(
            student_code=student_id,
            lecture_code=lecture_id,
            status=new_status,
            last_seen_at=now_dt,
            total_absence_minutes=total_absence,
        )
        self._cache(lecture_id, student_id, now_ts, new_status, total_absence)
        return

    def get_attendance_status(self, lecture_id, student_id):
        row = get_attendance_row(student_id, lecture_id)
        if row and row.get("status"):
            return row["status"]
        return "Absent"

    def get_session_status(self, lecture_id):
        # DB-backed: return a dict keyed by student_id like before.
        rows = get_session_attendance(lecture_id)
        out = {}
        for r in rows:
            out[r["student_id"]] = {
                "status": r["status"],
                "last_seen_at": r.get("last_seen_at").isoformat() if r.get("last_seen_at") else None,
                "total_absence_minutes": int(r.get("total_absence_minutes") or 0),
            }
        return out

    def get_absence_minutes(self, lecture_id, student_id) -> int:
        row = get_attendance_row(student_id, lecture_id)
        return int(row.get("total_absence_minutes") or 0) if row else 0

    def _cache(self, lecture_id, student_id, ts, status, total_absence_minutes):
        self.sessions.setdefault(lecture_id, {})
        self.sessions[lecture_id][student_id] = {
            "last_seen": ts,
            "status": status,
            "total_absence_minutes": total_absence_minutes,
        }

tracker = AttendanceTracker()
