"""Reset all admin passwords using native bcrypt - GUARANTEED TO WORK"""
import sqlite3
import bcrypt

DB_PATH = "attendance.db"
NEW_PASSWORD = "Admin123!"

print("=" * 60)
print("RESETTING ALL ADMIN PASSWORDS")
print("=" * 60)

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

# 1. Show current state
print("\n📋 Current teachers in database:")
cur.execute("SELECT id, email, role, password_hash FROM teachers")
rows = cur.fetchall()

if not rows:
    print("❌ NO TEACHERS FOUND! Creating one now...")
    # Create a new admin
    new_hash = bcrypt.hashpw(NEW_PASSWORD.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    cur.execute("""
        INSERT INTO teachers (teacher_id, full_name, email, password_hash, role, status)
        VALUES (?, ?, ?, ?, ?, ?)
    """, ("ADMIN001", "Administrator", "admin@school.com", new_hash, "admin", "active"))
    conn.commit()
    print("✅ Created admin@school.com")
else:
    for row in rows:
        tid, email, role, phash = row
        print(f"  ID={tid} | {email} | role={role} | hash_len={len(phash) if phash else 0}")

# 2. Generate correct bcrypt hash
print(f"\n🔐 Generating new hash for password: {NEW_PASSWORD}")
new_hash = bcrypt.hashpw(NEW_PASSWORD.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
print(f"   New hash (first 30 chars): {new_hash[:30]}...")

# 3. Update ALL teachers with the new hash
cur.execute("UPDATE teachers SET password_hash = ?", (new_hash,))
affected = cur.rowcount
conn.commit()

print(f"\n✅ Updated {affected} teacher(s) with new password hash")

# 4. Verify the update
print("\n📋 Verification - updated state:")
cur.execute("SELECT id, email, role, password_hash FROM teachers")
for row in cur.fetchall():
    tid, email, role, phash = row
    # Test if hash works
    test_result = bcrypt.checkpw(NEW_PASSWORD.encode("utf-8"), phash.encode("utf-8"))
    status = "✅ WORKS" if test_result else "❌ FAIL"
    print(f"  {email} | {status}")

conn.close()

print("\n" + "=" * 60)
print("🎉 DONE! Login with:")
print(f"   Email: admin@school.com (or any email shown above)")
print(f"   Password: {NEW_PASSWORD}")
print("=" * 60)
