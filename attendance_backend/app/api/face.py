"""Face registration and verification endpoints"""
from fastapi import APIRouter, UploadFile, File, HTTPException, status, Depends, Form
from typing import Optional
from sqlalchemy.orm import Session
from ..core.security import require_teacher, require_admin
from ..db.base import get_db
from ..services.face_service import FaceService
from ..services.class_service import ClassService
from ..services.attendance_service import AttendanceService
from ..schemas.face import FaceRegisterResponse, FaceVerifyResponse

router = APIRouter(prefix="/face", tags=["face"])
face_service = FaceService()
class_service = ClassService()
attendance_service = AttendanceService()

@router.post("/register", response_model=FaceRegisterResponse)
async def register_face(
    student_id: int = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Register a face for a student"""
    # Ensure admin has access to the student's class (org isolation)
    from ..db import crud
    student = crud.get_student_by_id(db, student_id)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    has_access = await class_service.check_teacher_access(student.class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this student")

    # Validate file type - be lenient since camera captures may not have proper MIME type
    allowed_extensions = ['.jpg', '.jpeg', '.png', '.webp']
    is_image_type = file.content_type and file.content_type.startswith('image/')
    has_image_ext = any(file.filename.lower().endswith(ext) for ext in allowed_extensions) if file.filename else False
    is_octet_stream = file.content_type == 'application/octet-stream'  # Sometimes sent by camera
    
    if not (is_image_type or has_image_ext or is_octet_stream):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File must be an image. Got: {file.content_type}, filename: {file.filename}"
        )
    
    try:
        # Read image data
        image_data = await file.read()
        
        # Register face
        success, message = await face_service.register_face(image_data, student_id, db)
        
        return FaceRegisterResponse(
            success=success,
            message=message,
            student_id=student_id if success else None
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error processing face registration: {str(e)}"
        )

@router.post("/verify", response_model=FaceVerifyResponse)
async def verify_face(
    class_id: Optional[int] = Form(None),
    auto_mark: bool = Form(False),
    check_in_type: str = Form("morning"),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Verify a face and optionally mark attendance if recognized"""
    # Check if teacher has access to this class IF class_id provided
    if class_id:
        has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
        if not has_access:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
    elif current_user["role"] != "super_admin":
        accessible_classes = await class_service.get_accessible_classes(current_user, db)
        if not accessible_classes:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No accessible classes")
    
    # Validate file type - be lenient since camera captures may not have proper MIME type
    allowed_extensions = ['.jpg', '.jpeg', '.png', '.webp']
    is_image_type = file.content_type and file.content_type.startswith('image/')
    has_image_ext = any(file.filename.lower().endswith(ext) for ext in allowed_extensions) if file.filename else False
    is_octet_stream = file.content_type == 'application/octet-stream'
    
    if not (is_image_type or has_image_ext or is_octet_stream):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File must be an image. Got: {file.content_type}, filename: {file.filename}"
        )
    
    try:
        # Read image data
        image_data = await file.read()
        
        # Verify face
        class_ids = None
        if not class_id and current_user["role"] != "super_admin":
            class_ids = [cls.id for cls in accessible_classes]

        success, message, student_id, confidence_score, threshold = await face_service.verify_face(
            image_data,
            db,
            class_id=class_id,
            class_ids=class_ids
        )
        
        attendance_marked = False
        student_name = None
        photo_path = None
        target_class_id = None
        
        if success and student_id:
            from ..db import crud
            student = crud.get_student_by_id(db, student_id)
            if student:
                student_name = student.full_name
                photo_path = student.photo_path
                
                # Determine class_id if not provided
                target_class_id = class_id if class_id else student.class_id
                
                # Check status
                is_marked = crud.check_attendance_exists(db, student_id, target_class_id, check_in_type=check_in_type)
                attendance_marked = is_marked
                
                if auto_mark and not is_marked:
                    try:
                        # Mark attendance
                        await attendance_service.mark_attendance(
                            student_id,
                            target_class_id,
                            confidence_score,
                            db,
                            check_in_type=check_in_type
                        )
                        attendance_marked = True
                        message += " (Attendance marked)"
                    except ValueError as e:
                         # Should not happen given check above, but safe to catch
                         pass
                elif is_marked:
                    message = f"Face recognized: {student_name} (Already present)"

        
        return FaceVerifyResponse(
            success=success,
            message=message,
            student_id=student_id,
            student_name=student_name,
            confidence_score=confidence_score,
            threshold=threshold,
            attendance_marked=attendance_marked,
            photo_path=photo_path,
            class_id=target_class_id
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error processing face verification: {str(e)}"
        )
