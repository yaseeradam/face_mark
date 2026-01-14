"""Teacher request/response schemas"""
from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime

class TeacherCreate(BaseModel):
    teacher_id: str
    full_name: str
    email: EmailStr
    password: str
    role: Optional[str] = "teacher"
    status: Optional[str] = "active"
    organization_id: Optional[int] = None

class TeacherUpdate(BaseModel):
    user_id: Optional[str] = None
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    role: Optional[str] = None
    status: Optional[str] = None
    organization_id: Optional[int] = None

class TeacherResponse(BaseModel):
    id: int
    teacher_id: str
    full_name: str
    email: str
    role: str
    status: Optional[str] = "active"
    organization_id: Optional[int] = None
    organization_name: Optional[str] = None
    created_at: datetime
    
    class Config:
        from_attributes = True

class TeacherLogin(BaseModel):
    identifier: str
    password: str

class TeacherLoginLegacy(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    teacher: TeacherResponse
