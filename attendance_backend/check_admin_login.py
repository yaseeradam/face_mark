"""Diagnostic script to check admin login issue"""
import sqlite3
import bcrypt
from passlib.hash import bcrypt as passlib_bcrypt

# Connect to database
conn = sqlite3.connect('attendance.db')
cursor = conn.cursor()

# Get admin user
cursor.execute("SELECT email, password_hash FROM teachers WHERE email = 'admin@school.com'")
admin = cursor.fetchone()

if not admin:
    print("[ERROR] Admin user not found in database!")
    conn.close()
    exit(1)

email, stored_hash = admin
print(f"[INFO] Found admin user: {email}")
print(f"[INFO] Stored hash: {stored_hash[:50]}...")
print(f"[INFO] Hash length: {len(stored_hash)}")
print()

# Test password
test_password = "admin123"
print(f"[TEST] Testing password: {test_password}")
print()

# Test with bcrypt (used by login)
try:
    bcrypt_result = bcrypt.checkpw(test_password.encode('utf-8'), stored_hash.encode('utf-8'))
    print(f"[BCRYPT] Native bcrypt verification: {'✓ SUCCESS' if bcrypt_result else '✗ FAILED'}")
except Exception as e:
    print(f"[BCRYPT] Native bcrypt verification: ✗ ERROR - {e}")

# Test with passlib
try:
    passlib_result = passlib_bcrypt.verify(test_password, stored_hash)
    print(f"[PASSLIB] Passlib bcrypt verification: {'✓ SUCCESS' if passlib_result else '✗ FAILED'}")
except Exception as e:
    print(f"[PASSLIB] Passlib bcrypt verification: ✗ ERROR - {e}")

print()
print("=" * 60)
print("RECOMMENDED ACTION:")
if bcrypt_result:
    print("✓ Password verification works! The issue may be elsewhere.")
else:
    print("✗ Password hash is incompatible with the login system.")
    print("  Solution: Re-create admin using the correct hashing method.")
    print("  Run: python fix_admin_hash.py")

conn.close()
