import os
import subprocess
import tempfile
import shutil
import pytest

DATABASE_URL = os.getenv("DATABASE_URL")

def test_buildbot_db_initialization():
    # create temp Buildbot master
    master_dir = tempfile.mkdtemp(prefix="bbmaster_")
    try:
        # initialize a new master in temp directory
        subprocess.run(
            ["buildbot", "create-master", master_dir, "--db", DATABASE_URL],
            check=True,
        )

        # run database upgrade (creates tables in Postgres)
        subprocess.run(
            ["buildbot", "upgrade-master", master_dir, "--db", DATABASE_URL],
            check=True,
        )

        # check a simple SQL query directly via psycopg
        import psycopg

        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                row = cur.fetchone()
                assert row[0] == 1

    finally:
        shutil.rmtree(master_dir)
