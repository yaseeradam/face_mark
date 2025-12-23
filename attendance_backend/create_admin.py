#!/usr/bin/env python3
"""Create admin user"""
import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.db.base import SessionLocal
from app.services.teacher_service import TeacherService
from app.schemas.teacher import TeacherCreate
import asyncio

async def create_admin():
    db = SessionLocal()
    try:
        teacher_service = TeacherService()
        admin_data = TeacherCreate(
            teacher_id="admin001",
            full_name="System Administrator", 
            email="admin@school.com",
            password="admin",
            role="admin"
        )
        
        result = await teacher_service.create_teacher(admin_data, db)
        if result:
            print("✅ Admin user created successfully!")
            print(f"Email: {admin_data['email']}")
            print(f"Password: {admin_data['password']}")
        else:
            print("❌ Failed to create admin user")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    asyncio.run(create_admin())