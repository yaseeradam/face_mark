"""Face recognition request/response schemas"""
from pydantic import BaseModel
from typing import Optional

class FaceRegisterResponse(BaseModel):
    success: bool
    message: str
    student_id: Optional[int] = None

class FaceVerifyResponse(BaseModel):
    success: bool
    message: str
    student_id: Optional[int] = None
    student_name: Optional[str] = None
    confidence_score: Optional[float] = None
    threshold: Optional[float] = None  # Similarity threshold used
    attendance_marked: Optional[bool] = None
    photo_path: Optional[str] = None
    class_id: Optional[int] = None

class FaceVerifyRequest(BaseModel):
    class_id: int