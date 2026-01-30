"""Student request/response schemas"""
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class StudentCreate(BaseModel):
    student_id: str
    full_name: str
    class_id: int

class StudentUpdate(BaseModel):
    student_id: Optional[str] = None
    full_name: Optional[str] = None
    class_id: Optional[int] = None

class StudentResponse(BaseModel):
    id: int
    student_id: str
    full_name: str
    class_id: int
    face_enrolled: bool
    photo_path: Optional[str] = None
    created_at: datetime
    class_obj: Optional[dict] = None  # Will be populated with class info
    
    class Config:
        from_attributes = True

class StudentWithClass(StudentResponse):
    class_name: Optional[str] = None
