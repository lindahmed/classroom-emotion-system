#!/usr/bin/env python
"""Quick diagnostic to test database connection without starting full FastAPI."""

import os
import sys
from pathlib import Path

def main() -> int:
    # Load .env
    env_file = Path(__file__).parent / ".env"
    if env_file.exists():
        print(f"Loading env from {env_file}")
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            os.environ.setdefault(key.strip(), val.strip().strip("\"'"))

    # Now test
    try:
        import psycopg2

        config = {
            "host": os.getenv("EDUPULSE_DB_HOST", "localhost"),
            "port": int(os.getenv("EDUPULSE_DB_PORT", "5432")),
            "dbname": os.getenv("EDUPULSE_DB_NAME", "EduPulse AI"),
            "user": os.getenv("EDUPULSE_DB_USER", "postgres"),
            "password": os.getenv("EDUPULSE_DB_PASSWORD", ""),
        }

        print("✓ Config loaded from env:")
        print(f"  host:     {config['host']}")
        print(f"  port:     {config['port']}")
        print(f"  dbname:   {config['dbname']}")
        print(f"  user:     {config['user']}")
        print(f"  password: {'*' * len(config['password'])}")

        print("\nAttempting connection...")
        conn = psycopg2.connect(**config)
        print("✓ Connection successful!")

        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            result = cur.fetchone()
            print(f"✓ Query test successful: {result}")

            cur.execute(
                """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                """
            )
            tables = cur.fetchall()
            print(f"✓ Existing tables: {len(tables)} found")
            if tables:
                for (tbl,) in tables[:5]:
                    print(f"    - {tbl}")
                if len(tables) > 5:
                    print(f"    ... and {len(tables) - 5} more")

        conn.close()
        print("\n✓ All checks passed! Database is accessible.")
        return 0

    except Exception as e:
        print(f"\n✗ ERROR: {type(e).__name__}")
        print(f"  {e}")
        import traceback

        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
