"""Dashboard statistics and activity endpoints"""
from datetime import date, datetime, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..core.security import require_teacher
from ..db.base import get_db
from ..db import crud
from ..services.class_service import ClassService

router = APIRouter(prefix="/dashboard", tags=["dashboard"])
class_service = ClassService()

@router.get("/stats")
async def get_dashboard_stats(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get dashboard statistics"""
    try:
        accessible_classes = await class_service.get_accessible_classes(current_user, db)
        class_ids = [cls.id for cls in accessible_classes]

        # Get counts (scoped)
        students = crud.get_students(db, class_ids=class_ids) if class_ids else []
        classes = accessible_classes

        teachers = []
        if current_user["role"] == "super_admin":
            teachers = crud.get_teachers(db)
        elif current_user["role"] == "admin":
            current_teacher = crud.get_teacher_by_id(db, current_user["user_id"])
            teachers = crud.get_teachers(db, org_id=current_teacher.organization_id if current_teacher else None)
        
        # Today's attendance
        today = date.today()
        today_attendance = crud.get_attendance_by_date(db, today, class_ids=class_ids) if hasattr(crud, 'get_attendance_by_date') else []
        
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
        accessible_classes = await class_service.get_accessible_classes(current_user, db)
        class_ids = [cls.id for cls in accessible_classes]

        # Get recent attendance records
        today = date.today()
        attendance_records = crud.get_attendance_by_date(db, today, class_ids=class_ids) if hasattr(crud, 'get_attendance_by_date') else []
        
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
