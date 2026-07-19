"""Teacher management endpoints"""
from typing import List
from fastapi import APIRouter, HTTPException, status, Depends, UploadFile, File
from sqlalchemy.orm import Session
from ..core.security import require_admin, require_teacher, get_password_hash, verify_password
from ..db.base import get_db
from ..db import crud
from ..services.teacher_service import TeacherService
from ..services.teacher_face_service import TeacherFaceService
from ..schemas.teacher import TeacherCreate, TeacherResponse, TeacherUpdate
from pydantic import BaseModel

router = APIRouter(prefix="/teachers", tags=["teachers"])
teacher_service = TeacherService()
teacher_face_service = TeacherFaceService()

class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str

# ===== PROFILE ENDPOINTS =====

@router.get("/me")
async def get_current_user_profile(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get current user's profile"""
    try:
        teacher = crud.get_teacher_by_id(db, current_user["user_id"])
        if not teacher:
            raise HTTPException(status_code=404, detail="User not found")
        
        face_embedding = crud.get_teacher_face_embedding(db, teacher.id)
        return {
            "id": teacher.id,
            "teacher_id": teacher.teacher_id,
            "full_name": teacher.full_name,
            "email": teacher.email,
            "role": teacher.role,
            "status": getattr(teacher, 'status', 'active'),
            "created_at": teacher.created_at.isoformat() if teacher.created_at else None,
            "has_face_id": face_embedding is not None
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error getting profile: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/change-password")
async def change_password(
    request: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Change current user's password"""
    try:
        teacher = crud.get_teacher_by_id(db, current_user["user_id"])
        if not teacher:
            raise HTTPException(status_code=404, detail="User not found")
        
        # Verify old password
        if not verify_password(request.old_password, teacher.password_hash):
            raise HTTPException(status_code=400, detail="Current password is incorrect")
        
        # Update password
        new_hash = get_password_hash(request.new_password)
        crud.update_teacher(db, teacher.id, {"password_hash": new_hash})
        
        return {"success": True, "message": "Password changed successfully"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error changing password: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/setup-face-id")
async def setup_face_id(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Set up face ID for teacher login"""
    try:
        allowed_extensions = ['.jpg', '.jpeg', '.png', '.webp']
        is_image_type = file.content_type and file.content_type.startswith('image/')
        has_image_ext = any(file.filename.lower().endswith(ext) for ext in allowed_extensions) if file.filename else False
        is_octet_stream = file.content_type == 'application/octet-stream'
        if not (is_image_type or has_image_ext or is_octet_stream):
            raise HTTPException(status_code=400, detail="File must be an image")
        
        image_data = await file.read()
        success, message = await teacher_face_service.register_face_id(image_data, current_user["user_id"], db)
        if not success:
            raise HTTPException(status_code=400, detail=message)
        return {"success": True, "message": message}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error setting up face ID: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ===== ADMIN ENDPOINTS =====

@router.post("/", response_model=TeacherResponse)
async def create_teacher(
    teacher_data: TeacherCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Create a new teacher (Admin only)"""
    try:
        teacher_dict = teacher_data.model_dump()
        # Admins/super admins can only create teacher role unless super_admin
        if current_user["role"] != "super_admin":
            if teacher_dict.get("role") in ["admin", "super_admin"]:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Super admin role not allowed")

        teacher = await teacher_service.create_teacher(TeacherCreate(**teacher_dict), db)
        return TeacherResponse.model_validate(teacher)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.get("/", response_model=List[TeacherResponse])
async def get_teachers(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Get all teachers (Admin only)"""
    teachers = await teacher_service.get_teachers(db)
    return [TeacherResponse.model_validate(teacher) for teacher in teachers]

@router.get("/{teacher_id}", response_model=TeacherResponse)
async def get_teacher(
    teacher_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Get teacher by ID (Admin only)"""
    teacher = await teacher_service.get_teacher_by_id(teacher_id, db)
    if not teacher:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Teacher not found")
    return TeacherResponse.model_validate(teacher)

@router.put("/{teacher_id}", response_model=TeacherResponse)
async def update_teacher(
    teacher_id: int,
    teacher_data: dict,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Update teacher (Admin only)"""
    try:
        teacher = await teacher_service.update_teacher(teacher_id, teacher_data, db)
        if not teacher:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Teacher not found")
        return TeacherResponse.model_validate(teacher)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.delete("/{teacher_id}")
async def delete_teacher(
    teacher_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Delete teacher (Admin only)"""
    try:
        # Prevent self deletion
        if current_user["user_id"] == teacher_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot delete your own account")
            
        success = await teacher_service.delete_teacher(teacher_id, db)
        if not success:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Teacher not found")
        return {"message": "Teacher deleted successfully"}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.post("/bulk-delete")
async def bulk_delete_teachers(
    request_body: dict,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Delete multiple teachers (Admin only)"""
    try:
        teacher_ids = request_body.get('teacher_ids', [])
        if not teacher_ids:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No teacher IDs provided")

        deleted_count = await teacher_service.bulk_delete_teachers(teacher_ids, db)
        return {
            "message": f"{deleted_count} teacher(s) deleted successfully",
            "deleted_count": deleted_count
        }
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.get("/export/csv")
async def export_teachers_csv(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Export all teachers to CSV (Admin only)"""
    from fastapi.responses import StreamingResponse
    import io
    import csv
    from datetime import datetime
    
    teachers = await teacher_service.get_teachers(db)
    
    # Create CSV in memory
    output = io.StringIO()
    writer = csv.writer(output)
    
    # Write header
    writer.writerow(['ID', 'Teacher ID', 'Full Name', 'Email', 'Role', 'Status', 'Created At'])
    
    # Write data
    for teacher in teachers:
        writer.writerow([
            teacher.id,
            teacher.teacher_id,
            teacher.full_name,
            teacher.email,
            teacher.role,
            getattr(teacher, 'status', 'active'),
            teacher.created_at.strftime('%Y-%m-%d %H:%M:%S') if teacher.created_at else ''
        ])
    
    # Prepare response
    output.seek(0)
    filename = f"teachers_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )
