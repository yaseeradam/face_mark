"""Create a new admin user with correct bcrypt hashing"""
import sqlite3
import bcrypt

# Connect to database
conn = sqlite3.connect('attendance.db')
cursor = conn.cursor()

# New admin credentials
admin_email = "admin2@school.com"
admin_password = "Admin123!"
admin_teacher_id = "ADMIN002"
admin_name = "Administrator"

# Check if this email already exists
cursor.execute("SELECT email FROM teachers WHERE email = ?", (admin_email,))
if cursor.fetchone():
    print(f"⚠️  User with email {admin_email} already exists!")
    print("Login with:")
    print(f"  Email: {admin_email}")
    print(f"  Password: {admin_password}")
    conn.close()
    exit(0)

# Generate password hash using native bcrypt (same as security.py)
password_hash = bcrypt.hashpw(admin_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

# Insert new admin user
cursor.execute("""
    INSERT INTO teachers (teacher_id, full_name, email, password_hash, role, status)
    VALUES (?, ?, ?, ?, ?, ?)
""", (admin_teacher_id, admin_name, admin_email, password_hash, 'admin', 'active'))

conn.commit()

print("=" * 60)
print("✅ SUCCESS! New admin user created!")
print("=" * 60)
print()
print("Login Credentials:")
print(f"  📧 Email: {admin_email}")
print(f"  🔑 Password: {admin_password}")
print()
print("⚠️  IMPORTANT: Change this password after login!")
print("=" * 60)

conn.close()
