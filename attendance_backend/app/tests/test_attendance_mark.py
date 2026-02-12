import asyncio

import pytest
from fastapi import HTTPException
from fastapi.encoders import jsonable_encoder
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.api.attendance import mark_attendance
from app.db import models
from app.db.base import Base


def _make_db():
    engine = create_engine("sqlite:///:memory:")
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    return TestingSessionLocal()


def _seed_teacher_class_student(db):
    teacher = models.Teacher(
        teacher_id="sa001",
        full_name="Super Admin",
        email="sa@example.com",
        password_hash="x",
        role="super_admin",
        status="active",
        organization_id=None,
    )
    db.add(teacher)
    db.commit()
    db.refresh(teacher)

    class_obj = models.Class(
        class_name="Test Class",
        class_code="TST001",
        teacher_id=teacher.id,
        organization_id=None,
    )
    db.add(class_obj)
    db.commit()
    db.refresh(class_obj)

    student = models.Student(
        student_id="S001",
        full_name="Test Student",
        class_id=class_obj.id,
        face_enrolled=False,
    )
    db.add(student)
    db.commit()
    db.refresh(student)

    return teacher, class_obj, student


def test_mark_attendance_returns_jsonable_dict():
    db = _make_db()
    try:
        teacher, class_obj, student = _seed_teacher_class_student(db)

        result = asyncio.run(
            mark_attendance(
                student_id=student.id,
                class_id=class_obj.id,
                confidence_score=0.95,
                check_in_type="morning",
                db=db,
                current_user={"user_id": teacher.id, "role": teacher.role},
            )
        )

        assert result["student_id"] == student.id
        assert result["class_id"] == class_obj.id
        assert result["check_in_type"] == "morning"
        assert result["status"] in (None, "present", "late", "absent")

        encoded = jsonable_encoder(result)
        assert isinstance(encoded["id"], int)
        assert isinstance(encoded["marked_at"], str)
    finally:
        db.close()


def test_mark_attendance_duplicate_returns_400():
    db = _make_db()
    try:
        teacher, class_obj, student = _seed_teacher_class_student(db)

        asyncio.run(
            mark_attendance(
                student_id=student.id,
                class_id=class_obj.id,
                confidence_score=0.95,
                check_in_type="morning",
                db=db,
                current_user={"user_id": teacher.id, "role": teacher.role},
            )
        )

        with pytest.raises(HTTPException) as exc_info:
            asyncio.run(
                mark_attendance(
                    student_id=student.id,
                    class_id=class_obj.id,
                    confidence_score=0.95,
                    check_in_type="morning",
                    db=db,
                    current_user={"user_id": teacher.id, "role": teacher.role},
                )
            )

        assert exc_info.value.status_code == 400
    finally:
        db.close()

