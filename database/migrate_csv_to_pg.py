"""
EduPulse AI — CSV to PostgreSQL Migration Script

One-time migration: reads all CSV files from data/ and inserts into PostgreSQL.
Run AFTER schema.sql and seed.sql have been executed.

Usage:
    python database/migrate_csv_to_pg.py --host localhost --port 5432 --dbname edupulse --user edupulse_app --password yourpassword

Requires: psycopg2-binary, pandas
"""

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
import argparse
import os
import secrets
import sys
from datetime import datetime

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')


def get_connection(args):
    return psycopg2.connect(
        host=args.host,
        port=args.port,
        dbname=args.dbname,
        user=args.user,
        password=args.password
    )


def migrate_lecturers(conn):
    """Create users + lecturer profiles from lecturers.csv"""
    df = pd.read_csv(os.path.join(DATA_DIR, 'lecturers.csv'))
    cur = conn.cursor()

    for _, row in df.iterrows():
        code = row['lecturer_id']
        name = row['lecturer_name']
        email = row['email']

        # Create user account with non-guessable temporary password hash
        username = code.lower()
        temp_password = secrets.token_urlsafe(24)
        cur.execute("""
            INSERT INTO users (username, email, password_hash, role, is_active)
            VALUES (%s, %s, crypt(%s, gen_salt('bf')), 'lecturer', TRUE)
            ON CONFLICT (username) DO NOTHING
            RETURNING user_id
        """, (username, email, temp_password))

        result = cur.fetchone()
        if result is None:
            cur.execute("SELECT user_id FROM users WHERE username = %s", (username,))
            result = cur.fetchone()
        user_id = result[0]

        # Create lecturer profile
        dept_id = get_department_id(cur, row.get('department', 'Computer Science'))
        title = name.split('.')[0] + '.' if '.' in name else None

        cur.execute("""
            INSERT INTO lecturers (user_id, lecturer_code, full_name, department_id, title)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (lecturer_code) DO NOTHING
        """, (user_id, code, name, dept_id, title))

    conn.commit()
    print(f"  Migrated {len(df)} lecturers")


def migrate_students(conn):
    """Create users + student profiles from students.csv and emotion_records.csv"""
    # Get unique students from emotion records (more complete than students.csv)
    emotions = pd.read_csv(os.path.join(DATA_DIR, 'emotion_records.csv'))
    students_csv = pd.read_csv(os.path.join(DATA_DIR, 'students.csv'))

    # Merge to get all students
    emotion_students = emotions[['student_id', 'student_name']].drop_duplicates()
    all_students = pd.concat([
        students_csv[['student_id', 'student_name']].rename(columns={'student_name': 'student_name'}),
        emotion_students
    ]).drop_duplicates(subset=['student_id'])

    cur = conn.cursor()

    for _, row in all_students.iterrows():
        code = row['student_id']
        name = row.get('student_name', f'Student {code}')

        # Create user account
        username = code.lower()
        email = f'{code}@student.edupulse.edu'

        temp_password = secrets.token_urlsafe(24)
        cur.execute("""
            INSERT INTO users (username, email, password_hash, role, is_active)
            VALUES (%s, %s, crypt(%s, gen_salt('bf')), 'student', TRUE)
            ON CONFLICT (username) DO NOTHING
            RETURNING user_id
        """, (username, email, temp_password))

        result = cur.fetchone()
        if result is None:
            cur.execute("SELECT user_id FROM users WHERE username = %s", (username,))
            result = cur.fetchone()
        user_id = result[0]

        # Create student profile
        dept_id = get_department_id(cur, 'Computer Science')
        enrollment_year = 2024

        cur.execute("""
            INSERT INTO students (user_id, student_code, full_name, department_id, enrollment_year)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (student_code) DO NOTHING
        """, (user_id, code, name, dept_id, enrollment_year))

    conn.commit()
    print(f"  Migrated {len(all_students)} students")


def migrate_groups_and_memberships(conn):
    """Create student groups and group memberships"""
    groups_df = pd.read_csv(os.path.join(DATA_DIR, 'groups.csv'))
    cur = conn.cursor()

    for _, row in groups_df.iterrows():
        group_code = row['group_id']
        group_name = row['group_name']
        course_code = None
        semester_id = row['semester_id']

        # Look up course_id from the course_id column
        course_pk = get_course_id(cur, row['course_id'])

        cur.execute("""
            INSERT INTO student_groups (group_code, group_name, course_id, semester_id)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (group_code, semester_id) DO NOTHING
            RETURNING group_id
        """, (group_code, group_name, course_pk, semester_id))

    conn.commit()

    # Generate memberships: 20 students per group (S001-S020 -> G01, S021-S040 -> G02, etc.)
    group_map = {}
    cur.execute("SELECT group_id, group_code FROM student_groups")
    for gid, gcode in cur.fetchall():
        group_map[gcode] = gid

    student_map = {}
    cur.execute("SELECT student_id, student_code FROM students")
    for sid, scode in cur.fetchall():
        student_map[scode] = sid

    membership_data = []
    group_codes = sorted(group_map.keys())
    for i, gcode in enumerate(group_codes):
        start = i * 20 + 1
        for j in range(20):
            scode = f'S{start + j:03d}'
            if scode in student_map and gcode in group_map:
                membership_data.append((group_map[gcode], student_map[scode]))

    if membership_data:
        execute_values(cur, """
            INSERT INTO group_memberships (group_id, student_id)
            VALUES %s
            ON CONFLICT (group_id, student_id) DO NOTHING
        """, membership_data)

    conn.commit()
    print(f"  Migrated {len(groups_df)} groups with {len(membership_data)} memberships")


def migrate_assignments(conn):
    """Create lecturer course assignments"""
    df = pd.read_csv(os.path.join(DATA_DIR, 'lecturer_course_assignments.csv'))
    cur = conn.cursor()

    for _, row in df.iterrows():
        lec_pk = get_lecturer_id(cur, row['lecturer_id'])
        course_pk = get_course_id(cur, row['course_id'])
        group_pk = get_group_id_by_code(cur, row['group_id'])

        cur.execute("""
            INSERT INTO lecturer_course_assignments (lecturer_id, course_id, group_id, semester_id, role)
            VALUES (%s, %s, %s, %s, 'primary')
            ON CONFLICT (lecturer_id, course_id, group_id, semester_id) DO NOTHING
        """, (lec_pk, course_pk, group_pk, row['semester_id']))

    conn.commit()
    print(f"  Migrated {len(df)} lecturer assignments")


def migrate_lectures(conn):
    """Migrate lecture schedule"""
    df = pd.read_csv(os.path.join(DATA_DIR, 'lecture_schedule.csv'))
    cur = conn.cursor()

    for _, row in df.iterrows():
        # Look up assignment_id
        lec_pk = get_lecturer_id(cur, row['lecturer_id'])
        course_pk = get_course_id(cur, row['course_id'])
        group_pk = get_group_id_by_code(cur, row['group_id'])

        cur.execute("""
            SELECT assignment_id FROM lecturer_course_assignments
            WHERE lecturer_id = %s AND course_id = %s AND group_id = %s AND semester_id = %s
        """, (lec_pk, course_pk, group_pk, row['semester_id']))
        result = cur.fetchone()
        if result is None:
            continue
        assignment_id = result[0]

        # Look up room_id
        room_pk = get_room_id(cur, row.get('room', 'Room 204'))

        cur.execute("""
            INSERT INTO lectures (lecture_code, lecture_name, assignment_id, semester_id,
                                  academic_week, lecture_date, day_name, start_time, end_time,
                                  room_id, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (lecture_code) DO NOTHING
        """, (
            row['lecture_id'], row['lecture_name'], assignment_id, row['semester_id'],
            int(row['academic_week']), row['lecture_date'], row['day_name'],
            row['start_time'], row['end_time'], room_pk, row.get('status', 'analyzed')
        ))

    conn.commit()
    print(f"  Migrated {len(df)} lectures")


def migrate_emotion_records(conn, batch_size=2000):
    """Migrate emotion records in batches"""
    df = pd.read_csv(os.path.join(DATA_DIR, 'emotion_records.csv'))
    cur = conn.cursor()

    # Build lookup maps
    student_map = {}
    cur.execute("SELECT student_id, student_code FROM students")
    for sid, scode in cur.fetchall():
        student_map[scode] = sid

    lecture_map = {}
    cur.execute("SELECT lecture_id, lecture_code FROM lectures")
    for lid, lcode in cur.fetchall():
        lecture_map[lcode] = lid

    total = 0
    batch = []

    for _, row in df.iterrows():
        sid = student_map.get(str(row['student_id']))
        lid = lecture_map.get(str(row['lecture_id']))

        if sid is None or lid is None:
            continue

        is_present = bool(row.get('is_present', True))
        left_room = bool(row.get('left_room', False))

        batch.append((
            sid, lid,
            row['timestamp'],
            int(row.get('time_minute', 0)),
            row['emotion'],
            float(row['confidence']),
            float(row['engagement_score']),
            float(row['focus_score']),
            is_present,
            left_room,
            int(row.get('absence_duration_minutes', 0)),
            row.get('source_type', 'mock_video'),
            row.get('model_name', 'EduPulse_v1.0')
        ))

        if len(batch) >= batch_size:
            execute_values(cur, """
                INSERT INTO emotion_records (student_id, lecture_id, recorded_at, time_minute,
                    emotion, confidence, engagement_score, focus_score, is_present, left_room,
                    absence_duration_minutes, source, model_name)
                VALUES %s
            """, batch)
            total += len(batch)
            batch = []
            conn.commit()
            print(f"    ... {total} records inserted")

    if batch:
        execute_values(cur, """
            INSERT INTO emotion_records (student_id, lecture_id, recorded_at, time_minute,
                emotion, confidence, engagement_score, focus_score, is_present, left_room,
                absence_duration_minutes, source, model_name)
            VALUES %s
        """, batch)
        total += len(batch)
        conn.commit()

    print(f"  Migrated {total} emotion records")


def generate_attendance_records(conn):
    """Generate attendance records from emotion data"""
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO attendance_records (student_id, lecture_id, status, first_seen_at, last_seen_at,
                                         total_absence_minutes, attendance_pct)
        SELECT
            er.student_id,
            er.lecture_id,
            CASE
                WHEN BOOL_AND(er.is_present) AND NOT BOOL_OR(er.left_room) THEN 'Present'::attendance_status_type
                WHEN NOT BOOL_AND(er.is_present) THEN 'Absent'::attendance_status_type
                ELSE 'Left'::attendance_status_type
            END,
            MIN(er.recorded_at),
            MAX(er.recorded_at),
            MAX(er.absence_duration_minutes),
            CASE
                WHEN MAX(er.absence_duration_minutes) = 0 THEN 100.00
                ELSE GREATEST(0, 100.00 - (MAX(er.absence_duration_minutes)::DECIMAL / 60.0 * 100.0))
            END
        FROM emotion_records er
        GROUP BY er.student_id, er.lecture_id
        ON CONFLICT (student_id, lecture_id) DO NOTHING
    """)
    count = cur.rowcount
    conn.commit()
    print(f"  Generated {count} attendance records")


# Helper functions

def get_department_id(cur, dept_name):
    cur.execute("SELECT department_id FROM departments WHERE department_name = %s", (dept_name,))
    result = cur.fetchone()
    return result[0] if result else None


def get_course_id(cur, course_id_or_code):
    # Try by code first (e.g., 'CS301')
    cur.execute("SELECT course_id FROM courses WHERE course_code = %s", (str(course_id_or_code),))
    result = cur.fetchone()
    if result:
        return result[0]
    # Try by course_id integer PK
    cur.execute("SELECT course_id FROM courses WHERE course_id = %s", (int(course_id_or_code.replace('C', '')),))
    result = cur.fetchone()
    return result[0] if result else None


def get_lecturer_id(cur, lecturer_code):
    cur.execute("SELECT lecturer_id FROM lecturers WHERE lecturer_code = %s", (str(lecturer_code),))
    result = cur.fetchone()
    return result[0] if result else None


def get_group_id_by_code(cur, group_code):
    cur.execute("SELECT group_id FROM student_groups WHERE group_code = %s", (str(group_code),))
    result = cur.fetchone()
    return result[0] if result else None


def get_room_id(cur, room_number):
    cur.execute("SELECT room_id FROM rooms WHERE room_number = %s", (str(room_number),))
    result = cur.fetchone()
    return result[0] if result else None


def main():
    parser = argparse.ArgumentParser(description='Migrate EduPulse CSV data to PostgreSQL')
    parser.add_argument('--host', default='localhost')
    parser.add_argument('--port', type=int, default=5432)
    parser.add_argument('--dbname', default='EduPulse AI')
    parser.add_argument('--user', default='postgres')
    parser.add_argument('--password', default='')
    args = parser.parse_args()

    print("=" * 60)
    print("EduPulse AI — CSV to PostgreSQL Migration")
    print("=" * 60)

    try:
        conn = get_connection(args)
        print(f"Connected to {args.dbname}@{args.host}:{args.port}\n")
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

    steps = [
        ("Lecturers", migrate_lecturers),
        ("Students", migrate_students),
        ("Groups & Memberships", migrate_groups_and_memberships),
        ("Lecturer Assignments", migrate_assignments),
        ("Lectures", migrate_lectures),
        ("Emotion Records", lambda c: migrate_emotion_records(c)),
        ("Attendance Records", generate_attendance_records),
    ]

    for name, func in steps:
        print(f"[{name}]")
        try:
            func(conn)
        except Exception as e:
            print(f"  ERROR: {e}")
            conn.rollback()
        print()

    # Summary
    cur = conn.cursor()
    tables = ['departments', 'rooms', 'users', 'lecturers', 'students', 'courses',
              'student_groups', 'group_memberships', 'lecturer_course_assignments',
              'lectures', 'emotion_records', 'attendance_records', 'system_settings']
    print("Row counts:")
    for table in tables:
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        count = cur.fetchone()[0]
        print(f"  {table:40s} {count:>6,}")

    conn.close()
    print("\nMigration complete!")


if __name__ == '__main__':
    main()
