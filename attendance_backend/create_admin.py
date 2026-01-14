import sqlite3
import bcrypt

# Connect to database
conn = sqlite3.connect('attendance.db')
cursor = conn.cursor()

# Check if admin already exists
cursor.execute("SELECT * FROM teachers WHERE email = 'admin@school.com'")
existing_admin = cursor.fetchone()

if existing_admin:
    print('Admin user already exists!')
    print('Email: admin@school.com')
    print('Password: admin123')
    print('\nYou can login with these credentials.')
else:
    # Create admin user
    password_hash = bcrypt.hashpw('admin123'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    
    cursor.execute("""
        INSERT INTO teachers (teacher_id, full_name, email, password_hash, role, status)
        VALUES (?, ?, ?, ?, ?, ?)
    """, ('admin001', 'System Administrator', 'admin@school.com', password_hash, 'admin', 'active'))
    
    conn.commit()
    print('SUCCESS! Admin user created!')
    print('\n=== LOGIN CREDENTIALS ===')
    print('Email: admin@school.com')
    print('Password: admin123')
    print('=========================')
    print('\nYou can now login to the app and access User Management.')

conn.close()
