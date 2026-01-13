"""Test login directly on the server - bypasses network"""
import sqlite3
import bcrypt
import os

# Find the database - try multiple locations
possible_paths = [
    "attendance.db",
    "./attendance.db",
    "/home/ubuntu/apps/attendance_backend/attendance.db",
    "../attendance.db",
    "data/attendance.db",
]

db_path = None
for path in possible_paths:
    if os.path.exists(path):
        db_path = path
        break

if not db_path:
    print("❌ Cannot find attendance.db!")
    print("Current directory:", os.getcwd())
    print("Files here:", os.listdir("."))
    exit(1)

print(f"✅ Found database: {db_path}")
print(f"   Full path: {os.path.abspath(db_path)}")

conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Test credentials
test_email = "admin@school.com"
test_password = "Admin123!"

print(f"\n🔍 Looking for user: {test_email}")
cur.execute("SELECT id, email, password_hash, role FROM teachers WHERE email = ?", (test_email,))
user = cur.fetchone()

if not user:
    print(f"❌ User '{test_email}' NOT FOUND in database!")
    print("\n📋 All users in database:")
    cur.execute("SELECT email, role FROM teachers")
    for row in cur.fetchall():
        print(f"   - {row[0]} ({row[1]})")
    conn.close()
    exit(1)

user_id, email, password_hash, role = user
print(f"✅ Found user: {email} (role: {role})")
print(f"   Hash length: {len(password_hash)}")
print(f"   Hash starts with: {password_hash[:20]}...")

# Test password verification
print(f"\n🔑 Testing password: {test_password}")
try:
    result = bcrypt.checkpw(test_password.encode('utf-8'), password_hash.encode('utf-8'))
    if result:
        print("✅ PASSWORD CORRECT! Login should work!")
    else:
        print("❌ PASSWORD MISMATCH!")
        print("   The hash in the database doesn't match the password.")
        print("\n🔧 Fixing now...")
        new_hash = bcrypt.hashpw(test_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        cur.execute("UPDATE teachers SET password_hash = ? WHERE email = ?", (new_hash, test_email))
        conn.commit()
        print("✅ Password hash updated!")
        print(f"   New hash: {new_hash[:30]}...")
except Exception as e:
    print(f"❌ Error verifying password: {e}")
    print("   The hash format may be corrupted.")
    print("\n🔧 Fixing now...")
    new_hash = bcrypt.hashpw(test_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    cur.execute("UPDATE teachers SET password_hash = ? WHERE email = ?", (new_hash, test_email))
    conn.commit()
    print("✅ Password hash updated!")

conn.close()

print("\n" + "=" * 50)
print("Now try logging in with:")
print(f"  Email: {test_email}")
print(f"  Password: {test_password}")
print("=" * 50)
