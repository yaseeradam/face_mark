"""Dashboard statistics and activity endpoints"""
from datetime import date, datetime, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..core.security import require_teacher
from ..db.base import get_db
from ..db import crud

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

@router.get("/stats")
async def get_dashboard_stats(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get dashboard statistics"""
    try:
        # Get counts
        students = crud.get_students(db)
        classes = crud.get_classes(db)
        teachers = crud.get_teachers(db)
        
        # Today's attendance
        today = date.today()
        today_attendance = crud.get_attendance_by_date(db, today) if hasattr(crud, 'get_attendance_by_date') else []
        
        # Calculate attendance rate
        total_students = len(students) if students else 0
        present_today = len(today_attendance) if today_attendance else 0
        attendance_rate = (present_today / total_students * 100) if total_students > 0 else 0
        
        # Get enrolled faces count
        enrolled_faces = sum(1 for s in students if s.face_enrolled) if students else 0
        
        return {
            "total_students": total_students,
            "total_classes": len(classes) if classes else 0,
            "total_teachers": len(teachers) if teachers else 0,
            "present_today": present_today,
            "absent_today": total_students - present_today,
            "attendance_rate": round(attendance_rate, 1),
            "enrolled_faces": enrolled_faces,
            "pending_enrollments": total_students - enrolled_faces
        }
    except Exception as e:
        print(f"Error getting dashboard stats: {e}")
        return {
            "total_students": 0,
            "total_classes": 0,
            "total_teachers": 0,
            "present_today": 0,
            "absent_today": 0,
            "attendance_rate": 0,
            "enrolled_faces": 0,
            "pending_enrollments": 0
        }

@router.get("/activity")
async def get_recent_activity(
    limit: int = 10,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get recent activity (attendance records)"""
    try:
        # Get recent attendance records
        today = date.today()
        attendance_records = crud.get_attendance_by_date(db, today) if hasattr(crud, 'get_attendance_by_date') else []
        
        activities = []
        for record in attendance_records[:limit]:
            activities.append({
                "id": record.id,
                "type": "attendance",
                "description": f"{record.student.full_name if record.student else 'Unknown'} marked present",
                "timestamp": record.timestamp.isoformat() if record.timestamp else datetime.now().isoformat(),
                "student_name": record.student.full_name if record.student else "Unknown",
                "class_name": record.class_obj.class_name if record.class_obj else "Unknown"
            })
        
        return activities
    except Exception as e:
        print(f"Error getting activity: {e}")
        return []
