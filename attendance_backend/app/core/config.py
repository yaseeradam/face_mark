"""App settings and configuration"""
from typing import Optional
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Database
    database_url: str = "sqlite:///./attendance.db"
    
    # Security
    secret_key: str = "your-super-secret-key-change-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    
    # Face Recognition
    face_similarity_threshold: float = 0.6
    insightface_model_name: str = "buffalo_l"
    
    # App
    app_name: str = "Face Recognition Attendance System"
    debug: bool = False
    dev_mode: bool = False
    
    # Cloudinary (optional)
    cloudinary_url: Optional[str] = None
    
    class Config:
        env_file = ".env"

settings = Settings()
