"""
database.py — PostgreSQL connection pool for EduPulse AI FastAPI backend
"""

import os
import psycopg2
from psycopg2 import pool
from contextlib import contextmanager

DB_CONFIG = {
    "host": os.getenv("EDUPULSE_DB_HOST", "localhost"),
    "port": int(os.getenv("EDUPULSE_DB_PORT", "5432")),
    "dbname": os.getenv("EDUPULSE_DB_NAME", "edupulse"),
    "user": os.getenv("EDUPULSE_DB_USER", "edupulse_app"),
    "password": os.getenv("EDUPULSE_DB_PASSWORD", "edupulse_pass"),
}

_connection_pool = None


def init_db():
    """Initialize the connection pool. Call at FastAPI startup."""
    global _connection_pool
    _connection_pool = pool.ThreadedConnectionPool(
        minconn=1,
        maxconn=10,
        **DB_CONFIG
    )
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


def execute_insert(sql, params=None):
    """Execute an INSERT and return the generated ID."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql + " RETURNING record_id", params)
            result = cur.fetchone()
            return result[0] if result else None


def execute_many(sql, params_list):
    """Execute a batch of INSERTs."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, params_list)
            return cur.rowcount
