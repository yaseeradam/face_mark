"""Teacher Face ID business logic using embeddings"""
from typing import Tuple, Optional
from sqlalchemy.orm import Session
from ..ai.embedding import generate_embedding, embedding_from_json
from ..ai.matcher import find_best_match
from ..db import crud
from ..utils.image_utils import preprocess_image, validate_image_format, resize_image_if_needed

class TeacherFaceService:
    def __init__(self):
        pass

    async def register_face_id(self, image_data: bytes, teacher_id: int, db: Session) -> Tuple[bool, str]:
        """Register a face embedding for a teacher (no image storage)."""
        try:
            teacher = crud.get_teacher_by_id(db, teacher_id)
            if not teacher:
                return False, "Teacher not found"

            is_valid, message = validate_image_format(image_data)
            if not is_valid:
                return False, message

            image = preprocess_image(image_data)
            if image is None:
                return False, "Failed to process image"

            image = resize_image_if_needed(image)
            embedding_json, embed_message = generate_embedding(image)
            if embedding_json is None:
                return False, embed_message

            target_embedding = embedding_from_json(embedding_json)
            all_embeddings = crud.get_all_teacher_face_embeddings(db)

            candidates = []
            for face_embed in all_embeddings:
                if face_embed.teacher_id == teacher_id:
                    continue
                candidate_embedding = embedding_from_json(face_embed.embedding)
                candidates.append((face_embed.teacher_id, candidate_embedding))

            if candidates:
                best_id, best_sim, is_match = find_best_match(target_embedding, candidates)
                if is_match:
                    existing_teacher = crud.get_teacher_by_id(db, best_id)
                    existing_name = existing_teacher.full_name if existing_teacher else "Unknown"
                    return False, f"Face already registered for teacher: {existing_name} (Similarity: {best_sim:.2f})"

            crud.create_teacher_face_embedding(db, teacher_id, embedding_json)
            return True, "Face ID registered successfully"
        except Exception as e:
            return False, f"Error registering Face ID: {str(e)}"

    async def verify_face_id(self, image_data: bytes, db: Session) -> Tuple[bool, str, Optional[int], Optional[float], Optional[float]]:
        """Verify a face against enrolled teacher embeddings."""
        try:
            from ..core.config import settings
            threshold = settings.face_similarity_threshold

            is_valid, message = validate_image_format(image_data)
            if not is_valid:
                return False, message, None, None, threshold

            image = preprocess_image(image_data)
            if image is None:
                return False, "Failed to process image", None, None, threshold

            image = resize_image_if_needed(image)
            embedding_json, embed_message = generate_embedding(image)
            if embedding_json is None:
                return False, embed_message, None, None, threshold

            target_embedding = embedding_from_json(embedding_json)
            face_embeddings = crud.get_all_teacher_face_embeddings(db)
            if not face_embeddings:
                return False, "No Face ID registered", None, None, threshold

            candidates = []
            for face_embed in face_embeddings:
                candidate_embedding = embedding_from_json(face_embed.embedding)
                candidates.append((face_embed.teacher_id, candidate_embedding))

            best_teacher_id, best_similarity, is_match = find_best_match(target_embedding, candidates)
            if is_match:
                teacher = crud.get_teacher_by_id(db, best_teacher_id)
                name = teacher.full_name if teacher else "Unknown"
                return True, f"Face recognized: {name}", best_teacher_id, best_similarity, threshold

            return False, f"Face not recognized (confidence: {best_similarity:.2%}, required: {threshold:.2%})", None, best_similarity, threshold
        except Exception as e:
            return False, f"Error verifying Face ID: {str(e)}", None, None, None
