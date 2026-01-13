"""Fix admin password hash to be compatible with login system"""
import sqlite3
import bcrypt

# Connect to database
conn = sqlite3.connect('attendance.db')
cursor = conn.cursor()

# Admin credentials
admin_email = "admin@school.com"
admin_password = "admin123"

# Generate hash using bcrypt (same as security.py)
password_hash = bcrypt.hashpw(admin_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

# Update the admin user's password hash
cursor.execute("""
    UPDATE teachers 
    SET password_hash = ? 
    WHERE email = ?
""", (password_hash, admin_email))

affected_rows = cursor.rowcount
conn.commit()

if affected_rows > 0:
    print("=" * 60)
    print("✓ SUCCESS! Admin password hash has been fixed!")
    print("=" * 60)
    print()
    print("You can now login with:")
    print(f"  Email: {admin_email}")
    print(f"  Password: {admin_password}")
    print()
    print("⚠️  IMPORTANT: Change this password after your first login!")
else:
    print("[ERROR] Admin user not found. Please create admin first.")
    print("Run: python create_admin_working.py")

conn.close()
