"""Database ORM models"""
from sqlalchemy import Column, Integer, String, DateTime, Text, ForeignKey, Boolean, Float
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from .base import Base

class Organization(Base):
    __tablename__ = "organizations"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    code = Column(String, unique=True, index=True, nullable=False)
    status = Column(String, default="active")  # active, inactive
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    teachers = relationship("Teacher", back_populates="organization")
    classes = relationship("Class", back_populates="organization")
    attendance_settings = relationship("AttendanceSettings", back_populates="organization", uselist=False)

class Teacher(Base):
    __tablename__ = "teachers"
    
    id = Column(Integer, primary_key=True, index=True)
    teacher_id = Column(String, unique=True, index=True, nullable=False)
    full_name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    role = Column(String, default="teacher")  # super_admin, admin, teacher
    status = Column(String, default="active")  # active, inactive
    organization_id = Column(Integer, ForeignKey("organizations.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    classes = relationship("Class", back_populates="teacher")
    organization = relationship("Organization", back_populates="teachers")
    face_embedding = relationship("TeacherFaceEmbedding", back_populates="teacher", uselist=False)

    @property
    def organization_name(self):
        return self.organization.name if self.organization else None

class Class(Base):
    __tablename__ = "classes"
    
    id = Column(Integer, primary_key=True, index=True)
    class_name = Column(String, nullable=False)
    class_code = Column(String, unique=True, index=True, nullable=False)
    teacher_id = Column(Integer, ForeignKey("teachers.id"), nullable=False)
    organization_id = Column(Integer, ForeignKey("organizations.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    teacher = relationship("Teacher", back_populates="classes")
    students = relationship("Student", back_populates="class_obj")
    organization = relationship("Organization", back_populates="classes")

class Student(Base):
    __tablename__ = "students"
    
    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(String, unique=True, index=True, nullable=False)
    full_name = Column(String, nullable=False)
    class_id = Column(Integer, ForeignKey("classes.id"), nullable=False)
    face_enrolled = Column(Boolean, default=False)
    photo_path = Column(String, nullable=True)  # Profile picture path
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    class_obj = relationship("Class", back_populates="students")
    face_embedding = relationship("FaceEmbedding", back_populates="student", uselist=False)
    attendance_records = relationship("Attendance", back_populates="student")

class FaceEmbedding(Base):
    __tablename__ = "face_embeddings"
    
    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"), unique=True, nullable=False)
    embedding = Column(Text, nullable=False)  # JSON serialized embedding
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    student = relationship("Student", back_populates="face_embedding")


class TeacherFaceEmbedding(Base):
    __tablename__ = "teacher_face_embeddings"
    
    id = Column(Integer, primary_key=True, index=True)
    teacher_id = Column(Integer, ForeignKey("teachers.id"), unique=True, nullable=False)
    embedding = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    teacher = relationship("Teacher", back_populates="face_embedding")

class Attendance(Base):
    __tablename__ = "attendance"
    
    id = Column(Integer, primary_key=True, index=True)
    student_id = Column(Integer, ForeignKey("students.id"), nullable=False)
    class_id = Column(Integer, ForeignKey("classes.id"), nullable=False)
    marked_at = Column(DateTime(timezone=True), server_default=func.now())
    confidence_score = Column(Float, nullable=True)
    status = Column(String, default="present")
    check_in_type = Column(String, default="morning")
    
    # Relationships
    student = relationship("Student", back_populates="attendance_records")
    class_obj = relationship("Class")

class AttendanceSettings(Base):
    __tablename__ = "attendance_settings"

    id = Column(Integer, primary_key=True, index=True)
    organization_id = Column(Integer, ForeignKey("organizations.id"), unique=True, nullable=False)
    school_start_time = Column(String, default="08:00")
    late_cutoff_time = Column(String, default="08:15")
    auto_absent_time = Column(String, default="09:00")
    allow_late_arrivals = Column(Boolean, default=True)
    require_absence_excuse = Column(Boolean, default=False)
    multiple_checkins = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    organization = relationship("Organization", back_populates="attendance_settings")
