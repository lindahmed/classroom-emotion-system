"""
database.py — PostgreSQL connection pool for EduPulse AI FastAPI backend
"""

import os
import logging
import re
import psycopg2
from psycopg2 import pool
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import unquote, urlparse


logger = logging.getLogger(__name__)


def _load_env_file():
    for path in (Path(__file__).resolve().parents[1] / ".env", Path(__file__).resolve().parent / ".env"):
        if not path.exists():
            continue
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def _config_from_database_url():
    database_url = os.getenv("DATABASE_URL") or os.getenv("EDUPULSE_DATABASE_URL")
    if not database_url:
        return {}

    parsed = urlparse(database_url)
    if parsed.scheme not in {"postgres", "postgresql"}:
        return {}

    return {
        "host": parsed.hostname or "localhost",
        "port": parsed.port or 5432,
        "dbname": unquote(parsed.path.lstrip("/")),
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
    }


_load_env_file()
_url_config = _config_from_database_url()

# FIXED: Changed default dbname from "EduPulse AI" (with space) to "edupulse_ai" (no space)
# PostgreSQL database names should not contain spaces
DB_CONFIG = {
    "host": os.getenv("EDUPULSE_DB_HOST", _url_config.get("host", "localhost")),
    "port": int(os.getenv("EDUPULSE_DB_PORT", str(_url_config.get("port", 5432)))),
    "dbname": os.getenv("EDUPULSE_DB_NAME", _url_config.get("dbname", "edupulse_ai")),
    "user": os.getenv("EDUPULSE_DB_USER", _url_config.get("user", "admin")),
    "password": os.getenv("EDUPULSE_DB_PASSWORD", _url_config.get("password", "")),
}

_connection_pool = None


def init_db():
    """Initialize the connection pool. Call at FastAPI startup."""
    global _connection_pool

    logger.info("Connecting to PostgreSQL (host=%s port=%s dbname=%s user=%s)", DB_CONFIG["host"], DB_CONFIG["port"], DB_CONFIG["dbname"], DB_CONFIG["user"])
    
    try:
        _connection_pool = pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=10,
            **DB_CONFIG
        )
        logger.info("Connection pool created successfully")
    except psycopg2.OperationalError as e:
        logger.exception("Database connection failed: %s", e)
        raise
    
    ensure_auth_schema()
    return _connection_pool


def close_db():
    """Close all connections. Call at FastAPI shutdown."""
    global _connection_pool
    if _connection_pool:
        _connection_pool.closeall()
        _connection_pool = None


@contextmanager
def get_connection():
    """Get a connection from the pool. Use as context manager."""
    if _connection_pool is None:
        init_db()
    conn = _connection_pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        _connection_pool.putconn(conn)


def execute_query(sql, params=None, fetch=True):
    """Execute a query and optionally fetch results."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            if fetch:
                columns = [desc[0] for desc in cur.description]
                rows = cur.fetchall()
                return [dict(zip(columns, row)) for row in rows]
            return cur.rowcount


def execute_insert(sql, params=None, returning: str = "record_id"):
    """Execute an INSERT and return a generated ID (optional).

    Notes:
      - Historically this helper appended `RETURNING record_id` unconditionally, which
        breaks inserts into tables whose PK is not `record_id` (e.g. `alert_id`, `user_id`).
      - If `sql` already includes a RETURNING clause, we do not append another.
      - If `returning` is falsy (None/""), the INSERT runs and returns None.
    """
    with get_connection() as conn:
        with conn.cursor() as cur:
            normalized_sql = sql.strip().rstrip(";")
            if not returning:
                cur.execute(normalized_sql, params)
                return None

            has_returning = re.search(r"\breturning\b", normalized_sql, re.IGNORECASE) is not None
            final_sql = normalized_sql if has_returning else f"{normalized_sql} RETURNING {returning}"
            cur.execute(final_sql, params)
            result = cur.fetchone()
            return result[0] if result else None


def execute_many(sql, params_list):
    """Execute a batch of INSERTs."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, params_list)
            return cur.rowcount


def ensure_auth_schema():
    """Verify auth tables exist and create them if missing."""
    required_tables = {"users", "students", "lecturers", "admins", "login_sessions"}
    
    with get_connection() as conn:
        with conn.cursor() as cur:
            # Check existing tables
            cur.execute(
                """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                """
            )
            existing_tables = {row[0] for row in cur.fetchall()}
            missing_tables = sorted(required_tables - existing_tables)
            
            if missing_tables:
                logger.warning("Missing tables: %s. Creating schema from database/schema.sql...", ", ".join(missing_tables))
                
                schema_path = Path(__file__).resolve().parent.parent / "database" / "schema.sql"
                if not schema_path.exists():
                    raise RuntimeError(
                        f"Schema file not found at {schema_path}\n"
                        "Cannot initialize database schema."
                    )
                
                try:
                    schema_sql = schema_path.read_text(encoding="utf-8")
                    cur.execute(schema_sql)
                    logger.info("Schema created successfully")
                except Exception as e:
                    raise RuntimeError(f"Failed to create schema: {e}")
            else:
                logger.info("All required tables exist")

            # Apply additive runtime migrations for existing local databases.
            try:
                cur.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
                cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS institution_id VARCHAR(20)")
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
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_institution_id_unique
                    ON users (lower(institution_id))
                    WHERE institution_id IS NOT NULL
                    """
                )
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
                cur.execute(
                    "CREATE INDEX IF NOT EXISTS idx_student_face_photos_student ON student_face_photos(student_id)"
                )
                cur.execute(
                    "CREATE INDEX IF NOT EXISTS idx_student_face_photos_file_id ON student_face_photos(source_file_id)"
                )
                cur.execute(
                    "CREATE INDEX IF NOT EXISTS idx_attendance_sessions_lecture ON attendance_sessions(lecture_id)"
                )
                cur.execute(
                    "CREATE INDEX IF NOT EXISTS idx_attendance_sessions_status ON attendance_sessions(status)"
                )
            except Exception as e:
                logger.warning("Could not apply runtime schema updates: %s", e)

            # Session start persistence (for time_minute across restarts)
            # Safe to create even if the full analytics schema is not present.
            try:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS lecture_sessions (
                        session_id   BIGSERIAL PRIMARY KEY,
                        lecture_id   INTEGER NOT NULL REFERENCES lectures(lecture_id) ON DELETE CASCADE,
                        started_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                        ended_at     TIMESTAMP WITH TIME ZONE,
                        status       TEXT NOT NULL DEFAULT 'started',
                        created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                        UNIQUE (lecture_id)
                    )
                    """
                )
            except Exception as e:
                # If lectures table doesn't exist (auth-only DB), ignore.
                logger.debug("Skipping lecture_sessions creation: %s", e)
    
    # Apply seed data
    apply_seed_data()


def apply_seed_data():
    """Apply seed data from database/seed.sql if users table is empty."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            # Check if users table already has data
            cur.execute("SELECT COUNT(*) FROM users;")
            user_count = cur.fetchone()[0]
            
            if user_count == 0:
                logger.info("Applying seed data...")
                seed_path = Path(__file__).resolve().parent.parent / "database" / "seed.sql"
                if seed_path.exists():
                    try:
                        seed_sql = seed_path.read_text(encoding="utf-8")
                        cur.execute(seed_sql)
                        logger.info("Seed data applied successfully")
                    except Exception as e:
                        logger.warning("Seed data application had issues: %s", e)
