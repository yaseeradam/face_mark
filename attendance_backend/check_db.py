from sqlalchemy import create_engine, text

engine = create_engine('sqlite:///attendance.db')
conn = engine.connect()

# Check embeddings count
result = conn.execute(text('SELECT COUNT(*) FROM face_embeddings'))
print(f'Face embeddings count: {result.scalar()}')

# Check sample embeddings
result = conn.execute(text('SELECT student_id, LENGTH(embedding) FROM face_embeddings LIMIT 3'))
print('Sample embeddings:')
for row in result:
    print(f'  Student {row[0]}: embedding length = {row[1]} chars')

# Check students with face_enrolled
result = conn.execute(text('SELECT id, student_id, full_name, face_enrolled FROM students'))
print('\nStudents:')
for row in result:
    print(f'  ID {row[0]}: {row[1]} - {row[2]} (enrolled: {row[3]})')

conn.close()
