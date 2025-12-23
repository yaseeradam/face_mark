"""Class request/response schemas"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class ClassCreate(BaseModel):
    class_name: str
    class_code: str
    teacher_id: int

class ClassResponse(BaseModel):
    id: int
    class_name: str
    class_code: str
    teacher_id: int
    created_at: datetime
    teacher: Optional[dict] = None  # Will be populated with teacher info
    
    class Config:
        from_attributes = True

class ClassWithStudents(ClassResponse):
    students: List[dict] = []