"""Reports generation endpoints"""
from datetime import date, datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
import io
import csv
from ..core.security import require_teacher
from ..db.base import get_db
from ..db import crud
from ..services.class_service import ClassService

router = APIRouter(prefix="/reports", tags=["reports"])
class_service = ClassService()

@router.get("/attendance/{class_id}")
async def get_attendance_report(
    class_id: int,
    start_date: Optional[str] = Query(None, description="Start date YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="End date YYYY-MM-DD"),
    format: Optional[str] = Query("json", description="Output format: json or csv"),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get attendance report for a class"""
    try:
        # Check access
        has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
        if not has_access:
            raise HTTPException(status_code=403, detail="Access denied")
        
        # Get class info
        class_obj = crud.get_class_by_id(db, class_id)
        if not class_obj:
            raise HTTPException(status_code=404, detail="Class not found")
        
        # Parse dates
        start = datetime.strptime(start_date, "%Y-%m-%d").date() if start_date else date.today() - timedelta(days=30)
        end = datetime.strptime(end_date, "%Y-%m-%d").date() if end_date else date.today()
        
        # Get students in class
        students = crud.get_students(db, class_id=class_id)
        
        # Get attendance records
        attendance_records = []
        if hasattr(crud, 'get_attendance_by_class_and_date_range'):
            attendance_records = crud.get_attendance_by_class_and_date_range(db, class_id, start, end)
        
        # Build report
        report_data = {
            "class_id": class_id,
            "class_name": class_obj.class_name,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "total_students": len(students) if students else 0,
            "total_days": (end - start).days + 1,
            "students": []
        }
        
        for student in (students or []):
            student_attendance = [
                r for r in attendance_records
                if r.student_id == student.id and (r.status or "present") in ["present", "late"]
            ]
            days_present = len(student_attendance)
            total_days = report_data["total_days"]
            
            report_data["students"].append({
                "id": student.id,
                "student_id": student.student_id,
                "full_name": student.full_name,
                "days_present": days_present,
                "days_absent": total_days - days_present,
                "attendance_rate": round((days_present / total_days * 100) if total_days > 0 else 0, 1)
            })
        
        # Return CSV if requested
        if format == "csv":
            output = io.StringIO()
            writer = csv.writer(output)
            writer.writerow(["Student ID", "Name", "Days Present", "Days Absent", "Attendance Rate"])
            for s in report_data["students"]:
                writer.writerow([s["student_id"], s["full_name"], s["days_present"], s["days_absent"], f"{s['attendance_rate']}%"])
            output.seek(0)
            return StreamingResponse(
                iter([output.getvalue()]),
                media_type="text/csv",
                headers={"Content-Disposition": f"attachment; filename=attendance_report_{class_id}.csv"}
            )
        
        return report_data
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error generating report: {e}")
        return {"error": str(e)}

@router.get("/student/{student_id}")
async def get_student_report(
    student_id: int,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get attendance report for a specific student"""
    try:
        student = crud.get_student_by_id(db, student_id)
        if not student:
            raise HTTPException(status_code=404, detail="Student not found")
        
        # Parse dates
        start = datetime.strptime(start_date, "%Y-%m-%d").date() if start_date else date.today() - timedelta(days=30)
        end = datetime.strptime(end_date, "%Y-%m-%d").date() if end_date else date.today()
        
        # Get attendance records for student
        attendance_records = []
        if hasattr(crud, 'get_attendance_by_student'):
            attendance_records = crud.get_attendance_by_student(db, student_id, start, end)
        
        total_days = (end - start).days + 1
        days_present = len([r for r in attendance_records if (r.status or "present") in ["present", "late"]])
        
        return {
            "student_id": student.student_id,
            "full_name": student.full_name,
            "class_id": student.class_id,
            "class_name": student.class_obj.class_name if student.class_obj else None,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "total_days": total_days,
            "days_present": days_present,
            "days_absent": total_days - days_present,
            "attendance_rate": round((days_present / total_days * 100) if total_days > 0 else 0, 1),
            "attendance_history": [
                {
                    "date": r.marked_at.date().isoformat() if r.marked_at else None,
                    "time": r.marked_at.time().isoformat() if r.marked_at else None,
                    "confidence": r.confidence_score,
                    "status": r.status or "present"
                }
                for r in attendance_records
            ]
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error generating student report: {e}")
        return {"error": str(e)}
