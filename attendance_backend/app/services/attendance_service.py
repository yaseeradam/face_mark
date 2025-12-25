"""Attendance business logic"""
from typing import List, Optional
from sqlalchemy.orm import Session
from datetime import date, datetime
from ..db import crud, models

class AttendanceService:
    def __init__(self):
        pass
    
    async def mark_attendance(self, student_id: int, class_id: int, confidence_score: float, db: Session) -> models.Attendance:
        """Mark attendance for a student"""
        # Check if attendance already marked today
        if crud.check_attendance_exists(db, student_id, class_id):
            raise ValueError("Attendance already marked for today")
        
        # Verify student exists and belongs to the class
        student = crud.get_student_by_id(db, student_id)
        if not student:
            raise ValueError("Student not found")
        
        if student.class_id != class_id:
            raise ValueError("Student does not belong to this class")
        
        return crud.create_attendance(db, student_id, class_id, confidence_score)
    
    async def get_attendance_today(self, db: Session, class_id: Optional[int] = None) -> List[models.Attendance]:
        """Get today's attendance records"""
        return crud.get_attendance_today(db, class_id=class_id)
    
    async def get_attendance_by_class(self, class_id: int, db: Session, date_filter: Optional[date] = None) -> List[models.Attendance]:
        """Get attendance records for a specific class"""
        return crud.get_attendance_by_class(db, class_id, date_filter=date_filter)
    
    async def get_attendance_summary(self, class_id: int, db: Session, date_filter: Optional[date] = None) -> dict:
        """Get attendance summary for a class"""
        if not date_filter:
            date_filter = date.today()
        
        # Get total students in class
        students = crud.get_students(db, class_id=class_id)
        total_students = len(students)
        
        # Get attendance for the date
        attendance_records = crud.get_attendance_by_class(db, class_id, date_filter=date_filter)
        present_students = len(attendance_records)
        
        attendance_rate = (present_students / total_students * 100) if total_students > 0 else 0
        
        return {
            "total_students": total_students,
            "present_students": present_students,
            "attendance_rate": round(attendance_rate, 2),
            "date": date_filter
        }
    
    async def get_attendance_by_date(self, db: Session, filter_date: date, class_id: Optional[int] = None) -> List[models.Attendance]:
        """Get attendance records for a specific date"""
        return crud.get_attendance_by_date(db, filter_date, class_id=class_id)