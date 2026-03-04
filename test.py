import os
import tempfile
import shutil
import pytest
from buildbot.util import secretutil
from buildbot import config
from buildbot.db import schema

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://github:github@localhost:5432/testdb")

def test_buildbot_master_worker_db():
    # Create temporary master directory
    master_dir = tempfile.mkdtemp(prefix="bbmaster_")

    try:
        # Minimal Buildbot master config
        c = config.Config(
            db=DATABASE_URL,
            workers=[],
            secrets=secretutil.getSecrets()
        )

        # Initialize schema
        schema.upgrade(c.db_url)
        # Optionally, test inserting something into master DB
        from buildbot.db import dbcommands
        with dbcommands.DBConnection(DATABASE_URL) as db:
            db.execute("SELECT 1;")
            result = db.fetchone()
            assert result[0] == 1
    finally:
        shutil.rmtree(master_dir)
