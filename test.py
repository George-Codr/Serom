import os
import tempfile
import shutil
import pytest
from buildbot.db import schema
from buildbot import config

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://github:github@localhost:5432/testdb")

def test_buildbot_master_db():
    # Create temporary master directory
    master_dir = tempfile.mkdtemp(prefix="bbmaster_")

    try:
        # Minimal Buildbot master config
        c = config.Config(
            db=DATABASE_URL,
            workers=[],   # no workers needed for DB test
            # secrets are optional for DB tests
        )

        # Initialize schema
        schema.upgrade(c.db_url)

        # Simple test: check DB connection
        from sqlalchemy import create_engine, text
        engine = create_engine(DATABASE_URL)
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1;")).scalar()
            assert result == 1

    finally:
        shutil.rmtree(master_dir)
