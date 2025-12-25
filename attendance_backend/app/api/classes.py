"""Class management endpoints - Simplified for testing"""
from typing import List, Optional
from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.orm import Session
from pydantic import BaseModel
from ..core.security import require_admin, require_teacher
from ..db.base import get_db
from ..db import crud

router = APIRouter(prefix="/classes", tags=["classes"])

# Simple schemas
class SimpleClassCreate(BaseModel):
    class_name: str
    class_code: str
    teacher_id: Optional[int] = None

class SimpleClassResponse(BaseModel):
    id: int
    class_name: str
    class_code: str
    teacher_id: int
    
    class Config:
        from_attributes = True

@router.post("/")
async def create_class(
    class_data: SimpleClassCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Create a new class"""
    try:
        print(f"Received: {class_data}")
        
        # Use teacher_id from request or default to current user
        teacher_id = class_data.teacher_id if class_data.teacher_id else current_user["user_id"]
        
        # Create class dict
        class_dict = {
            "class_name": class_data.class_name,
            "class_code": class_data.class_code,
            "teacher_id": teacher_id
        }
        
        print(f"Creating with: {class_dict}")
        
        # Create directly in DB
        new_class = crud.create_class(db, class_dict)
        
        return {
            "success": True,
            "id": new_class.id,
            "class_name": new_class.class_name,
            "class_code": new_class.class_code,
            "teacher_id": new_class.teacher_id
        }
    except Exception as e:
        print(f"Error: {e}")
        return {"success": False, "error": str(e)}

@router.get("/")
async def get_classes(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get all classes"""
    try:
        classes = crud.get_classes(db)
        result = []
        for c in classes:
            result.append({
                "id": c.id,
                "class_name": c.class_name,
                "class_code": c.class_code,
                "teacher_id": c.teacher_id,
                "teacher": {
                    "id": c.teacher.id,
                    "full_name": c.teacher.full_name,
                    "email": c.teacher.email
                } if c.teacher else None
            })
        return result
    except Exception as e:
        print(f"Error getting classes: {e}")
        return []

@router.get("/test")
async def test_endpoint():
    """Test endpoint"""
    return {"status": "success", "message": "Classes API working!"}

@router.get("/{class_id}")
async def get_class_by_id(
    class_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_teacher)
):
    """Get class by ID"""
    try:
        class_obj = crud.get_class_by_id(db, class_id)
        if not class_obj:
            raise HTTPException(status_code=404, detail="Class not found")
        
        return {
            "id": class_obj.id,
            "class_name": class_obj.class_name,
            "class_code": class_obj.class_code,
            "teacher_id": class_obj.teacher_id,
            "students": [
                {"id": s.id, "student_id": s.student_id, "full_name": s.full_name}
                for s in class_obj.students
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.put("/{class_id}")
async def update_class(
    class_id: int,
    class_data: dict,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Update a class"""
    try:
        class_obj = crud.get_class_by_id(db, class_id)
        if not class_obj:
            raise HTTPException(status_code=404, detail="Class not found")
        
        # Update fields
        update_data = {}
        if "class_name" in class_data:
            update_data["class_name"] = class_data["class_name"]
        if "class_code" in class_data:
            update_data["class_code"] = class_data["class_code"]
        if "teacher_id" in class_data:
            update_data["teacher_id"] = class_data["teacher_id"]
        
        if update_data:
            updated = crud.update_class(db, class_id, update_data)
            return {
                "success": True,
                "id": updated.id,
                "class_name": updated.class_name,
                "class_code": updated.class_code,
                "teacher_id": updated.teacher_id
            }
        return {"success": True, "message": "No changes"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error updating class: {e}")
        return {"success": False, "error": str(e)}

@router.delete("/{class_id}")
async def delete_class(
    class_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_admin)
):
    """Delete a class"""
    try:
        result = crud.delete_class(db, class_id)
        return {"success": result}
    except Exception as e:
        return {"success": False, "error": str(e)}