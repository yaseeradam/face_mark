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
            
            # Check if face is already registered
            target_embedding = embedding_from_json(embedding_json)
            all_embeddings = crud.get_all_face_embeddings(db)
            
            candidates = []
            for face_embed in all_embeddings:
                # Skip checking against the student's own previous embedding if it exists (re-enrollment)
                if face_embed.student_id == student_id:
                    continue
                candidate_embedding = embedding_from_json(face_embed.embedding)
                candidates.append((face_embed.student_id, candidate_embedding))
            
            if candidates:
                best_id, best_sim, is_match = find_best_match(target_embedding, candidates)
                if is_match:
                    existing_student = crud.get_student_by_id(db, best_id)
                    return False, f"Face already registered for student: {existing_student.full_name} (Similarity: {best_sim:.2f})"
            
            # Save embedding to database
            crud.create_face_embedding(db, student_id, embedding_json)
            
            # Update student face_enrolled status and photo_path
            crud.update_student_face_enrolled(db, student_id, True, photo_path=f"students/{photo_filename}")
            
            return True, "Face registered successfully"
            
        except Exception as e:
            return False, f"Error registering face: {str(e)}"
    
    async def verify_face(self, image_data: bytes, db: Session, class_id: Optional[int] = None) -> Tuple[bool, str, Optional[int], Optional[float], Optional[float]]:
        """Verify a face against enrolled students, optionally filtered by class
        
        Args:
            image_data: Raw image bytes
            db: Database session
            class_id: Optional Class ID to search within
            
        Returns:
            Tuple[success, message, student_id, confidence_score, threshold]
        """
        try:
            from ..core.config import settings
            threshold = settings.face_similarity_threshold
            
            print(f"\n{'='*60}")
            print(f"🔍 FACE VERIFICATION STARTED {'for class ' + str(class_id) if class_id else 'GLOBAL SEARCH'}")
            print(f"{'='*60}")
            
            # Validate image format
            is_valid, message = validate_image_format(image_data)
            if not is_valid:
                print(f"❌ Image validation failed: {message}")
                return False, message, None, None, threshold
            
            # Preprocess image
            image = preprocess_image(image_data)
            if image is None:
                print("❌ Image preprocessing failed")
                return False, "Failed to process image", None, None, threshold
            
            # Resize if needed
            image = resize_image_if_needed(image)
            
            # Generate embedding for input image
            print("📊 Generating embedding for captured face...")
            embedding_json, embed_message = generate_embedding(image)
            if embedding_json is None:
                print(f"❌ Embedding generation failed: {embed_message}")
                return False, embed_message, None, None, threshold
            
            print(f"✅ Embedding generated successfully (length: {len(embedding_json)} chars)")
            target_embedding = embedding_from_json(embedding_json)
            
            # Get face embeddings
            if class_id:
                print(f"📚 Fetching enrolled faces for class {class_id}...")
                face_embeddings = crud.get_all_face_embeddings_by_class(db, class_id)
            else:
                print(f"📚 Fetching ALL enrolled faces...")
                face_embeddings = crud.get_all_face_embeddings(db)
            
            if not face_embeddings:
                print(f"⚠️ No enrolled faces found")
                return False, "No enrolled faces found", None, None, threshold
            
            print(f"✅ Found {len(face_embeddings)} enrolled face(s)")
            
            # Prepare candidate embeddings
            candidates = []
            for face_embed in face_embeddings:
                candidate_embedding = embedding_from_json(face_embed.embedding)
                candidates.append((face_embed.student_id, candidate_embedding))
            
            # Find best match
            print("\n🎯 Starting face matching...")
            best_student_id, best_similarity, is_match = find_best_match(target_embedding, candidates)
            
            if is_match:
                student = crud.get_student_by_id(db, best_student_id)
                print(f"\n✅ MATCH FOUND: {student.full_name} (ID: {best_student_id})")
                print(f"{'='*60}\n")
                return True, f"Face recognized: {student.full_name}", best_student_id, best_similarity, threshold
            else:
                print(f"\n❌ NO MATCH: Best similarity {best_similarity:.4f} below threshold {threshold}")
                print(f"{'='*60}\n")
                return False, f"Face not recognized (confidence: {best_similarity:.2%}, required: {threshold:.2%})", None, best_similarity, threshold
                
        except Exception as e:
            print(f"\n❌ ERROR in verify_face: {str(e)}")
            print(f"{'='*60}\n")
            return False, f"Error verifying face: {str(e)}", None, None, None