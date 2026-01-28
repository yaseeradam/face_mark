import sqlite3
import os
from datetime import date

db_path = os.path.join('attendance_backend', 'attendance.db')
if not os.path.exists(db_path):
    # Try different location if not found
    db_path = 'attendance.db'

print(f"Checking DB: {db_path}")
conn = sqlite3.connect(db_path)
cur = conn.cursor()

try:
    students_count = cur.execute('SELECT COUNT(*) FROM students').fetchone()[0]
    attendance_today = cur.execute('SELECT COUNT(*) FROM attendance WHERE date(marked_at) = date("now")').fetchone()[0]
    
    print(f"Total Students: {students_count}")
    print(f"Attendance Today: {attendance_today}")
    
    if students_count > 0:
        rate = (attendance_today / students_count) * 100
        print(f"Calculated Rate: {rate}%")
    else:
        print("Calculated Rate: 0% (No students)")
except Exception as e:
    print(f"Error: {e}")
finally:
    conn.close()
