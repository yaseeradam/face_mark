"""Authentication endpoints"""
from datetime import timedelta
from fastapi import APIRouter, HTTPException, status, Depends, UploadFile, File
from sqlalchemy.orm import Session
from ..core.security import create_access_token
from ..core.config import settings
from ..db.base import get_db
from ..db import crud
from ..services.teacher_service import TeacherService
from ..services.teacher_face_service import TeacherFaceService
from typing import Union
from ..schemas.teacher import TeacherLogin, TeacherLoginLegacy, TokenResponse, TeacherResponse

router = APIRouter(prefix="/auth", tags=["auth"])
teacher_service = TeacherService()
teacher_face_service = TeacherFaceService()

@router.post("/login", response_model=TokenResponse)
async def login(login_data: Union[TeacherLogin, TeacherLoginLegacy], db: Session = Depends(get_db)):
    """Teacher login endpoint"""
    identifier = login_data.identifier if isinstance(login_data, TeacherLogin) else login_data.email

    # Give a clear message for deactivated accounts instead of "wrong password".
    teacher_candidate = crud.get_teacher_by_email(db, identifier)
    if not teacher_candidate:
        teacher_candidate = crud.get_teacher_by_teacher_id(db, identifier)
    if teacher_candidate and getattr(teacher_candidate, "status", "active") != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive"
        )

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
    
    teacher_data = TeacherResponse.model_validate(teacher).model_dump()
    teacher_data["has_face_id"] = crud.get_teacher_face_embedding(db, teacher.id) is not None
    return TokenResponse(
        access_token=access_token,
        token_type="bearer",
        teacher=TeacherResponse.model_validate(teacher_data)
    )

@router.post("/face-login", response_model=TokenResponse)
async def face_login(file: UploadFile = File(...), db: Session = Depends(get_db)):
    """Login using Face ID"""
    try:
        allowed_extensions = ['.jpg', '.jpeg', '.png', '.webp']
        is_image_type = file.content_type and file.content_type.startswith('image/')
        has_image_ext = any(file.filename.lower().endswith(ext) for ext in allowed_extensions) if file.filename else False
        is_octet_stream = file.content_type == 'application/octet-stream'
        if not (is_image_type or has_image_ext or is_octet_stream):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File must be an image")

        image_data = await file.read()
        success, message, teacher_id, similarity, threshold = await teacher_face_service.verify_face_id(image_data, db)
        if not success or not teacher_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=message)

        teacher = await teacher_service.get_teacher_by_id(teacher_id, db)
        if not teacher:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Teacher not found")
        if getattr(teacher, "status", "active") != "active":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is inactive")

        access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)
        access_token = create_access_token(
            data={"sub": str(teacher.id), "role": teacher.role},
            expires_delta=access_token_expires
        )

        teacher_data = TeacherResponse.model_validate(teacher).model_dump()
        teacher_data["has_face_id"] = crud.get_teacher_face_embedding(db, teacher.id) is not None
        return TokenResponse(
            access_token=access_token,
            token_type="bearer",
            teacher=TeacherResponse.model_validate(teacher_data)
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
