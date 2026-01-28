import os
import sys
from datetime import date, datetime

# Add the backend app to path so we can import models and crud
sys.path.append(os.path.join(os.getcwd(), 'attendance_backend'))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db.base import Base
from app.db import models, crud

SQLALCHEMY_DATABASE_URL = "sqlite:///attendance_backend/attendance.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def test_dashboard_logic():
    db = SessionLocal()
    try:
        print("Cleaning up any previous test data...")
        # Clean up
        db.query(models.Attendance).delete()
        db.query(models.Student).delete()
        db.query(models.Class).delete()
        db.query(models.Organization).delete()
        db.commit()

        print("Creating mock data...")
        # 1. Create Organization
        org = models.Organization(name="Test School", code="TS001")
        db.add(org)
        db.commit()
        db.refresh(org)

        # 2. Get the super_admin teacher (id=1 already exists based on my check)
        teacher = db.query(models.Teacher).filter(models.Teacher.role == "super_admin").first()
        if not teacher:
            print("No super_admin teacher found. Please run the create_admin script first.")
            return
        
        teacher.organization_id = org.id
        db.commit()

        # 3. Create a Class
        cls = models.Class(class_name="Grade 10-A", class_code="G10A", teacher_id=teacher.id, organization_id=org.id)
        db.add(cls)
        db.commit()
        db.refresh(cls)

        # 4. Create Students
        s1 = models.Student(student_id="S001", full_name="John Doe", class_id=cls.id, face_enrolled=True)
        s2 = models.Student(student_id="S002", full_name="Jane Smith", class_id=cls.id, face_enrolled=False)
        db.add_all([s1, s2])
        db.commit()
        db.refresh(s1)
        db.refresh(s2)

        # 5. Mark Attendance for John Doe (Present)
        att = models.Attendance(student_id=s1.id, class_id=cls.id, status="present", marked_at=datetime.now())
        db.add(att)
        db.commit()

        print("\n--- Verification ---")
        # Now simulate dashboard logic
        students = db.query(models.Student).all()
        total_students = len(students)
        today_attendance = db.query(models.Attendance).filter(crud.func.date(models.Attendance.marked_at) == date.today()).all()
        present_today = len([r for r in today_attendance if r.status in ["present", "late"]])
        attendance_rate = (present_today / total_students * 100) if total_students > 0 else 0

        print(f"Total Students: {total_students} (Expected: 2)")
        print(f"Present Today: {present_today} (Expected: 1)")
        print(f"Attendance Rate: {attendance_rate}% (Expected: 50.0%)")

        if attendance_rate == 50.0:
            print("\nDashboard Logic Test: PASSED ✅")
        else:
            print(f"\nDashboard Logic Test: FAILED ❌ (Got {attendance_rate}%)")

    except Exception as e:
        print(f"Error: {e}")
    finally:
        # We leave the data there for the user to see in their UI if they want, 
        # or we could clean it up. Let's keep it for a moment so they can verify.
        db.close()

if __name__ == "__main__":
    test_dashboard_logic()
