"""Add teacher face embeddings table"""
import sqlite3
import os

# Get the database path
db_path = os.path.join(os.path.dirname(__file__), 'attendance.db')

def migrate():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='teacher_face_embeddings'")
        exists = cursor.fetchone() is not None

        if not exists:
            cursor.execute("""
                CREATE TABLE teacher_face_embeddings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    teacher_id INTEGER NOT NULL UNIQUE,
                    embedding TEXT NOT NULL,
                    created_at TEXT,
                    updated_at TEXT,
                    FOREIGN KEY (teacher_id) REFERENCES teachers (id)
                )
            """)
            conn.commit()
            print("Migration completed successfully.")
        else:
            print("teacher_face_embeddings already exists. No migration needed.")
    except Exception as e:
        print(f"Migration failed: {e}")
        conn.rollback()
    finally:
        conn.close()

if __name__ == "__main__":
    migrate()
