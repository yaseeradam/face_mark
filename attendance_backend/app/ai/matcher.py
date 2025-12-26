"""Compare face embeddings"""
import numpy as np
from typing import Tuple, List
from ..core.config import settings

def cosine_similarity(embedding1: np.ndarray, embedding2: np.ndarray) -> float:
    """Calculate cosine similarity between two embeddings"""
    # Normalize the embeddings
    norm1 = np.linalg.norm(embedding1)
    norm2 = np.linalg.norm(embedding2)
    
    if norm1 == 0 or norm2 == 0:
        return 0.0
    
    # Calculate cosine similarity
    similarity = np.dot(embedding1, embedding2) / (norm1 * norm2)
    return float(similarity)

def match_faces(embedding1: np.ndarray, embedding2: np.ndarray, threshold: float = None) -> Tuple[bool, float]:
    """Check if two embeddings match based on similarity threshold
    
    Args:
        embedding1: First face embedding
        embedding2: Second face embedding
        threshold: Similarity threshold (uses config default if None)
    
    Returns:
        Tuple[is_match, similarity_score]
    """
    if threshold is None:
        threshold = settings.face_similarity_threshold
    
    similarity = cosine_similarity(embedding1, embedding2)
    is_match = similarity >= threshold
    
    return is_match, similarity

def find_best_match(target_embedding: np.ndarray, candidate_embeddings: List[Tuple[int, np.ndarray]], threshold: float = None) -> Tuple[int, float, bool]:
    """Find the best matching embedding from a list of candidates
    
    Args:
        target_embedding: The embedding to match against
        candidate_embeddings: List of (student_id, embedding) tuples
        threshold: Similarity threshold
    
    Returns:
        Tuple[best_student_id, best_similarity, is_match]
    """
    if not candidate_embeddings:
        print("⚠️ No candidate embeddings provided")
        return None, 0.0, False
    
    if threshold is None:
        threshold = settings.face_similarity_threshold
    
    print(f"🔍 Matching against {len(candidate_embeddings)} candidates with threshold {threshold}")
    
    best_student_id = None
    best_similarity = 0.0
    
    for student_id, candidate_embedding in candidate_embeddings:
        similarity = cosine_similarity(target_embedding, candidate_embedding)
        print(f"  Student {student_id}: similarity = {similarity:.4f}")
        if similarity > best_similarity:
            best_similarity = similarity
            best_student_id = student_id
    
    is_match = best_similarity >= threshold
    print(f"{'✅' if is_match else '❌'} Best match: Student {best_student_id} with {best_similarity:.4f} (threshold: {threshold})")
    
    return best_student_id, best_similarity, is_match