"""Class management endpoints"""
from typing import List, Optional
from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.orm import Session
from ..core.security import require_admin, require_teacher
from ..db.base import get_db
from ..services.class_service import ClassService
from ..schemas.class_schema import ClassCreate, ClassResponse, ClassWithStudents

router = APIRouter(prefix="/classes", tags=["classes"])
class_service = ClassService()

@router.post("/", response_model=ClassResponse)
async def create_class(
    class_data: ClassCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Create a new class (Admin only)"""
    try:
        class_obj = await class_service.create_class(class_data, db)
        return ClassResponse.model_validate(class_obj)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.get("/", response_model=List[ClassResponse])
async def get_classes(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get classes (Teachers see only their classes, Admins see all)"""
    teacher_id = None if current_user["role"] == "admin" else current_user["user_id"]
    classes = await class_service.get_classes(db, teacher_id=teacher_id)
    
    result = []
    for class_obj in classes:
        class_dict = ClassResponse.model_validate(class_obj).model_dump()
        class_dict["teacher"] = {
            "id": class_obj.teacher.id,
            "full_name": class_obj.teacher.full_name,
            "email": class_obj.teacher.email
        }
        result.append(class_dict)
    
    return result

@router.get("/{class_id}", response_model=ClassWithStudents)
async def get_class_by_id(
    class_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get class details with students"""
    # Check if teacher has access to this class
    has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
    
    class_obj = await class_service.get_class_by_id(class_id, db)
    if not class_obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    
    class_dict = ClassWithStudents.model_validate(class_obj).model_dump()
    class_dict["teacher"] = {
        "id": class_obj.teacher.id,
        "full_name": class_obj.teacher.full_name,
        "email": class_obj.teacher.email
    }
    class_dict["students"] = [
        {
            "id": student.id,
            "student_id": student.student_id,
            "full_name": student.full_name,
            "face_enrolled": student.face_enrolled
        }
        for student in class_obj.students
    ]
    
    return class_dict