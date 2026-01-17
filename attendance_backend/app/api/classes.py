"""Class management endpoints - Simplified for testing"""
from typing import List, Optional
from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.orm import Session
from pydantic import BaseModel
from ..core.security import require_admin, require_admin_or_super_admin, verify_token
from ..db.base import get_db
from ..db import crud
from ..services.class_service import ClassService

router = APIRouter(prefix="/classes", tags=["classes"])
class_service = ClassService()

# Simple schemas
class SimpleClassCreate(BaseModel):
    class_name: str
    class_code: str
    teacher_id: Optional[int] = None
    organization_id: Optional[int] = None

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
    current_user: dict = Depends(require_admin_or_super_admin)
):
    """Create a new class"""
    try:
        print(f"Received: {class_data}")
        
        # Use teacher_id from request or default to current user
        teacher_id = class_data.teacher_id if class_data.teacher_id else current_user["user_id"]
        teacher = crud.get_teacher_by_id(db, teacher_id)
        if not teacher:
            return {"success": False, "error": "Teacher not found"}

        organization_id = teacher.organization_id
        if current_user["role"] == "super_admin":
            if class_data.organization_id is None:
                return {"success": False, "error": "Organization is required"}
            if teacher.organization_id != class_data.organization_id:
                return {"success": False, "error": "Teacher must be in the selected organization"}
            organization_id = class_data.organization_id
        else:
            current_teacher = crud.get_teacher_by_id(db, current_user["user_id"])
            if not current_teacher or current_teacher.organization_id is None:
                return {"success": False, "error": "Organization not set for user"}
            if current_teacher and teacher.organization_id != current_teacher.organization_id:
                return {"success": False, "error": "Teacher must be in your organization"}
            organization_id = current_teacher.organization_id if current_teacher else None
            current_teacher = crud.get_teacher_by_id(db, current_user["user_id"])
            if not current_teacher or current_teacher.organization_id is None:
                return {"success": False, "error": "Organization not set for user"}
            if current_teacher and teacher.organization_id != current_teacher.organization_id:
                return {"success": False, "error": "Teacher must be in your organization"}
            organization_id = current_teacher.organization_id if current_teacher else None
        
        # Create class dict
        class_dict = {
            "class_name": class_data.class_name,
            "class_code": class_data.class_code,
            "teacher_id": teacher_id,
            "organization_id": organization_id
        }
        
        print(f"Creating with: {class_dict}")
        
        # Create directly in DB
        new_class = crud.create_class(db, class_dict)
        
        return {
            "success": True,
            "id": new_class.id,
            "class_name": new_class.class_name,
            "class_code": new_class.class_code,
            "teacher_id": new_class.teacher_id,
            "organization_id": new_class.organization_id,
            "organization_name": new_class.organization.name if new_class.organization else None
        }
    except Exception as e:
        print(f"Error: {e}")
        return {"success": False, "error": str(e)}

@router.get("/")
async def get_classes(
    org_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: dict = Depends(verify_token)
):
    """Get all classes"""
    try:
        role = current_user.get("role")
        if role == "super_admin":
            if org_id is None:
                raise HTTPException(status_code=400, detail="organization_id is required")
            classes = crud.get_classes(db, org_id=org_id)
        elif role in ["admin", "teacher"]:
            classes = await class_service.get_accessible_classes(current_user, db)
        else:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

        result = []
        for c in classes:
            result.append({
                "id": c.id,
                "class_name": c.class_name,
                "class_code": c.class_code,
                "teacher_id": c.teacher_id,
                "organization_id": c.organization_id,
                "organization_name": c.organization.name if c.organization else None,
                "teacher": {
                    "id": c.teacher.id,
                    "full_name": c.teacher.full_name,
                    "email": c.teacher.email
                } if c.teacher else None
            })
        return result
    except HTTPException:
        raise
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
    org_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: dict = Depends(verify_token)
):
    """Get class by ID"""
    try:
        class_obj = crud.get_class_by_id(db, class_id)
        if not class_obj:
            raise HTTPException(status_code=404, detail="Class not found")

        role = current_user.get("role")
        if role == "super_admin":
            if org_id is None or class_obj.organization_id != org_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")
        else:
            has_access = await class_service.check_teacher_access(class_id, current_user["user_id"], db)
            if not has_access:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied to this class")

        return {
            "id": class_obj.id,
            "class_name": class_obj.class_name,
            "class_code": class_obj.class_code,
            "teacher_id": class_obj.teacher_id,
            "organization_id": class_obj.organization_id,
            "organization_name": class_obj.organization.name if class_obj.organization else None,
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
    current_user: dict = Depends(require_admin_or_super_admin)
):
    """Update a class"""
    try:
        class_obj = crud.get_class_by_id(db, class_id)
        if not class_obj:
            raise HTTPException(status_code=404, detail="Class not found")

        if current_user["role"] != "super_admin":
            current_teacher = crud.get_teacher_by_id(db, current_user["user_id"])
            if not current_teacher or current_teacher.organization_id is None:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Organization not set for user")
            if current_teacher and class_obj.organization_id != current_teacher.organization_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")
        
        # Update fields
        update_data = {}
        if "class_name" in class_data:
            update_data["class_name"] = class_data["class_name"]
        if "class_code" in class_data:
            update_data["class_code"] = class_data["class_code"]
        if "teacher_id" in class_data:
            new_teacher = crud.get_teacher_by_id(db, class_data["teacher_id"])
            if not new_teacher:
                raise HTTPException(status_code=404, detail="Teacher not found")
            if current_user["role"] != "super_admin":
                if current_teacher and new_teacher.organization_id != current_teacher.organization_id:
                    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Teacher must be in your organization")
                update_data["organization_id"] = current_teacher.organization_id if current_teacher else None
            else:
                update_data["organization_id"] = new_teacher.organization_id
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
    current_user: dict = Depends(require_admin_or_super_admin)
):
    """Delete a class"""
    try:
        if current_user["role"] != "super_admin":
            current_teacher = crud.get_teacher_by_id(db, current_user["user_id"])
            class_obj = crud.get_class_by_id(db, class_id)
            if not class_obj:
                raise HTTPException(status_code=404, detail="Class not found")
            if current_teacher and class_obj.organization_id != current_teacher.organization_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

        result = crud.delete_class(db, class_id)
        return {"success": result}
    except Exception as e:
        return {"success": False, "error": str(e)}
