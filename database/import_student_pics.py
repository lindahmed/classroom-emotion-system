#!/usr/bin/env python3
"""
Import StudentPicsDataset.csv into PostgreSQL and the local DeepFace image store.

The importer is idempotent:
- blank Student ID rows are ignored
- duplicate Student IDs become additional face photos
- student, group, lecture, and photo metadata rows are upserted
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import secrets
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import date, time, timedelta
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV_PATH = REPO_ROOT / "StudentPicsDataset.csv"
KNOWN_FACES_DIR = REPO_ROOT / "backend" / "known_faces"

FACE_COURSE_CODE = "FACE101"
FACE_GROUP_CODE = "FACE_G01"
FACE_SEMESTER_ID = "SPRING2026"


ARABIC_WORDS = {
    "\u0645\u062d\u0645\u062f": "Mohamed",
    "\u0627\u062d\u0645\u062f": "Ahmed",
    "\u0623\u062d\u0645\u062f": "Ahmed",
    "\u0639\u0644\u0627\u0621": "Alaa",
    "\u0644\u0637\u0641\u0649": "Lotfy",
    "\u0644\u0637\u0641\u064a": "Lotfy",
    "\u0628\u064a\u0634\u0648\u0649": "Bishoy",
    "\u0645\u0631\u0642\u0633": "Morcos",
    "\u062d\u0628\u064a\u0628": "Habib",
    "\u0645\u0631\u0627\u0645": "Maram",
    "\u062a\u0627\u0645\u0631": "Tamer",
    "\u0639\u0628\u062f\u0627\u0644\u062d\u0649": "Abdelhai",
    "\u0639\u0628\u062f\u0627\u0644\u062d\u064a": "Abdelhai",
    "\u0631\u0636\u0648\u0649": "Radwa",
    "\u0634\u0631\u064a\u0641": "Sherif",
    "\u062d\u0645\u0627\u062f": "Hammad",
    "\u0646\u062f\u0649": "Nada",
    "\u0627\u0628\u0631\u0627\u0647\u064a\u0645": "Ibrahim",
    "\u0625\u0628\u0631\u0627\u0647\u064a\u0645": "Ibrahim",
    "\u0645\u0631\u064a\u0645": "Mariam",
    "\u0648\u0627\u0626\u0644": "Wael",
    "\u0627\u0644\u0628\u0648\u0631\u0635\u0644\u0649": "El Borsaly",
    "\u0627\u0644\u0628\u0648\u0631\u0635\u0644\u064a": "El Borsaly",
    "\u062d\u0633\u064a\u0646": "Hussein",
    "\u0647\u0634\u0627\u0645": "Hesham",
    "\u0641\u0631\u064a\u062f": "Farid",
    "\u0641\u0631\u062d": "Farah",
    "\u064a\u0627\u0633\u0631": "Yasser",
    "\u0632\u064a\u0646\u0647": "Zeina",
    "\u0632\u064a\u0646\u0629": "Zeina",
    "\u0633\u0627\u0644\u0645": "Salem",
    "\u0645\u0627\u0631\u064a\u0648": "Mario",
    "\u0631\u0627\u0641\u062a": "Raafat",
    "\u0631\u0623\u0641\u062a": "Raafat",
    "\u0639\u064a\u0627\u062f": "Eid",
    "\u0628\u0631\u0627\u0621": "Baraa",
    "\u0627\u064a\u0645\u0646": "Ayman",
    "\u0623\u064a\u0645\u0646": "Ayman",
    "\u0639\u0628\u062f\u0627\u0644\u0639\u0638\u064a\u0645": "Abdelazim",
    "\u0646\u0648\u0631": "Nour",
    "\u0631\u0636\u0627": "Reda",
    "\u0627\u0628\u0648\u0627\u0644\u062e\u064a\u0631": "Aboulkheir",
    "\u0645\u0639\u0627\u0630": "Moaz",
    "\u0633\u0644\u0627\u0645": "Salam",
    "\u0634\u0647\u062f": "Shahd",
    "\u0627\u0633\u0627\u0645\u0647": "Osama",
    "\u0623\u0633\u0627\u0645\u0629": "Osama",
    "\u0633\u0639\u0648\u062f": "Saud",
    "\u0639\u0628\u062f\u0627\u0644\u0644\u0647": "Abdullah",
    "\u062e\u0627\u0644\u062f": "Khaled",
    "\u0639\u0645\u0627\u0631": "Ammar",
    "\u0628\u0644\u0627\u0644": "Belal",
    "\u0627\u0634\u0631\u0641": "Ashraf",
    "\u0623\u0634\u0631\u0641": "Ashraf",
    "\u062d\u0633\u0646": "Hassan",
    "\u0627\u0646\u0633": "Anas",
    "\u0623\u0646\u0633": "Anas",
    "\u0645\u0635\u0637\u0641\u0649": "Mostafa",
    "\u0645\u0635\u0637\u0641\u064a": "Mostafa",
    "\u0645\u0643\u0627\u0648\u0649": "Mekawy",
    "\u0645\u0643\u0627\u0648\u064a": "Mekawy",
    "\u062c\u0648\u0646": "John",
    "\u0645\u0627\u062c\u062f": "Maged",
    "\u0644\u0628\u064a\u0628": "Labib",
    "\u0639\u0645\u0631": "Omar",
    "\u064a\u0648\u0633\u0641": "Youssef",
    "\u0627\u0631\u0648\u0649": "Arwa",
    "\u0623\u0631\u0648\u0649": "Arwa",
    "\u064a\u062d\u064a\u0649": "Yehia",
    "\u0633\u0627\u0644\u0645\u0647": "Salama",
    "\u0645\u062d\u0645\u0648\u062f": "Mahmoud",
    "\u0639\u0645\u0631\u0648": "Amr",
    "\u0634\u064a\u0631\u064a\u0646": "Sherine",
    "\u062d\u0633\u0646\u064a\u0646": "Hassanein",
    "\u0646\u0627\u0631\u064a\u0645\u0627\u0646": "Nariman",
    "\u0639\u0627\u062f\u0644": "Adel",
    "\u0627\u0644\u0627\u0632\u0647\u0631\u0649": "El Azhary",
    "\u0641\u0631\u064a\u062f\u0647": "Farida",
    "\u0641\u0631\u064a\u062f\u0629": "Farida",
    "\u0633\u0644\u064a\u0645": "Selim",
    "\u0627\u0644\u0627\u062f\u0647\u0645": "El Adham",
    "\u0644\u0624\u0649": "Loay",
    "\u0648\u0644\u064a\u062f": "Walid",
    "\u0627\u0628\u0648\u0627\u0644\u0645\u0639\u0627\u0637\u0649": "Aboulmaaty",
    "\u0645\u064a\u0631\u0627": "Mira",
    "\u0639\u0627\u0637\u0641": "Atef",
    "\u0635\u0627\u0644\u062d": "Saleh",
    "\u0634\u062a\u0627\u062a": "Shatat",
    "\u0647\u0646\u0627": "Hana",
    "\u0627\u064a\u0647\u0627\u0628": "Ehab",
    "\u0625\u064a\u0647\u0627\u0628": "Ehab",
    "\u0639\u0644\u0649": "Ali",
    "\u0639\u0644\u064a": "Ali",
    "\u0634\u0644\u0628\u0649": "Shalaby",
    "\u0634\u0644\u0628\u064a": "Shalaby",
    "\u0639\u0645\u0627\u062f": "Emad",
    "\u0632\u064a\u0627\u062f": "Ziad",
    "\u0627\u0644\u0633\u064a\u062f": "Elsayed",
    "\u0631\u0648\u0627\u0646": "Rawan",
    "\u0637\u0627\u0631\u0642": "Tarek",
    "\u0627\u0628\u0648\u0627\u0644\u062f\u0647\u0628": "Aboul Dahab",
    "\u0627\u062f\u0647\u0645": "Adham",
    "\u0647\u0627\u0646\u0649": "Hany",
    "\u0647\u0627\u0646\u064a": "Hany",
    "\u0627\u0633\u0645\u0627\u0639\u064a\u0644": "Ismail",
    "\u0631\u064a\u0645": "Reem",
    "\u0641\u0627\u0637\u0645\u0647": "Fatma",
    "\u0641\u0627\u0637\u0645\u0629": "Fatma",
    "\u062e\u0644\u064a\u0644": "Khalil",
    "\u0646\u0627\u0646\u0633\u0649": "Nancy",
    "\u0646\u0627\u0646\u0633\u064a": "Nancy",
    "\u0639\u0631\u0641\u0627\u062a": "Arafat",
    "\u064a\u062d\u064a\u0649": "Yehia",
    "\u0627\u0644\u062d\u0627\u0648\u0649": "El Hawy",
    "\u0627\u0644\u062d\u0627\u0648\u064a": "El Hawy",
    "\u0627\u0644\u0635\u0627\u0648\u0649": "El Sawy",
    "\u0627\u0644\u0635\u0627\u0648\u064a": "El Sawy",
    "\u0631\u0642\u064a\u0647": "Rokaya",
    "\u0631\u0642\u064a\u0629": "Rokaya",
    "\u0641\u0627\u0631\u0648\u0642": "Farouk",
    "\u062f\u0646\u064a\u0627": "Donia",
}

ARABIC_CHARS = {
    "\u0621": "a", "\u0622": "a", "\u0623": "a", "\u0624": "w", "\u0625": "e",
    "\u0626": "y", "\u0627": "a", "\u0628": "b", "\u0629": "a", "\u062a": "t",
    "\u062b": "th", "\u062c": "g", "\u062d": "h", "\u062e": "kh", "\u062f": "d",
    "\u0630": "z", "\u0631": "r", "\u0632": "z", "\u0633": "s", "\u0634": "sh",
    "\u0635": "s", "\u0636": "d", "\u0637": "t", "\u0638": "z", "\u0639": "a",
    "\u063a": "gh", "\u0640": "", "\u0641": "f", "\u0642": "q", "\u0643": "k",
    "\u0644": "l", "\u0645": "m", "\u0646": "n", "\u0647": "h", "\u0648": "w",
    "\u0649": "a", "\u064a": "y",
}


@dataclass
class StudentImportRecord:
    student_id: str
    arabic_name: str
    english_name: str
    photo_links: list[str] = field(default_factory=list)


def load_env_file(path: Path = REPO_ROOT / ".env") -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def transliterate_name(name: str) -> str:
    words = [word for word in re.split(r"\s+", name.strip()) if word]
    out = []
    for word in words:
        if word in ARABIC_WORDS:
            out.extend(ARABIC_WORDS[word].split())
            continue
        latin = "".join(ARABIC_CHARS.get(ch, ch if ch.isascii() else "") for ch in word)
        latin = re.sub(r"[^A-Za-z]+", "", latin)
        out.append(latin.capitalize() if latin else "Student")
    return " ".join(out) or "Student"


def safe_name(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9]+", "_", value.strip())
    value = re.sub(r"_+", "_", value).strip("_")
    return value[:60] or "Student"


def google_file_id(url: str) -> str:
    match = re.search(r"(?:id=|/d/)([A-Za-z0-9_-]+)", url)
    return match.group(1) if match else ""


def google_download_url(url: str) -> str:
    file_id = google_file_id(url)
    if file_id:
        return f"https://drive.google.com/uc?export=download&id={file_id}"
    return url


def parse_student_pics_csv(path: Path) -> tuple[list[StudentImportRecord], dict[str, int]]:
    rows = list(csv.DictReader(path.open(encoding="utf-8-sig")))
    by_student: dict[str, StudentImportRecord] = {}
    blank_rows = 0
    photo_rows = 0
    duplicate_photo_rows = 0

    for row in rows:
        student_id = (row.get("Student ID") or "").strip()
        arabic_name = (row.get("Student Name") or "").strip()
        photo_link = (row.get("Photo Link") or "").strip()

        if not student_id:
            blank_rows += 1
            continue

        if student_id not in by_student:
            by_student[student_id] = StudentImportRecord(
                student_id=student_id,
                arabic_name=arabic_name,
                english_name=transliterate_name(arabic_name),
            )
        elif photo_link:
            duplicate_photo_rows += 1

        if photo_link:
            photo_rows += 1
            if photo_link not in by_student[student_id].photo_links:
                by_student[student_id].photo_links.append(photo_link)

    stats = {
        "raw_rows": len(rows),
        "blank_rows": blank_rows,
        "photo_rows": photo_rows,
        "unique_students": len(by_student),
        "duplicate_photo_rows": duplicate_photo_rows,
    }
    return list(by_student.values()), stats


def db_config() -> dict[str, object]:
    load_env_file()
    return {
        "host": os.getenv("EDUPULSE_DB_HOST", "localhost"),
        "port": int(os.getenv("EDUPULSE_DB_PORT", "5432")),
        "dbname": os.getenv("EDUPULSE_DB_NAME", "edupulse_ai"),
        "user": os.getenv("EDUPULSE_DB_USER", "postgres"),
        "password": os.getenv("EDUPULSE_DB_PASSWORD", ""),
    }


def connect():
    import psycopg2

    return psycopg2.connect(**db_config())


def ensure_runtime_schema(cur) -> None:
    cur.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
    cur.execute(
        """
        SELECT character_maximum_length
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'students'
          AND column_name = 'student_code'
        """
    )
    row = cur.fetchone()
    if row and row[0] and int(row[0]) < 20:
        cur.execute("SAVEPOINT widen_student_code")
        try:
            cur.execute("ALTER TABLE students ALTER COLUMN student_code TYPE VARCHAR(20)")
        except Exception:
            cur.execute("ROLLBACK TO SAVEPOINT widen_student_code")
        finally:
            cur.execute("RELEASE SAVEPOINT widen_student_code")
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS student_face_photos (
            photo_id BIGSERIAL PRIMARY KEY,
            student_id INTEGER NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
            source_url TEXT NOT NULL,
            source_file_id VARCHAR(128),
            local_path VARCHAR(500),
            is_downloaded BOOLEAN NOT NULL DEFAULT FALSE,
            download_error TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            UNIQUE (student_id, source_url)
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS attendance_sessions (
            session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            lecture_id INTEGER NOT NULL UNIQUE REFERENCES lectures(lecture_id) ON DELETE CASCADE,
            started_by INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
            started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            ended_at TIMESTAMP WITH TIME ZONE,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            CONSTRAINT chk_attendance_session_status CHECK (status IN ('active', 'completed', 'cancelled')),
            CONSTRAINT chk_attendance_session_times CHECK (ended_at IS NULL OR ended_at >= started_at)
        )
        """
    )


def fetch_one_id(cur, sql: str, params: tuple[object, ...]) -> int:
    cur.execute(sql, params)
    row = cur.fetchone()
    if row is None:
        raise RuntimeError(f"Missing required row for query: {sql}")
    return int(row[0])


def ensure_face101_context(cur, lecturer_code: str, semester_id: str) -> tuple[int, int]:
    cur.execute(
        """
        INSERT INTO departments (department_name, department_code, building)
        VALUES ('Computer Science', 'CS', 'Science Building')
        ON CONFLICT (department_code) DO NOTHING
        """
    )
    dept_id = fetch_one_id(cur, "SELECT department_id FROM departments WHERE department_code = 'CS'", ())

    cur.execute(
        """
        INSERT INTO rooms (room_number, building, capacity, room_type, equipment)
        VALUES ('Room FACE', 'Science Building', 160, 'Computer Lab', ARRAY['camera', 'projector'])
        ON CONFLICT (room_number, building) DO NOTHING
        """
    )
    room_id = fetch_one_id(cur, "SELECT room_id FROM rooms WHERE room_number = 'Room FACE'", ())

    cur.execute(
        """
        INSERT INTO semesters (semester_id, semester_name, start_date, end_date, is_active)
        VALUES (%s, 'Spring 2026', '2026-02-09', '2026-05-31', TRUE)
        ON CONFLICT (semester_id) DO NOTHING
        """,
        (semester_id,),
    )
    semester_start = date(2026, 2, 9)
    for week in range(1, 17):
        week_start = semester_start + timedelta(days=(week - 1) * 7)
        cur.execute(
            """
            INSERT INTO semester_weeks (semester_id, academic_week, week_label, start_date, end_date, status)
            VALUES (%s, %s, %s, %s, %s,
                    CASE WHEN %s < 13 THEN 'completed'::week_status
                         WHEN %s = 13 THEN 'active'::week_status
                         ELSE 'scheduled'::week_status END)
            ON CONFLICT (semester_id, academic_week) DO NOTHING
            """,
            (
                semester_id,
                week,
                f"Week {week}",
                week_start,
                week_start + timedelta(days=6),
                week,
                week,
            ),
        )
    cur.execute(
        """
        INSERT INTO courses (course_code, course_name, department_id, credit_hours, description)
        VALUES (%s, 'Face Recognition Attendance', %s, 3,
                'Imported attendance course for StudentPicsDataset.csv')
        ON CONFLICT (course_code) DO UPDATE SET
            course_name = EXCLUDED.course_name,
            department_id = EXCLUDED.department_id,
            description = EXCLUDED.description,
            updated_at = NOW()
        RETURNING course_id
        """,
        (FACE_COURSE_CODE, dept_id),
    )
    course_id = int(cur.fetchone()[0])

    lecturer_id = ensure_lecturer(cur, lecturer_code, dept_id)

    cur.execute(
        """
        INSERT INTO student_groups (group_code, group_name, course_id, semester_id)
        VALUES (%s, 'StudentPicsDataset Group', %s, %s)
        ON CONFLICT (group_code, semester_id) DO UPDATE SET
            group_name = EXCLUDED.group_name,
            course_id = EXCLUDED.course_id,
            updated_at = NOW()
        RETURNING group_id
        """,
        (FACE_GROUP_CODE, course_id, semester_id),
    )
    group_id = int(cur.fetchone()[0])

    cur.execute(
        """
        INSERT INTO lecturer_course_assignments (lecturer_id, course_id, group_id, semester_id, role)
        VALUES (%s, %s, %s, %s, 'primary')
        ON CONFLICT (lecturer_id, course_id, group_id, semester_id) DO UPDATE SET
            role = EXCLUDED.role,
            updated_at = NOW()
        RETURNING assignment_id
        """,
        (lecturer_id, course_id, group_id, semester_id),
    )
    assignment_id = int(cur.fetchone()[0])

    ensure_face101_lectures(cur, assignment_id, semester_id, room_id)
    return group_id, dept_id


def ensure_lecturer(cur, lecturer_code: str, department_id: int) -> int:
    cur.execute("SELECT lecturer_id FROM lecturers WHERE lecturer_code = %s", (lecturer_code,))
    row = cur.fetchone()
    if row:
        return int(row[0])

    email = f"{lecturer_code.lower()}@lecturer.edupulse.edu"
    temp_password = secrets.token_urlsafe(24)
    cur.execute(
        """
        INSERT INTO users (username, email, password_hash, role, institution_id, is_active)
        VALUES (%s, %s, crypt(%s, gen_salt('bf')), 'lecturer', %s, TRUE)
        ON CONFLICT (email) DO UPDATE SET
            institution_id = EXCLUDED.institution_id,
            updated_at = NOW()
        RETURNING user_id
        """,
        (lecturer_code.lower(), email, temp_password, lecturer_code),
    )
    user_id = int(cur.fetchone()[0])
    cur.execute(
        """
        INSERT INTO lecturers (user_id, lecturer_code, full_name, department_id, title)
        VALUES (%s, %s, 'Dr. Linda Ahmed', %s, 'Dr.')
        ON CONFLICT (lecturer_code) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            department_id = EXCLUDED.department_id,
            updated_at = NOW()
        RETURNING lecturer_id
        """,
        (user_id, lecturer_code, department_id),
    )
    return int(cur.fetchone()[0])


def ensure_face101_lectures(cur, assignment_id: int, semester_id: str, room_id: int) -> None:
    cur.execute(
        """
        SELECT academic_week, start_date
        FROM semester_weeks
        WHERE semester_id = %s
        ORDER BY academic_week
        """,
        (semester_id,),
    )
    weeks = cur.fetchall()
    if not weeks:
        raise RuntimeError(f"No semester weeks found for {semester_id}")

    for academic_week, start_date in weeks[:16]:
        lecture_code = f"FR{int(academic_week):03d}"
        cur.execute(
            """
            INSERT INTO lectures (
                lecture_code, lecture_name, assignment_id, semester_id, academic_week,
                lecture_date, day_name, start_time, end_time, room_id, status, notes
            )
            VALUES (%s, %s, %s, %s, %s, %s, 'Monday', %s, %s, %s, 'scheduled',
                    'Auto-created for StudentPicsDataset attendance')
            ON CONFLICT (lecture_code) DO UPDATE SET
                lecture_name = EXCLUDED.lecture_name,
                assignment_id = EXCLUDED.assignment_id,
                semester_id = EXCLUDED.semester_id,
                academic_week = EXCLUDED.academic_week,
                lecture_date = EXCLUDED.lecture_date,
                day_name = EXCLUDED.day_name,
                start_time = EXCLUDED.start_time,
                end_time = EXCLUDED.end_time,
                room_id = EXCLUDED.room_id,
                updated_at = NOW()
            """,
            (
                lecture_code,
                f"{FACE_COURSE_CODE} Week {int(academic_week)} Attendance",
                assignment_id,
                semester_id,
                int(academic_week),
                start_date,
                time(9, 0),
                time(10, 0),
                room_id,
            ),
        )


def ensure_student(cur, record: StudentImportRecord, group_id: int, department_id: int) -> int:
    email = f"{record.student_id}@face101.edupulse.edu"
    username = f"student_{record.student_id}"
    phone = "010" + record.student_id[-8:]
    temp_password = secrets.token_urlsafe(24)

    cur.execute(
        """
        SELECT user_id
        FROM users
        WHERE institution_id = %s OR lower(email) = lower(%s)
        LIMIT 1
        """,
        (record.student_id, email),
    )
    row = cur.fetchone()
    if row:
        user_id = int(row[0])
        cur.execute(
            """
            UPDATE users
            SET email = %s, role = 'student', institution_id = %s, updated_at = NOW()
            WHERE user_id = %s
            """,
            (email, record.student_id, user_id),
        )
    else:
        cur.execute(
            """
            INSERT INTO users (username, email, password_hash, role, institution_id, is_active)
            VALUES (%s, %s, crypt(%s, gen_salt('bf')), 'student', %s, TRUE)
            RETURNING user_id
            """,
            (username, email, temp_password, record.student_id),
        )
        user_id = int(cur.fetchone()[0])

    cur.execute(
        """
        INSERT INTO students (user_id, student_code, full_name, department_id, enrollment_year, degree_level, phone)
        VALUES (%s, %s, %s, %s, 2023, 'Undergraduate', %s)
        ON CONFLICT (student_code) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            department_id = EXCLUDED.department_id,
            enrollment_year = EXCLUDED.enrollment_year,
            degree_level = EXCLUDED.degree_level,
            phone = EXCLUDED.phone,
            updated_at = NOW()
        RETURNING student_id
        """,
        (user_id, record.student_id, record.english_name, department_id, phone),
    )
    student_pk = int(cur.fetchone()[0])

    cur.execute(
        """
        INSERT INTO group_memberships (group_id, student_id)
        VALUES (%s, %s)
        ON CONFLICT (group_id, student_id) DO NOTHING
        """,
        (group_id, student_pk),
    )
    return student_pk


def photo_extension(headers) -> str:
    content_type = headers.get("content-type", "").lower()
    if "png" in content_type:
        return ".png"
    if "webp" in content_type:
        return ".webp"
    return ".jpg"


def download_photo(url: str, destination_base: Path, timeout: int) -> Path:
    request = urllib.request.Request(
        google_download_url(url),
        headers={"User-Agent": "EduPulseImporter/1.0"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        ext = photo_extension(response.headers)
        destination = destination_base.with_suffix(ext)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(delete=False, dir=str(destination.parent), suffix=ext) as tmp:
            shutil.copyfileobj(response, tmp)
            tmp_path = Path(tmp.name)
    tmp_path.replace(destination)
    return destination


def upsert_photo_metadata(
    cur,
    student_pk: int,
    source_url: str,
    local_path: Path | None,
    is_downloaded: bool,
    download_error: str | None,
) -> None:
    relative_path = str(local_path.relative_to(REPO_ROOT)) if local_path else None
    cur.execute(
        """
        INSERT INTO student_face_photos (
            student_id, source_url, source_file_id, local_path, is_downloaded, download_error
        )
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (student_id, source_url) DO UPDATE SET
            source_file_id = EXCLUDED.source_file_id,
            local_path = EXCLUDED.local_path,
            is_downloaded = EXCLUDED.is_downloaded,
            download_error = EXCLUDED.download_error,
            updated_at = NOW()
        """,
        (student_pk, source_url, google_file_id(source_url), relative_path, is_downloaded, download_error),
    )


def import_records(
    records: Iterable[StudentImportRecord],
    *,
    skip_download: bool,
    lecturer_code: str,
    semester_id: str,
    download_timeout: int,
    limit: int | None,
) -> dict[str, int]:
    summary = {"students": 0, "photo_links": 0, "downloaded": 0, "download_failed": 0}
    selected_records = list(records)
    if limit is not None:
        selected_records = selected_records[:limit]

    with connect() as conn:
        with conn.cursor() as cur:
            ensure_runtime_schema(cur)
            group_id, department_id = ensure_face101_context(cur, lecturer_code, semester_id)
            for record in selected_records:
                student_pk = ensure_student(cur, record, group_id, department_id)
                summary["students"] += 1
                folder = KNOWN_FACES_DIR / f"{record.student_id}_{safe_name(record.english_name)}"
                folder.mkdir(parents=True, exist_ok=True)

                for index, url in enumerate(record.photo_links, start=1):
                    summary["photo_links"] += 1
                    file_id = google_file_id(url) or f"photo_{index}"
                    destination_base = folder / f"photo_{index:02d}_{file_id[:12]}"
                    if skip_download:
                        upsert_photo_metadata(cur, student_pk, url, None, False, "download skipped")
                        continue
                    try:
                        existing = next(folder.glob(f"photo_{index:02d}_{file_id[:12]}.*"), None)
                        local_path = existing or download_photo(url, destination_base, download_timeout)
                        upsert_photo_metadata(cur, student_pk, url, local_path, True, None)
                        summary["downloaded"] += 1
                    except (OSError, urllib.error.URLError, TimeoutError) as exc:
                        upsert_photo_metadata(cur, student_pk, url, None, False, str(exc)[:1000])
                        summary["download_failed"] += 1
            conn.commit()

    clear_deepface_cache()
    return summary


def clear_deepface_cache() -> None:
    for cache_file in KNOWN_FACES_DIR.glob("representations_*.pkl"):
        cache_file.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import StudentPicsDataset.csv into EduPulse")
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV_PATH)
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--lecturer-code", default="L001")
    parser.add_argument("--semester-id", default=FACE_SEMESTER_ID)
    parser.add_argument("--download-timeout", type=int, default=30)
    parser.add_argument("--limit", type=int)
    args = parser.parse_args(argv)

    records, stats = parse_student_pics_csv(args.csv)
    print("StudentPicsDataset.csv summary:")
    for key, value in stats.items():
        print(f"  {key}: {value}")

    if args.dry_run:
        print("Dry run complete. No database rows or files were changed.")
        return 0

    summary = import_records(
        records,
        skip_download=args.skip_download,
        lecturer_code=args.lecturer_code,
        semester_id=args.semester_id,
        download_timeout=args.download_timeout,
        limit=args.limit,
    )
    print("Import complete:")
    for key, value in summary.items():
        print(f"  {key}: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
