"""Face recognition business logic using InsightFace"""
from typing import Tuple, Optional
from sqlalchemy.orm import Session
from ..ai.embedding import generate_embedding, embedding_from_json
from ..ai.matcher import find_best_match
from ..db import crud
from ..utils.image_utils import preprocess_image, validate_image_format, resize_image_if_needed
import numpy as np
import os
import uuid

# Directory to save student photos
UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "uploads", "students")

class FaceService:
    def __init__(self):
        # Ensure upload directory exists
        os.makedirs(UPLOAD_DIR, exist_ok=True)
    
    async def register_face(self, image_data: bytes, student_id: int, db: Session) -> Tuple[bool, str]:
        """Register a face for a student
        
        Args:
            image_data: Raw image bytes
            student_id: Student ID to register face for
            db: Database session
            
        Returns:
            Tuple[success, message]
        """
        try:
            # Validate student exists
            student = crud.get_student_by_id(db, student_id)
            if not student:
                return False, "Student not found"
            
            # Validate image format
            is_valid, message = validate_image_format(image_data)
            if not is_valid:
                return False, message
            
            # Save the photo as student profile picture
            photo_filename = f"{student_id}_{uuid.uuid4().hex[:8]}.jpg"
            photo_path = os.path.join(UPLOAD_DIR, photo_filename)
            with open(photo_path, 'wb') as f:
                f.write(image_data)
            
            # Preprocess image
            image = preprocess_image(image_data)
            if image is None:
                return False, "Failed to process image"
            
            # Resize if needed
            image = resize_image_if_needed(image)
            
            # Generate embedding
            embedding_json, embed_message = generate_embedding(image)
            if embedding_json is None:
                return False, embed_message
            
            # Save embedding to database
            crud.create_face_embedding(db, student_id, embedding_json)
            
            # Update student face_enrolled status and photo_path
            crud.update_student_face_enrolled(db, student_id, True, photo_path=f"students/{photo_filename}")
            
            return True, "Face registered successfully"
            
        except Exception as e:
            return False, f"Error registering face: {str(e)}"
    
    async def verify_face(self, image_data: bytes, class_id: int, db: Session) -> Tuple[bool, str, Optional[int], Optional[float]]:
        """Verify a face against enrolled students in a class
        
        Args:
            image_data: Raw image bytes
            class_id: Class ID to search within
            db: Database session
            
        Returns:
            Tuple[success, message, student_id, confidence_score]
        """
        try:
            print(f"\n{'='*60}")
            print(f"🔍 FACE VERIFICATION STARTED for class {class_id}")
            print(f"{'='*60}")
            
            # Validate image format
            is_valid, message = validate_image_format(image_data)
            if not is_valid:
                print(f"❌ Image validation failed: {message}")
                return False, message, None, None
            
            # Preprocess image
            image = preprocess_image(image_data)
            if image is None:
                print("❌ Image preprocessing failed")
                return False, "Failed to process image", None, None
            
            # Resize if needed
            image = resize_image_if_needed(image)
            
            # Generate embedding for input image
            print("📊 Generating embedding for captured face...")
            embedding_json, embed_message = generate_embedding(image)
            if embedding_json is None:
                print(f"❌ Embedding generation failed: {embed_message}")
                return False, embed_message, None, None
            
            print(f"✅ Embedding generated successfully (length: {len(embedding_json)} chars)")
            target_embedding = embedding_from_json(embedding_json)
            
            # Get all face embeddings for students in this class
            print(f"📚 Fetching enrolled faces for class {class_id}...")
            face_embeddings = crud.get_all_face_embeddings_by_class(db, class_id)
            
            if not face_embeddings:
                print(f"⚠️ No enrolled faces found in class {class_id}")
                return False, "No enrolled faces found in this class", None, None
            
            print(f"✅ Found {len(face_embeddings)} enrolled face(s)")
            
            # Prepare candidate embeddings
            candidates = []
            for face_embed in face_embeddings:
                candidate_embedding = embedding_from_json(face_embed.embedding)
                candidates.append((face_embed.student_id, candidate_embedding))
                print(f"  - Student ID {face_embed.student_id} added to candidates")
            
            # Find best match
            print("\n🎯 Starting face matching...")
            best_student_id, best_similarity, is_match = find_best_match(target_embedding, candidates)
            
            if is_match:
                student = crud.get_student_by_id(db, best_student_id)
                print(f"\n✅ MATCH FOUND: {student.full_name} (ID: {best_student_id})")
                print(f"{'='*60}\n")
                return True, f"Face recognized: {student.full_name}", best_student_id, best_similarity
            else:
                print(f"\n❌ NO MATCH: Best similarity {best_similarity:.4f} below threshold")
                print(f"{'='*60}\n")
                return False, "Face not recognized", None, best_similarity
                
        except Exception as e:
            print(f"\n❌ ERROR in verify_face: {str(e)}")
            print(f"{'='*60}\n")
            return False, f"Error verifying face: {str(e)}", None, None