from deepface import DeepFace
from .face_registry import KNOWN_FACES_PATH
import tempfile
import os

def recognize_face(image_bytes):
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
        print(f'Error in recognition: {e}')
        return {'student_id': 'Unknown', 'student_name': '', 'recognized': False}
    finally:
        os.unlink(temp_path)
