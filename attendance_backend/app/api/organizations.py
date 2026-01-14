"""Organization management endpoints"""
from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.orm import Session
from ..core.security import require_super_admin
from ..db.base import get_db
from ..db import crud
from ..schemas.organization import OrganizationCreate, OrganizationResponse, OrganizationUpdate

router = APIRouter(prefix="/organizations", tags=["organizations"])

@router.post("/", response_model=OrganizationResponse)
async def create_organization(
    org_data: OrganizationCreate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_super_admin)
):
    """Create a new organization and its admin account (Super Admin only)"""
    existing = crud.get_organization_by_code(db, org_data.code)
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Organization code already exists")

    existing_teacher = crud.get_teacher_by_email(db, org_data.admin_email)
    if existing_teacher:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Admin email already exists")

    organization = crud.create_organization(db, {
        "name": org_data.name,
        "code": org_data.code,
        "status": org_data.status
    })

    crud.create_teacher(db, {
        "teacher_id": org_data.admin_teacher_id,
        "full_name": org_data.admin_full_name,
        "email": org_data.admin_email,
        "password": org_data.admin_password,
        "role": "admin",
        "status": "active",
        "organization_id": organization.id
    })

    return OrganizationResponse.model_validate(organization)

@router.get("/", response_model=list[OrganizationResponse])
async def get_organizations(
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_super_admin)
):
    """Get all organizations (Super Admin only)"""
    orgs = crud.get_organizations(db)
    return [OrganizationResponse.model_validate(org) for org in orgs]

@router.get("/{org_id}", response_model=OrganizationResponse)
async def get_organization(
    org_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_super_admin)
):
    """Get organization by ID (Super Admin only)"""
    org = crud.get_organization_by_id(db, org_id)
    if not org:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Organization not found")
    return OrganizationResponse.model_validate(org)

@router.put("/{org_id}", response_model=OrganizationResponse)
async def update_organization(
    org_id: int,
    org_data: OrganizationUpdate,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_super_admin)
):
    """Update organization (Super Admin only)"""
    update_dict = org_data.model_dump(exclude_unset=True)
    if "code" in update_dict:
        existing = crud.get_organization_by_code(db, update_dict["code"])
        if existing and existing.id != org_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Organization code already exists")

    org = crud.update_organization(db, org_id, update_dict)
    if not org:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Organization not found")
    return OrganizationResponse.model_validate(org)

@router.delete("/{org_id}")
async def delete_organization(
    org_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(require_super_admin)
):
    """Delete organization (Super Admin only)"""
    success = crud.delete_organization(db, org_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Organization not found")
    return {"success": True}

