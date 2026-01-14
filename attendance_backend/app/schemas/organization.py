"""Organization request/response schemas"""
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

class OrganizationCreate(BaseModel):
    name: str
    code: str
    status: Optional[str] = "active"
    admin_email: EmailStr
    admin_full_name: str
    admin_teacher_id: str
    admin_password: str

class OrganizationUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    status: Optional[str] = None

class OrganizationResponse(BaseModel):
    id: int
    name: str
    code: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True

