"""Attendance settings endpoints"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ..core.security import require_teacher, require_admin
from ..db.base import get_db
from ..db import crud
from ..schemas.attendance_settings import AttendanceSettingsResponse, AttendanceSettingsUpdate

router = APIRouter(prefix="/attendance/settings", tags=["attendance-settings"])

DEFAULT_SETTINGS = {
    "school_start_time": "08:00",
    "late_cutoff_time": "08:15",
    "auto_absent_time": "09:00",
    "allow_late_arrivals": True,
    "require_absence_excuse": False,
    "multiple_checkins": False,
}

@router.get("", response_model=AttendanceSettingsResponse)
async def get_attendance_settings(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    settings = crud.get_attendance_settings(db)
    if settings:
        return AttendanceSettingsResponse(
            school_start_time=settings.school_start_time,
            late_cutoff_time=settings.late_cutoff_time,
            auto_absent_time=settings.auto_absent_time,
            allow_late_arrivals=settings.allow_late_arrivals,
            require_absence_excuse=settings.require_absence_excuse,
            multiple_checkins=settings.multiple_checkins,
        )

    return AttendanceSettingsResponse(
        **DEFAULT_SETTINGS
    )

@router.put("", response_model=AttendanceSettingsResponse)
async def update_attendance_settings(
    payload: AttendanceSettingsUpdate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    update_data = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not update_data:
        update_data = {}
    settings = crud.upsert_attendance_settings(db, update_data)
    return AttendanceSettingsResponse(
        school_start_time=settings.school_start_time,
        late_cutoff_time=settings.late_cutoff_time,
        auto_absent_time=settings.auto_absent_time,
        allow_late_arrivals=settings.allow_late_arrivals,
        require_absence_excuse=settings.require_absence_excuse,
        multiple_checkins=settings.multiple_checkins,
    )
