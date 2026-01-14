"""Attendance marking and fetching endpoints"""
from typing import List, Optional
from datetime import date
from fastapi import APIRouter, HTTPException, status, Depends, Query
from sqlalchemy.orm import Session
from ..core.security import require_teacher
from ..db.base import get_db
from ..services.attendance_service import AttendanceService
from ..services.class_service import ClassService
from ..schemas.attendance import AttendanceResponse, AttendanceWithDetails, AttendanceSummary

router = APIRouter(prefix="/attendance", tags=["attendance"])
attendance_service = AttendanceService()
class_service = ClassService()

@router.post("/mark", response_model=AttendanceResponse)
async def mark_attendance(
    student_id: int,
    class_id: int,
    confidence_score: float,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Mark attendance for a student (Internal use - called by face verification)"""
    # Check if teacher has access to this class
    has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
    
    try:
        attendance = await attendance_service.mark_attendance(student_id, class_id, confidence_score, db)
        return AttendanceResponse.model_validate(attendance)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.get("/today", response_model=List[AttendanceWithDetails])
async def get_attendance_today(
    class_id: Optional[int] = Query(None, description="Filter by class ID"),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get today's attendance records"""
    # Check access if class_id is specified
    if class_id:
        has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
        if not has_access:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
    
    # For non-super admins without class_id, filter by accessible classes
    if current_user["role"] != "super_admin" and not class_id:
        accessible_classes = await class_service.get_accessible_classes(current_user, db)
        class_ids = [cls.id for cls in accessible_classes]
        all_attendance = await attendance_service.get_attendance_today(db, class_ids=class_ids)
    else:
        all_attendance = await attendance_service.get_attendance_today(db, class_id=class_id)
    
    result = []
    for attendance in all_attendance:
        attendance_dict = AttendanceWithDetails.model_validate(attendance).model_dump()
        if attendance.student:
            attendance_dict["student_name"] = attendance.student.full_name
            attendance_dict["student_student_id"] = attendance.student.student_id
        if attendance.class_obj:
            attendance_dict["class_name"] = attendance.class_obj.class_name
        result.append(attendance_dict)
    
    return result

@router.get("/by-class/{class_id}", response_model=List[AttendanceWithDetails])
async def get_attendance_by_class(
    class_id: int,
    date_filter: Optional[date] = Query(None, description="Filter by date (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get attendance records for a specific class"""
    # Check if teacher has access to this class
    has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
    
    attendance_records = await attendance_service.get_attendance_by_class(class_id, db, date_filter=date_filter)
    
    result = []
    for attendance in attendance_records:
        attendance_dict = AttendanceWithDetails.model_validate(attendance).model_dump()
        if attendance.student:
            attendance_dict["student_name"] = attendance.student.full_name
            attendance_dict["student_student_id"] = attendance.student.student_id
        if attendance.class_obj:
            attendance_dict["class_name"] = attendance.class_obj.class_name
        result.append(attendance_dict)
    
    return result

@router.get("/summary/{class_id}", response_model=AttendanceSummary)
async def get_attendance_summary(
    class_id: int,
    date_filter: Optional[date] = Query(None, description="Filter by date (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get attendance summary for a class"""
    # Check if teacher has access to this class
    has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
    
    summary = await attendance_service.get_attendance_summary(class_id, db, date_filter=date_filter)
    return AttendanceSummary(**summary)

@router.get("/history")
async def get_attendance_history(
    date: Optional[str] = Query(None, description="Filter by date YYYY-MM-DD"),
    class_id: Optional[int] = Query(None, description="Filter by class ID"),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get attendance history with optional date filter"""
    from datetime import datetime as dt
    try:
        # Parse date if provided
        filter_date = None
        if date:
            try:
                filter_date = dt.strptime(date, "%Y-%m-%d").date()
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
        
        # Get attendance records
        class_ids = None
        if current_user["role"] != "super_admin" and not class_id:
            accessible_classes = await class_service.get_accessible_classes(current_user, db)
            class_ids = [cls.id for cls in accessible_classes]

        if filter_date:
            records = await attendance_service.get_attendance_by_date(db, filter_date, class_id=class_id, class_ids=class_ids)
        else:
            records = await attendance_service.get_attendance_today(db, class_id=class_id, class_ids=class_ids)
        
        result = []
        for record in records:
            result.append({
                "id": record.id,
                "student_id": record.student_id,
                "student_name": record.student.full_name if record.student else "Unknown",
                "student_student_id": record.student.student_id if record.student else "Unknown",
                "class_id": record.class_id,
                "class_name": record.class_obj.class_name if record.class_obj else "Unknown",
                "timestamp": record.timestamp.isoformat() if record.timestamp else None,
                "confidence_score": record.confidence_score,
                "status": "present"
            })
        
        return result
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error getting attendance history: {e}")
        return []

@router.get("/export/csv")
async def export_attendance_csv(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Export today's attendance to CSV"""
    from fastapi.responses import StreamingResponse
    import io
    import csv
    from datetime import datetime
    
    # Get attendance records (Today)
    class_ids = None
    if current_user["role"] != "super_admin":
        accessible_classes = await class_service.get_accessible_classes(current_user, db)
        class_ids = [cls.id for cls in accessible_classes]
    records = await attendance_service.get_attendance_today(db, class_ids=class_ids)
    
    # Create CSV
    output = io.StringIO()
    writer = csv.writer(output)
    
    writer.writerow(['ID', 'Student Name', 'Student ID', 'Class ID', 'Time', 'Confidence'])
    
    for record in records:
        writer.writerow([
            record.id,
            getattr(record.student, 'full_name', 'Unknown'),
            getattr(record.student, 'student_id', 'Unknown'),
            record.class_id,
            record.timestamp.strftime('%H:%M:%S'),
            f"{record.confidence_score:.2f}%"
        ])
    
    output.seek(0)
    filename = f"attendance_export_{datetime.now().strftime('%Y%m%d')}.csv"
    
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )
