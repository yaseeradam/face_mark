"""Initialize database with admin user"""
import asyncio
import sys
import os

# Add the app directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.db.base import SessionLocal, engine, Base
from app.services.teacher_service import TeacherService
from app.schemas.teacher import TeacherCreate

async def init_db():
    """Initialize database with tables and admin user"""
    print("Creating database tables...")
    Base.metadata.create_all(bind=engine)
    print("Database tables created successfully!")
    
    # Create super admin user
    db = SessionLocal()
    try:
        service = TeacherService()
        
        # Check if admin already exists
        from app.db import crud
        existing_admin = crud.get_teacher_by_email(db, "admin@school.com")
        
        if existing_admin:
            print("Admin user already exists!")
            return
        
        admin_data = TeacherCreate(
            teacher_id="admin001",
            full_name="System Administrator",
            email="admin@school.com",
            password="admin123",  # Change this in production!
            role="super_admin"
        )
        
        admin_user = await service.create_teacher(admin_data, db)
        print(f"Super admin user created successfully!")
        print(f"Email: admin@school.com")
        print(f"Password: admin123")
        print("IMPORTANT: Change the admin password in production!")
        
    except Exception as e:
        print(f"Error creating admin user: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    asyncio.run(init_db())
