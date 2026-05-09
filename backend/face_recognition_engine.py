from deepface import DeepFace
from .face_registry import KNOWN_FACES_PATH
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def recognize_face(image_bytes):
    temp_path = None
    with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as temp_file:
        temp_file.write(image_bytes)
        temp_path = temp_file.name
    try:
        result = DeepFace.find(img_path=temp_path, db_path=KNOWN_FACES_PATH, enforce_detection=False)
        if result and len(result[0]) > 0:
            identity = result[0]['identity'][0]
            folder = os.path.basename(os.path.dirname(identity))
            parts = folder.split('_', 1)
            if len(parts) == 2:
                student_id, name = parts
                return {'student_id': student_id, 'student_name': name, 'recognized': True}
        return {'student_id': 'Unknown', 'student_name': '', 'recognized': False}
    except Exception as e:
        logger.exception("Error in recognition: %s", e)
        return {'student_id': 'Unknown', 'student_name': '', 'recognized': False}
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass
