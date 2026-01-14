"""App entry point"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
import os
from .core.config import settings
from .db.base import engine, Base
from .ai.insightface_model import face_model
from .api import auth, teachers, classes, students, attendance, face, dashboard, reports, organizations

# Create database tables
Base.metadata.create_all(bind=engine)

# Create uploads directory if it doesn't exist
UPLOADS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
os.makedirs(UPLOADS_DIR, exist_ok=True)
os.makedirs(os.path.join(UPLOADS_DIR, "students"), exist_ok=True)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Load InsightFace model
    print("Loading InsightFace model...")
    face_model.load_model()
    print("InsightFace model loaded successfully")
    yield
    # Shutdown: cleanup if needed
    print("Shutting down...")

app = FastAPI(
    title=settings.app_name,
    description="Face Recognition Attendance System API",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router)
app.include_router(teachers.router)
app.include_router(classes.router)
app.include_router(students.router)
app.include_router(attendance.router)
app.include_router(face.router)
app.include_router(dashboard.router)
app.include_router(reports.router)
app.include_router(organizations.router)

# Mount static files for uploads (student photos)
app.mount("/uploads", StaticFiles(directory=UPLOADS_DIR), name="uploads")

@app.get("/")
def root():
    return {
        "message": "Face Recognition Attendance System API",
        "version": "1.0.0",
        "docs": "/docs"
    }

@app.get("/health")
def health_check():
    return {"status": "healthy"}
