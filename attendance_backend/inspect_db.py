"""Quick check to see what's in the database"""
import sqlite3

# Connect to database  
conn = sqlite3.connect('attendance.db')
cursor = conn.cursor()

# Get all teachers
cursor.execute("SELECT id, teacher_id, full_name, email, role, password_hash FROM teachers")
teachers = cursor.fetchall()

print("=" * 80)
print("TEACHERS IN DATABASE:")
print("=" * 80)

if not teachers:
    print("❌ NO TEACHERS FOUND!")
else:
    for teacher in teachers:
        tid, teacher_id, name, email, role, hash_preview = teacher
        print(f"\nID: {tid}")
        print(f"Teacher ID: {teacher_id}")
        print(f"Name: {name}")
        print(f"Email: {email}")
        print(f"Role: {role}")
        print(f"Password Hash (first 30 chars): {hash_preview[:30]}...")
        print(f"Hash Length: {len(hash_preview)}")

conn.close()

print("\n" + "=" * 80)
print(f"Total teachers: {len(teachers)}")
print("=" * 80)
