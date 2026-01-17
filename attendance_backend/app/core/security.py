"""Authentication and security utilities"""
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
import bcrypt
from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from .config import settings

# ==================================================
# 🔧 DEV MODE - Set to True to bypass authentication
# ==================================================
DEV_MODE = settings.dev_mode

security = HTTPBearer(auto_error=not DEV_MODE)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against a hash using bcrypt directly"""
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

def get_password_hash(password: str) -> str:
    """Hash a password using bcrypt directly"""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.access_token_expire_minutes)
    
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)
    return encoded_jwt

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    # 🔧 DEV MODE: Skip authentication
    if DEV_MODE:
        return {"user_id": 1, "role": "super_admin"}
    
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    
    try:
        payload = jwt.decode(credentials.credentials, settings.secret_key, algorithms=[settings.algorithm])
        user_id: str = payload.get("sub")
        role: str = payload.get("role")
        if user_id is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        return {"user_id": int(user_id), "role": role}
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

def require_admin(current_user: dict = Depends(verify_token)):
    # 🔧 DEV MODE: Always return admin
    if DEV_MODE:
        return {"user_id": 1, "role": "super_admin"}
    
    if current_user["role"] not in ["admin", "super_admin"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return current_user

def require_teacher(current_user: dict = Depends(verify_token)):
    # 🔧 DEV MODE: Always return admin (has teacher permissions)
    if DEV_MODE:
        return {"user_id": 1, "role": "super_admin"}
    
    if current_user["role"] not in ["admin", "teacher", "super_admin"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Teacher access required")
    return current_user

def require_admin_or_super_admin(current_user: dict = Depends(verify_token)):
    if DEV_MODE:
        return {"user_id": 1, "role": "super_admin"}

    if current_user["role"] not in ["admin", "super_admin"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return current_user

def require_super_admin(current_user: dict = Depends(verify_token)):
    if DEV_MODE:
        return {"user_id": 1, "role": "super_admin"}

    if current_user["role"] != "super_admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Super admin access required")
    return current_user
