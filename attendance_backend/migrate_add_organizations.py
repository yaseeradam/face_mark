"""Add organizations table and org_id columns"""
import sqlite3
import os

db_path = os.path.join(os.path.dirname(__file__), "attendance.db")

def migrate():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    try:
        # Create organizations table if missing
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS organizations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL,
                code TEXT UNIQUE NOT NULL,
                status TEXT DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Add organization_id to teachers
        cursor.execute("PRAGMA table_info(teachers)")
        teacher_columns = [column[1] for column in cursor.fetchall()]
        if "organization_id" not in teacher_columns:
            cursor.execute("ALTER TABLE teachers ADD COLUMN organization_id INTEGER")

        # Add organization_id to classes
        cursor.execute("PRAGMA table_info(classes)")
        class_columns = [column[1] for column in cursor.fetchall()]
        if "organization_id" not in class_columns:
            cursor.execute("ALTER TABLE classes ADD COLUMN organization_id INTEGER")

        conn.commit()
        print("Migration completed successfully.")
    except Exception as e:
        conn.rollback()
        print(f"Migration failed: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    migrate()
