"""Class business logic"""
from typing import List, Optional
from sqlalchemy.orm import Session
from ..db import crud, models
from ..schemas.class_schema import ClassCreate

class ClassService:
    def __init__(self):
        pass
    
    async def create_class(self, class_data: ClassCreate, db: Session) -> models.Class:
        """Create a new class"""
        # Check if class_code already exists
        existing_classes = crud.get_classes(db)
        for cls in existing_classes:
            if cls.class_code == class_data.class_code:
                raise ValueError("Class code already exists")
        
        # Verify teacher exists
        teacher = crud.get_teacher_by_id(db, class_data.teacher_id)
        if not teacher:
            raise ValueError("Teacher not found")
        
        class_dict = class_data.model_dump()
        return crud.create_class(db, class_dict)
    
    async def get_classes(self, db: Session, teacher_id: Optional[int] = None) -> List[models.Class]:
        """Get all classes, optionally filtered by teacher"""
        return crud.get_classes(db, teacher_id=teacher_id)

    async def get_accessible_classes(self, current_user: dict, db: Session) -> List[models.Class]:
        """Get classes the current user can access"""
        role = current_user.get("role")
        if role == "super_admin":
            return crud.get_classes(db)

        teacher = crud.get_teacher_by_id(db, current_user["user_id"])
        if teacher and role == "admin":
            return crud.get_classes(db, org_id=teacher.organization_id)

        return crud.get_classes(db, teacher_id=current_user["user_id"])
    
    async def get_class_by_id(self, class_id: int, db: Session) -> Optional[models.Class]:
        """Get class by ID"""
        return crud.get_class_by_id(db, class_id)
    
    async def check_teacher_access(self, class_id: int, teacher_id: int, db: Session) -> bool:
        """Check if teacher has access to the class"""
        class_obj = crud.get_class_by_id(db, class_id)
        if not class_obj:
            return False
        
        # Admin can access all classes in their org; super admin can access all
        teacher = crud.get_teacher_by_id(db, teacher_id)
        if teacher and teacher.role in ["admin", "super_admin"]:
            if teacher.role == "super_admin":
                return True
            return class_obj.organization_id is not None and class_obj.organization_id == teacher.organization_id
        
        # Teacher can only access their own classes
        return class_obj.teacher_id == teacher_id
