import asyncio

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db.base import Base
from app.db import models
from app.services.class_service import ClassService


def _make_db():
    engine = create_engine("sqlite:///:memory:")
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    return TestingSessionLocal()


def test_super_admin_can_access_class_without_org():
    db = _make_db()
    try:
        super_admin = models.Teacher(
            teacher_id="sa001",
            full_name="Super Admin",
            email="sa@example.com",
            password_hash="x",
            role="super_admin",
            status="active",
            organization_id=None,
        )
        db.add(super_admin)
        db.commit()
        db.refresh(super_admin)

        class_obj = models.Class(
            class_name="Test Class",
            class_code="TST001",
            teacher_id=super_admin.id,
            organization_id=None,
        )
        db.add(class_obj)
        db.commit()
        db.refresh(class_obj)

        allowed = asyncio.run(
            ClassService().check_teacher_access(class_obj.id, super_admin.id, db)
        )
        assert allowed is True
    finally:
        db.close()

