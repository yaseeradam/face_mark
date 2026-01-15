"""Add attendance settings table and attendance columns"""
import sqlite3
import os

db_path = os.path.join(os.path.dirname(__file__), 'attendance.db')

def migrate():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        cursor.execute("PRAGMA table_info(attendance)")
        columns = [column[1] for column in cursor.fetchall()]

        if 'status' not in columns:
            cursor.execute("ALTER TABLE attendance ADD COLUMN status TEXT DEFAULT 'present'")
        if 'check_in_type' not in columns:
            cursor.execute("ALTER TABLE attendance ADD COLUMN check_in_type TEXT DEFAULT 'morning'")

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='attendance_settings'")
        has_settings_table = cursor.fetchone() is not None

        if not has_settings_table:
            cursor.execute("""
                CREATE TABLE attendance_settings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    organization_id INTEGER NOT NULL UNIQUE,
                    school_start_time TEXT DEFAULT '08:00',
                    late_cutoff_time TEXT DEFAULT '08:15',
                    auto_absent_time TEXT DEFAULT '09:00',
                    allow_late_arrivals BOOLEAN DEFAULT 1,
                    require_absence_excuse BOOLEAN DEFAULT 0,
                    multiple_checkins BOOLEAN DEFAULT 0,
                    created_at TEXT,
                    updated_at TEXT,
                    FOREIGN KEY (organization_id) REFERENCES organizations (id)
                )
            """)

        conn.commit()
        print("Migration completed successfully.")
    except Exception as e:
        print(f"Migration failed: {e}")
        conn.rollback()
    finally:
        conn.close()

if __name__ == "__main__":
    migrate()
