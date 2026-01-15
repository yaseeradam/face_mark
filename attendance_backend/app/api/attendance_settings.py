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

def _get_org_id(db: Session, current_user: dict) -> int:
    teacher = crud.get_teacher_by_id(db, current_user["user_id"])
    org_id = teacher.organization_id if teacher else None
    if org_id is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Organization not set for user")
    return org_id

@router.get("", response_model=AttendanceSettingsResponse)
async def get_attendance_settings(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    org_id = _get_org_id(db, current_user)
    settings = crud.get_attendance_settings_by_org_id(db, org_id)
    if settings:
        return AttendanceSettingsResponse(
            organization_id=org_id,
            school_start_time=settings.school_start_time,
            late_cutoff_time=settings.late_cutoff_time,
            auto_absent_time=settings.auto_absent_time,
            allow_late_arrivals=settings.allow_late_arrivals,
            require_absence_excuse=settings.require_absence_excuse,
            multiple_checkins=settings.multiple_checkins,
        )

    return AttendanceSettingsResponse(
        organization_id=org_id,
        **DEFAULT_SETTINGS
    )

@router.put("", response_model=AttendanceSettingsResponse)
async def update_attendance_settings(
    payload: AttendanceSettingsUpdate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    org_id = _get_org_id(db, current_user)
    update_data = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not update_data:
        update_data = {}
    settings = crud.upsert_attendance_settings(db, org_id, update_data)
    return AttendanceSettingsResponse(
        organization_id=org_id,
        school_start_time=settings.school_start_time,
        late_cutoff_time=settings.late_cutoff_time,
        auto_absent_time=settings.auto_absent_time,
        allow_late_arrivals=settings.allow_late_arrivals,
        require_absence_excuse=settings.require_absence_excuse,
        multiple_checkins=settings.multiple_checkins,
    )
