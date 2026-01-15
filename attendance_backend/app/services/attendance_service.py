"""Attendance business logic"""
from typing import List, Optional
from sqlalchemy.orm import Session
from datetime import date, datetime, time
from ..db import crud, models

class AttendanceService:
    def __init__(self):
        pass

    def _parse_time(self, value: str, fallback: time) -> time:
        try:
            parts = value.split(":")
            if len(parts) != 2:
                return fallback
            hour = int(parts[0])
            minute = int(parts[1])
            return time(hour=hour, minute=minute)
        except Exception:
            return fallback

    def _get_settings_for_class(self, class_id: int, db: Session) -> dict:
        class_obj = crud.get_class_by_id(db, class_id)
        org_id = class_obj.organization_id if class_obj else None
        settings = crud.get_attendance_settings_by_org_id(db, org_id) if org_id else None

        return {
            "school_start_time": self._parse_time(
                settings.school_start_time if settings else "08:00",
                time(hour=8, minute=0)
            ),
            "late_cutoff_time": self._parse_time(
                settings.late_cutoff_time if settings else "08:15",
                time(hour=8, minute=15)
            ),
            "auto_absent_time": self._parse_time(
                settings.auto_absent_time if settings else "09:00",
                time(hour=9, minute=0)
            ),
            "allow_late_arrivals": settings.allow_late_arrivals if settings else True,
            "require_absence_excuse": settings.require_absence_excuse if settings else False,
            "multiple_checkins": settings.multiple_checkins if settings else False,
        }

    def _determine_status(self, now: datetime, settings: dict) -> str:
        start_time = settings["school_start_time"]
        cutoff_time = settings["late_cutoff_time"]
        current_time = now.time()

        if current_time <= start_time:
            return "present"
        if current_time <= cutoff_time:
            return "late"
        return "absent"

    async def _auto_mark_absent_for_classes(self, db: Session, class_ids: List[int]) -> None:
        now = datetime.now()
        for class_id in class_ids:
            settings = self._get_settings_for_class(class_id, db)
            if now.time() < settings["auto_absent_time"]:
                continue

            students = crud.get_students(db, class_id=class_id)
            for student in students:
                existing = crud.get_attendance_record_for_date(
                    db,
                    student.id,
                    class_id,
                    check_in_type="morning"
                )
                if existing:
                    continue

                crud.create_attendance(
                    db,
                    student.id,
                    class_id,
                    confidence_score=None,
                    status="absent",
                    check_in_type="morning"
                )
    
    async def mark_attendance(
        self,
        student_id: int,
        class_id: int,
        confidence_score: float,
        db: Session,
        check_in_type: str = "morning"
    ) -> models.Attendance:
        """Mark attendance for a student"""
        settings = self._get_settings_for_class(class_id, db)
        now = datetime.now()
        status = self._determine_status(now, settings)

        if not settings["allow_late_arrivals"] and now.time() > settings["school_start_time"]:
            raise ValueError("Late arrivals are not allowed")
        
        # Verify student exists and belongs to the class
        student = crud.get_student_by_id(db, student_id)
        if not student:
            raise ValueError("Student not found")
        
        if student.class_id != class_id:
            raise ValueError("Student does not belong to this class")

        # Check if attendance already marked today
        if settings["multiple_checkins"]:
            existing = crud.get_attendance_record_for_date(
                db,
                student_id,
                class_id,
                check_in_type=check_in_type
            )
        else:
            existing = crud.get_attendance_record_for_date(db, student_id, class_id)

        if existing:
            if existing.status == "absent" and status != "absent":
                return crud.update_attendance(
                    db,
                    existing.id,
                    {
                        "status": status,
                        "marked_at": now,
                        "confidence_score": confidence_score,
                        "check_in_type": check_in_type
                    }
                )
            raise ValueError("Attendance already marked for today")

        return crud.create_attendance(
            db,
            student_id,
            class_id,
            confidence_score,
            status=status,
            check_in_type=check_in_type
        )
    
    async def get_attendance_today(self, db: Session, class_id: Optional[int] = None, class_ids: Optional[List[int]] = None) -> List[models.Attendance]:
        """Get today's attendance records"""
        if class_id:
            await self._auto_mark_absent_for_classes(db, [class_id])
        elif class_ids:
            await self._auto_mark_absent_for_classes(db, class_ids)
        return crud.get_attendance_today(db, class_id=class_id, class_ids=class_ids)
    
    async def get_attendance_by_class(self, class_id: int, db: Session, date_filter: Optional[date] = None) -> List[models.Attendance]:
        """Get attendance records for a specific class"""
        if not date_filter or date_filter == date.today():
            await self._auto_mark_absent_for_classes(db, [class_id])
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
        present_students = len([r for r in attendance_records if (r.status or "present") in ["present", "late"]])
        
        attendance_rate = (present_students / total_students * 100) if total_students > 0 else 0
        
        return {
            "total_students": total_students,
            "present_students": present_students,
            "attendance_rate": round(attendance_rate, 2),
            "date": date_filter
        }
    
    async def get_attendance_by_date(self, db: Session, filter_date: date, class_id: Optional[int] = None, class_ids: Optional[List[int]] = None) -> List[models.Attendance]:
        """Get attendance records for a specific date"""
        if filter_date == date.today():
            if class_id:
                await self._auto_mark_absent_for_classes(db, [class_id])
            elif class_ids:
                await self._auto_mark_absent_for_classes(db, class_ids)
        return crud.get_attendance_by_date(db, filter_date, class_id=class_id, class_ids=class_ids)
