"""Attendance settings schemas"""
from pydantic import BaseModel
from typing import Optional

class AttendanceSettingsBase(BaseModel):
    school_start_time: str
    late_cutoff_time: str
    auto_absent_time: str
    allow_late_arrivals: bool
    require_absence_excuse: bool
    multiple_checkins: bool

class AttendanceSettingsResponse(AttendanceSettingsBase):
    organization_id: int

class AttendanceSettingsUpdate(BaseModel):
    school_start_time: Optional[str] = None
    late_cutoff_time: Optional[str] = None
    auto_absent_time: Optional[str] = None
    allow_late_arrivals: Optional[bool] = None
    require_absence_excuse: Optional[bool] = None
    multiple_checkins: Optional[bool] = None
