"""Student CRUD and management endpoints"""
from typing import List, Optional
from fastapi import APIRouter, HTTPException, status, Depends, Query
from sqlalchemy.orm import Session
from ..core.security import require_teacher
from ..db.base import get_db
from ..services.student_service import StudentService
from ..services.class_service import ClassService
from ..schemas.student import StudentCreate, StudentUpdate, StudentResponse, StudentWithClass

router = APIRouter(prefix="/students", tags=["students"])
student_service = StudentService()
class_service = ClassService()

@router.post("/")
async def create_student(
    student_data: StudentCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Create a new student"""
    try:
        print(f"Creating student: {student_data}")
        
        # Check if teacher has access to the class
        has_access = await class_service.check_teacher_access(student_data.class_id, current_user["user_id"], db)
        if not has_access:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
        
        student = await student_service.create_student(student_data, db)
        print(f"Student created: {student.id}")
        
        return {
            "id": student.id,
            "student_id": student.student_id,
            "full_name": student.full_name,
            "class_id": student.class_id,
            "face_enrolled": student.face_enrolled
        }
    except ValueError as e:
        print(f"ValueError: {e}")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error creating student: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))

@router.get("/")
async def get_students(
    class_id: Optional[int] = Query(None, description="Filter by class ID"),
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get students, optionally filtered by class"""
    try:
        # For admin, get all students
        if current_user["role"] == "admin":
            all_students = await student_service.get_students(db, class_id=class_id)
        elif class_id:
            # Check access for specific class
            has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
            if not has_access:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
            all_students = await student_service.get_students(db, class_id=class_id)
        else:
            # Get students from all teacher's classes
            teacher_classes = await class_service.get_classes(db, teacher_id=current_user["user_id"])
            all_students = []
            for cls in teacher_classes:
                students = await student_service.get_students(db, class_id=cls.id)
                all_students.extend(students)
        
        result = []
        for student in all_students:
            result.append({
                "id": student.id,
                "student_id": student.student_id,
                "full_name": student.full_name,
                "class_id": student.class_id,
                "face_enrolled": student.face_enrolled,
                "class_name": student.class_obj.class_name if student.class_obj else None
            })
        
        return result
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error getting students: {e}")
        return []

@router.get("/{student_id}", response_model=StudentWithClass)
async def get_student_by_id(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get student by ID"""
    student = await student_service.get_student_by_id(student_id, db)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    
    # Check if teacher has access to this student's class
    has_access = await class_service.check_teacher_access(student.class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this student")
    
    student_dict = StudentWithClass.model_validate(student).model_dump()
    if student.class_obj:
        student_dict["class_name"] = student.class_obj.class_name
    
    return student_dict

@router.put("/{student_id}", response_model=StudentResponse)
async def update_student(
    student_id: int,
    student_data: StudentUpdate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Update a student"""
    student = await student_service.get_student_by_id(student_id, db)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    
    # Check if teacher has access to this student's class
    has_access = await class_service.check_teacher_access(student.class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this student")
    
    # If changing class, check access to new class
    if student_data.class_id and student_data.class_id != student.class_id:
        has_new_access = await class_service.check_teacher_access(student_data.class_id, current_user["user_id"], db)
        if not has_new_access:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to target class")
    
    try:
        updated_student = await student_service.update_student(student_id, student_data, db)
        return StudentResponse.model_validate(updated_student)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.delete("/{student_id}")
async def delete_student(
    student_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Delete a student"""
    student = await student_service.get_student_by_id(student_id, db)
    if not student:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Student not found")
    
    # Check if teacher has access to this student's class
    has_access = await class_service.check_teacher_access(student.class_id, current_user["user_id"], db)
    if not has_access:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this student")
    
    try:
        await student_service.delete_student(student_id, db)
        return {"message": "Student deleted successfully"}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))