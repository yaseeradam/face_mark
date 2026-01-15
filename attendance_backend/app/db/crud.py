"""Database CRUD operations"""
from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func, Date
from datetime import datetime, date
from . import models
from ..core.security import get_password_hash, verify_password

# Organization CRUD
def create_organization(db: Session, org_data: dict) -> models.Organization:
    db_org = models.Organization(
        name=org_data["name"],
        code=org_data["code"],
        status=org_data.get("status", "active")
    )
    db.add(db_org)
    db.commit()
    db.refresh(db_org)
    return db_org

def get_organization_by_id(db: Session, org_id: int) -> Optional[models.Organization]:
    return db.query(models.Organization).filter(models.Organization.id == org_id).first()

def get_organization_by_code(db: Session, code: str) -> Optional[models.Organization]:
    return db.query(models.Organization).filter(models.Organization.code == code).first()

def get_organizations(db: Session) -> List[models.Organization]:
    return db.query(models.Organization).all()

def update_organization(db: Session, org_id: int, update_data: dict) -> Optional[models.Organization]:
    org = get_organization_by_id(db, org_id)
    if org:
        for key, value in update_data.items():
            if hasattr(org, key):
                setattr(org, key, value)
        db.commit()
        db.refresh(org)
    return org

def delete_organization(db: Session, org_id: int) -> bool:
    org = get_organization_by_id(db, org_id)
    if org:
        db.delete(org)
        db.commit()
        return True
    return False

# Teacher CRUD
def create_teacher(db: Session, teacher_data: dict) -> models.Teacher:
    hashed_password = get_password_hash(teacher_data["password"])
    db_teacher = models.Teacher(
        teacher_id=teacher_data["teacher_id"],
        full_name=teacher_data["full_name"],
        email=teacher_data["email"],
        password_hash=hashed_password,
        role=teacher_data.get("role", "teacher"),
        status=teacher_data.get("status", "active"),
        organization_id=teacher_data.get("organization_id")
    )
    db.add(db_teacher)
    db.commit()
    db.refresh(db_teacher)
    return db_teacher

def get_teacher_by_email(db: Session, email: str) -> Optional[models.Teacher]:
    return db.query(models.Teacher).filter(models.Teacher.email == email).first()

def get_teacher_by_teacher_id(db: Session, teacher_id: str) -> Optional[models.Teacher]:
    return db.query(models.Teacher).filter(models.Teacher.teacher_id == teacher_id).first()

def get_teacher_by_id(db: Session, teacher_id: int) -> Optional[models.Teacher]:
    return db.query(models.Teacher).filter(models.Teacher.id == teacher_id).first()

def get_teachers(db: Session, skip: int = 0, limit: int = 100, org_id: Optional[int] = None) -> List[models.Teacher]:
    query = db.query(models.Teacher)
    if org_id:
        query = query.filter(models.Teacher.organization_id == org_id)
    return query.offset(skip).limit(limit).all()

def authenticate_teacher(db: Session, email: str, password: str) -> Optional[models.Teacher]:
    teacher = get_teacher_by_email(db, email)
    if not teacher or not verify_password(password, teacher.password_hash):
        return None
    return teacher

# Class CRUD
def create_class(db: Session, class_data: dict) -> models.Class:
    db_class = models.Class(**class_data)
    db.add(db_class)
    db.commit()
    db.refresh(db_class)
    return db_class

def get_class_by_id(db: Session, class_id: int) -> Optional[models.Class]:
    return db.query(models.Class).filter(models.Class.id == class_id).first()

def get_classes(db: Session, teacher_id: Optional[int] = None, org_id: Optional[int] = None) -> List[models.Class]:
    query = db.query(models.Class)
    if teacher_id:
        query = query.filter(models.Class.teacher_id == teacher_id)
    if org_id:
        query = query.filter(models.Class.organization_id == org_id)
    return query.all()

# Student CRUD
def create_student(db: Session, student_data: dict) -> models.Student:
    db_student = models.Student(**student_data)
    db.add(db_student)
    db.commit()
    db.refresh(db_student)
    return db_student

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
    student = get_student_by_id(db, student_id)
    if student:
        student.face_enrolled = enrolled
        if photo_path:
            student.photo_path = photo_path
        db.commit()
        db.refresh(student)
    return student

def update_student(db: Session, student_id: int, update_data: dict) -> models.Student:
    student = get_student_by_id(db, student_id)
    if student:
        for key, value in update_data.items():
            if hasattr(student, key):
                setattr(student, key, value)
        db.commit()
        db.refresh(student)
    return student

def delete_student(db: Session, student_id: int) -> bool:
    student = get_student_by_id(db, student_id)
    if student:
        # Delete face embedding first
        db.query(models.FaceEmbedding).filter(models.FaceEmbedding.student_id == student_id).delete()
        # Delete attendance records
        db.query(models.Attendance).filter(models.Attendance.student_id == student_id).delete()
        # Delete student
        db.delete(student)
        db.commit()
        return True
    return False

# Teacher UPDATE/DELETE
def update_teacher(db: Session, teacher_id: int, update_data: dict) -> models.Teacher:
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

def delete_teacher(db: Session, teacher_id: int) -> bool:
    teacher = get_teacher_by_id(db, teacher_id)
    if teacher:
        db.delete(teacher)
        db.commit()
        return True
    return False

# Class UPDATE/DELETE
def update_class(db: Session, class_id: int, update_data: dict) -> models.Class:
    class_obj = get_class_by_id(db, class_id)
    if class_obj:
        for key, value in update_data.items():
            if hasattr(class_obj, key):
                setattr(class_obj, key, value)
        db.commit()
        db.refresh(class_obj)
    return class_obj

def delete_class(db: Session, class_id: int) -> bool:
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

# Face Embedding CRUD
def create_face_embedding(db: Session, student_id: int, embedding: str) -> models.FaceEmbedding:
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

def get_face_embedding(db: Session, student_id: int) -> Optional[models.FaceEmbedding]:
    return db.query(models.FaceEmbedding).filter(models.FaceEmbedding.student_id == student_id).first()

def get_all_face_embeddings_by_class(db: Session, class_id: int) -> List[models.FaceEmbedding]:
    return db.query(models.FaceEmbedding).join(models.Student).filter(
        models.Student.class_id == class_id
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
    
    # Create start and end of day daterange
    from datetime import datetime
    start_of_day = datetime.combine(check_date, datetime.min.time())
    end_of_day = datetime.combine(check_date, datetime.max.time())
    
    query = db.query(models.Attendance).filter(
        and_(
            models.Attendance.student_id == student_id,
            models.Attendance.class_id == class_id,
            models.Attendance.marked_at >= start_of_day,
            models.Attendance.marked_at <= end_of_day
        )
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
    
    from datetime import datetime
    start_of_day = datetime.combine(check_date, datetime.min.time())
    end_of_day = datetime.combine(check_date, datetime.max.time())

    query = db.query(models.Attendance).filter(
        and_(
            models.Attendance.student_id == student_id,
            models.Attendance.class_id == class_id,
            models.Attendance.marked_at >= start_of_day,
            models.Attendance.marked_at <= end_of_day
        )
    )
    if check_in_type:
        query = query.filter(models.Attendance.check_in_type == check_in_type)
    return query.first()

def update_attendance(db: Session, attendance_id: int, update_data: dict) -> Optional[models.Attendance]:
    attendance = db.query(models.Attendance).filter(models.Attendance.id == attendance_id).first()
    if attendance:
        for key, value in update_data.items():
            if hasattr(attendance, key):
                setattr(attendance, key, value)
        db.commit()
        db.refresh(attendance)
    return attendance

# Attendance Settings CRUD
def get_attendance_settings_by_org_id(db: Session, org_id: int) -> Optional[models.AttendanceSettings]:
    return db.query(models.AttendanceSettings).filter(models.AttendanceSettings.organization_id == org_id).first()

def upsert_attendance_settings(db: Session, org_id: int, update_data: dict) -> models.AttendanceSettings:
    settings = get_attendance_settings_by_org_id(db, org_id)
    if settings:
        for key, value in update_data.items():
            if hasattr(settings, key):
                setattr(settings, key, value)
        db.commit()
        db.refresh(settings)
        return settings

    settings = models.AttendanceSettings(
        organization_id=org_id,
        **update_data
    )
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return settings

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
    
    from datetime import datetime
    
    if start_date:
        start_ts = datetime.combine(start_date, datetime.min.time())
        query = query.filter(models.Attendance.marked_at >= start_ts)
        
    if end_date:
        end_ts = datetime.combine(end_date, datetime.max.time())
        query = query.filter(models.Attendance.marked_at <= end_ts)
        
    return query.all()
