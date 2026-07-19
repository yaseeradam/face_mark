"""Database CRUD operations"""
from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from datetime import datetime, date
import os
from . import models
from ..core.security import get_password_hash, verify_password

def _delete_student_photo_file(photo_path: Optional[str]) -> None:
    if not photo_path:
        return
    try:
        # Resolve absolute path to the uploads folder
        base_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        normalized_path = photo_path.replace("\\", "/").lstrip("/")
        abs_path = os.path.join(base_dir, "uploads", normalized_path)
        if os.path.exists(abs_path) and os.path.isfile(abs_path):
            os.remove(abs_path)
            print(f"Deleted photo file: {abs_path}")
    except Exception as e:
        print(f"Error deleting photo file {photo_path}: {e}")

# Teacher CRUD
def create_teacher(db: Session, teacher_data: dict) -> models.Teacher:
    try:
        hashed_password = get_password_hash(teacher_data["password"])
        db_teacher = models.Teacher(
            teacher_id=teacher_data["teacher_id"],
            full_name=teacher_data["full_name"],
            email=teacher_data["email"],
            password_hash=hashed_password,
            role=teacher_data.get("role", "teacher"),
            status=teacher_data.get("status", "active")
        )
        db.add(db_teacher)
        db.commit()
        db.refresh(db_teacher)
        return db_teacher
    except Exception:
        db.rollback()
        raise

def get_teacher_by_email(db: Session, email: str) -> Optional[models.Teacher]:
    return db.query(models.Teacher).filter(models.Teacher.email == email).first()

def get_teacher_by_teacher_id(db: Session, teacher_id: str) -> Optional[models.Teacher]:
    return db.query(models.Teacher).filter(models.Teacher.teacher_id == teacher_id).first()

def get_teacher_by_id(db: Session, teacher_id: int) -> Optional[models.Teacher]:
    return db.query(models.Teacher).filter(models.Teacher.id == teacher_id).first()

def get_teachers(db: Session, skip: int = 0, limit: int = 100) -> List[models.Teacher]:
    return db.query(models.Teacher).offset(skip).limit(limit).all()

def authenticate_teacher(db: Session, email: str, password: str) -> Optional[models.Teacher]:
    teacher = get_teacher_by_email(db, email)
    if not teacher or not verify_password(password, teacher.password_hash):
        return None
    return teacher

# Class CRUD
def create_class(db: Session, class_data: dict) -> models.Class:
    try:
        # Strip organization_id if passed in payload
        class_data.pop("organization_id", None)
        db_class = models.Class(**class_data)
        db.add(db_class)
        db.commit()
        db.refresh(db_class)
        return db_class
    except Exception:
        db.rollback()
        raise

def get_class_by_id(db: Session, class_id: int) -> Optional[models.Class]:
    return db.query(models.Class).filter(models.Class.id == class_id).first()

def get_classes(db: Session, teacher_id: Optional[int] = None) -> List[models.Class]:
    query = db.query(models.Class)
    if teacher_id is not None:
        query = query.filter(models.Class.teacher_id == teacher_id)
    return query.all()

# Student CRUD
def create_student(db: Session, student_data: dict) -> models.Student:
    try:
        db_student = models.Student(**student_data)
        db.add(db_student)
        db.commit()
        db.refresh(db_student)
        return db_student
    except Exception:
        db.rollback()
        raise

def get_student_by_id(db: Session, student_id: int) -> Optional[models.Student]:
    return db.query(models.Student).filter(models.Student.id == student_id).first()

def get_student_by_student_id(db: Session, student_id: str) -> Optional[models.Student]:
    return db.query(models.Student).filter(models.Student.student_id == student_id).first()

def get_students(db: Session, class_id: Optional[int] = None, class_ids: Optional[List[int]] = None) -> List[models.Student]:
    query = db.query(models.Student)
    if class_id:
        query = query.filter(models.Student.class_id == class_id)
    if class_ids:
        query = query.filter(models.Student.class_id.in_(class_ids))
    return query.all()

def update_student_face_enrolled(db: Session, student_id: int, enrolled: bool, photo_path: str = None) -> models.Student:
    try:
        student = get_student_by_id(db, student_id)
        if student:
            student.face_enrolled = enrolled
            if photo_path:
                # If there's an existing photo, delete it to prevent orphaned files
                if student.photo_path and student.photo_path != photo_path:
                    _delete_student_photo_file(student.photo_path)
                student.photo_path = photo_path
            db.commit()
            db.refresh(student)
        return student
    except Exception:
        db.rollback()
        raise

def update_student(db: Session, student_id: int, update_data: dict) -> models.Student:
    try:
        student = get_student_by_id(db, student_id)
        if student:
            for key, value in update_data.items():
                if hasattr(student, key):
                    setattr(student, key, value)
            db.commit()
            db.refresh(student)
        return student
    except Exception:
        db.rollback()
        raise

def delete_student(db: Session, student_id: int) -> bool:
    try:
        student = get_student_by_id(db, student_id)
        if student:
            # Delete face embedding first
            db.query(models.FaceEmbedding).filter(models.FaceEmbedding.student_id == student_id).delete()
            # Delete attendance records
            db.query(models.Attendance).filter(models.Attendance.student_id == student_id).delete()
            # Clean up the physical profile photo file from disk
            _delete_student_photo_file(student.photo_path)
            # Delete student
            db.delete(student)
            db.commit()
            return True
        return False
    except Exception:
        db.rollback()
        raise

# Teacher UPDATE/DELETE
def update_teacher(db: Session, teacher_id: int, update_data: dict) -> models.Teacher:
    try:
        teacher = get_teacher_by_id(db, teacher_id)
        if teacher:
            for key, value in update_data.items():
                if key == "password":
                    teacher.password_hash = get_password_hash(value)
                elif hasattr(teacher, key):
                    setattr(teacher, key, value)
            db.commit()
            db.refresh(teacher)
        return teacher
    except Exception:
        db.rollback()
        raise

def delete_teacher(db: Session, teacher_id: int) -> bool:
    try:
        teacher = get_teacher_by_id(db, teacher_id)
        if teacher:
            # Delete teacher face embeddings first
            db.query(models.TeacherFaceEmbedding).filter(models.TeacherFaceEmbedding.teacher_id == teacher_id).delete()
            # Delete teacher
            db.delete(teacher)
            db.commit()
            return True
        return False
    except Exception:
        db.rollback()
        raise

# Class UPDATE/DELETE
def update_class(db: Session, class_id: int, update_data: dict) -> models.Class:
    try:
        class_obj = get_class_by_id(db, class_id)
        if class_obj:
            # Strip organization_id if passed
            update_data.pop("organization_id", None)
            for key, value in update_data.items():
                if hasattr(class_obj, key):
                    setattr(class_obj, key, value)
            db.commit()
            db.refresh(class_obj)
        return class_obj
    except Exception:
        db.rollback()
        raise

def delete_class(db: Session, class_id: int) -> bool:
    try:
        class_obj = get_class_by_id(db, class_id)
        if class_obj:
            # Delete students in this class (cascade)
            students = get_students(db, class_id=class_id)
            for student in students:
                delete_student(db, student.id)
            db.delete(class_obj)
            db.commit()
            return True
        return False
    except Exception:
        db.rollback()
        raise

# Face Embedding CRUD
def create_face_embedding(db: Session, student_id: int, embedding: str) -> models.FaceEmbedding:
    try:
        # Delete existing embedding if any
        db.query(models.FaceEmbedding).filter(models.FaceEmbedding.student_id == student_id).delete()
        
        db_embedding = models.FaceEmbedding(
            student_id=student_id,
            embedding=embedding
        )
        db.add(db_embedding)
        db.commit()
        db.refresh(db_embedding)
        return db_embedding
    except Exception:
        db.rollback()
        raise

def get_face_embedding(db: Session, student_id: int) -> Optional[models.FaceEmbedding]:
    return db.query(models.FaceEmbedding).filter(models.FaceEmbedding.student_id == student_id).first()

def get_all_face_embeddings_by_class(db: Session, class_id: int) -> List[models.FaceEmbedding]:
    return db.query(models.FaceEmbedding).join(models.Student).filter(
        models.Student.class_id == class_id
    ).all()

def get_all_face_embeddings_by_class_ids(db: Session, class_ids: List[int]) -> List[models.FaceEmbedding]:
    return db.query(models.FaceEmbedding).join(models.Student).filter(
        models.Student.class_id.in_(class_ids)
    ).all()

def get_all_face_embeddings(db: Session) -> List[models.FaceEmbedding]:
    return db.query(models.FaceEmbedding).all()

# Attendance CRUD
def create_attendance(
    db: Session,
    student_id: int,
    class_id: int,
    confidence_score: float = None,
    status: str = "present",
    check_in_type: str = "morning"
) -> models.Attendance:
    try:
        db_attendance = models.Attendance(
            student_id=student_id,
            class_id=class_id,
            confidence_score=confidence_score,
            status=status,
            check_in_type=check_in_type
        )
        db.add(db_attendance)
        db.commit()
        db.refresh(db_attendance)
        return db_attendance
    except Exception:
        db.rollback()
        raise

def get_attendance_today(db: Session, class_id: Optional[int] = None, class_ids: Optional[List[int]] = None) -> List[models.Attendance]:
    today = date.today()
    query = db.query(models.Attendance).filter(
        func.date(models.Attendance.marked_at) == today
    )
    if class_id:
        query = query.filter(models.Attendance.class_id == class_id)
    if class_ids:
        query = query.filter(models.Attendance.class_id.in_(class_ids))
    return query.all()

def get_attendance_by_class(db: Session, class_id: int, date_filter: Optional[date] = None) -> List[models.Attendance]:
    query = db.query(models.Attendance).filter(models.Attendance.class_id == class_id)
    if date_filter:
        query = query.filter(func.date(models.Attendance.marked_at) == date_filter)
    return query.all()

def check_attendance_exists(
    db: Session,
    student_id: int,
    class_id: int,
    check_date: date = None,
    check_in_type: Optional[str] = None
) -> bool:
    if not check_date:
        check_date = date.today()

    query = db.query(models.Attendance).filter(
        models.Attendance.student_id == student_id,
        models.Attendance.class_id == class_id,
        func.date(models.Attendance.marked_at) == check_date,
    )
    if check_in_type:
        query = query.filter(models.Attendance.check_in_type == check_in_type)
    return query.first() is not None

def get_attendance_record_for_date(
    db: Session,
    student_id: int,
    class_id: int,
    check_date: date = None,
    check_in_type: Optional[str] = None
) -> Optional[models.Attendance]:
    if not check_date:
        check_date = date.today()

    query = db.query(models.Attendance).filter(
        models.Attendance.student_id == student_id,
        models.Attendance.class_id == class_id,
        func.date(models.Attendance.marked_at) == check_date,
    )
    if check_in_type:
        query = query.filter(models.Attendance.check_in_type == check_in_type)
    return query.first()

def update_attendance(db: Session, attendance_id: int, update_data: dict) -> Optional[models.Attendance]:
    try:
        attendance = db.query(models.Attendance).filter(models.Attendance.id == attendance_id).first()
        if attendance:
            for key, value in update_data.items():
                if hasattr(attendance, key):
                    setattr(attendance, key, value)
            db.commit()
            db.refresh(attendance)
        return attendance
    except Exception:
        db.rollback()
        raise

# Global Attendance Settings CRUD
def get_attendance_settings(db: Session) -> models.AttendanceSettings:
    try:
        settings = db.query(models.AttendanceSettings).first()
        if not settings:
            # Create a default settings row
            settings = models.AttendanceSettings()
            db.add(settings)
            db.commit()
            db.refresh(settings)
        return settings
    except Exception:
        db.rollback()
        raise

def upsert_attendance_settings(db: Session, update_data: dict) -> models.AttendanceSettings:
    try:
        settings = get_attendance_settings(db)
        # Strip organization_id if present
        update_data.pop("organization_id", None)
        for key, value in update_data.items():
            if hasattr(settings, key):
                setattr(settings, key, value)
        db.commit()
        db.refresh(settings)
        return settings
    except Exception:
        db.rollback()
        raise

def get_attendance_by_date(db: Session, filter_date: date, class_id: Optional[int] = None, class_ids: Optional[List[int]] = None) -> List[models.Attendance]:
    """Get attendance records for a specific date"""
    query = db.query(models.Attendance).filter(
        func.date(models.Attendance.marked_at) == filter_date
    )
    if class_id:
        query = query.filter(models.Attendance.class_id == class_id)
    if class_ids:
        query = query.filter(models.Attendance.class_id.in_(class_ids))
    return query.all()

def get_attendance_by_class_and_date_range(db: Session, class_id: int, start_date: date, end_date: date) -> List[models.Attendance]:
    """Get attendance records for a class within a date range"""
    return db.query(models.Attendance).filter(
        and_(
            models.Attendance.class_id == class_id,
            func.date(models.Attendance.marked_at) >= start_date,
            func.date(models.Attendance.marked_at) <= end_date
        )
    ).all()

def get_attendance_by_student(db: Session, student_id: int, start_date: date = None, end_date: date = None) -> List[models.Attendance]:
    """Get attendance records for a specific student"""
    query = db.query(models.Attendance).filter(models.Attendance.student_id == student_id)
    
    if start_date:
        start_ts = datetime.combine(start_date, datetime.min.time())
        query = query.filter(models.Attendance.marked_at >= start_ts)
        
    if end_date:
        end_ts = datetime.combine(end_date, datetime.max.time())
        query = query.filter(models.Attendance.marked_at <= end_ts)
        
    return query.all()

# Teacher Face Embedding CRUD
def create_teacher_face_embedding(db: Session, teacher_id: int, embedding: str) -> models.TeacherFaceEmbedding:
    try:
        db.query(models.TeacherFaceEmbedding).filter(models.TeacherFaceEmbedding.teacher_id == teacher_id).delete()
        db_embedding = models.TeacherFaceEmbedding(
            teacher_id=teacher_id,
            embedding=embedding
        )
        db.add(db_embedding)
        db.commit()
        db.refresh(db_embedding)
        return db_embedding
    except Exception:
        db.rollback()
        raise

def get_teacher_face_embedding(db: Session, teacher_id: int) -> Optional[models.TeacherFaceEmbedding]:
    return db.query(models.TeacherFaceEmbedding).filter(models.TeacherFaceEmbedding.teacher_id == teacher_id).first()

def get_all_teacher_face_embeddings(db: Session) -> List[models.TeacherFaceEmbedding]:
    return db.query(models.TeacherFaceEmbedding).all()

