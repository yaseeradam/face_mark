"""Authentication endpoints"""
from datetime import timedelta
from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.orm import Session
from ..core.security import create_access_token
from ..core.config import settings
from ..db.base import get_db
from ..services.teacher_service import TeacherService
from typing import Union
from ..schemas.teacher import TeacherLogin, TeacherLoginLegacy, TokenResponse, TeacherResponse

router = APIRouter(prefix="/auth", tags=["auth"])
teacher_service = TeacherService()

@router.post("/login", response_model=TokenResponse)
async def login(login_data: Union[TeacherLogin, TeacherLoginLegacy], db: Session = Depends(get_db)):
    """Teacher login endpoint"""
    identifier = login_data.identifier if isinstance(login_data, TeacherLogin) else login_data.email
    teacher = await teacher_service.authenticate_teacher(identifier, login_data.password, db)
    
    if not teacher:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )
    
    access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)
    access_token = create_access_token(
        data={"sub": str(teacher.id), "role": teacher.role},
        expires_delta=access_token_expires
    )
    
    return TokenResponse(
        access_token=access_token,
        token_type="bearer",
        teacher=TeacherResponse.model_validate(teacher)
    )
