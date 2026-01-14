"""Create a super admin user with bcrypt hashing"""
import sqlite3
import bcrypt

conn = sqlite3.connect("attendance.db")
cursor = conn.cursor()

super_email = "superadmin@frontalminds.com"
super_password = "SuperAdmin123!"
super_teacher_id = "SUPER001"
super_name = "Super Administrator"

cursor.execute("SELECT email FROM teachers WHERE email = ?", (super_email,))
if cursor.fetchone():
    print("Super admin already exists.")
    print(f"Email: {super_email}")
    print(f"Password: {super_password}")
    conn.close()
    raise SystemExit(0)

password_hash = bcrypt.hashpw(super_password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

cursor.execute(
    """
    INSERT INTO teachers (teacher_id, full_name, email, password_hash, role, status)
    VALUES (?, ?, ?, ?, ?, ?)
    """,
    (super_teacher_id, super_name, super_email, password_hash, "super_admin", "active"),
)

conn.commit()
print("SUCCESS! Super admin user created!")
print("Email:", super_email)
print("Password:", super_password)
conn.close()
