"""Attendance request/response schemas"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class AttendanceResponse(BaseModel):
    id: int
    student_id: int
    class_id: int
    marked_at: datetime
    confidence_score: Optional[float]
    status: Optional[str] = None
    check_in_type: Optional[str] = None
    student: Optional[dict] = None  # Will be populated with student info
    
    class Config:
        from_attributes = True

class AttendanceWithDetails(AttendanceResponse):
    student_name: Optional[str] = None
    student_student_id: Optional[str] = None
    class_name: Optional[str] = None

class AttendanceSummary(BaseModel):
    total_students: int
    present_students: int
    attendance_rate: float
    date: datetime
