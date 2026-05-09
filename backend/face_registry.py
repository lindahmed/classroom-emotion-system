import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
KNOWN_FACES_PATH = os.path.join(BASE_DIR, 'known_faces')
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png'}

def load_known_students():
    students = []
    if not os.path.exists(KNOWN_FACES_PATH):
        return students
    for folder in os.listdir(KNOWN_FACES_PATH):
        folder_path = os.path.join(KNOWN_FACES_PATH, folder)
        if os.path.isdir(folder_path):
            parts = folder.split('_', 1)
            if len(parts) == 2:
                student_id, name = parts
                image_count = 0
                for filename in os.listdir(folder_path):
                    _, ext = os.path.splitext(filename.lower())
                    if ext in IMAGE_EXTENSIONS:
                        image_count += 1
                students.append({
                    'student_id': student_id,
                    'student_name': name,
                    'image_count': image_count,
                    'folder': folder
                })
    return students

def refresh_known_students():
    global KNOWN_STUDENTS
    KNOWN_STUDENTS = load_known_students()
    return KNOWN_STUDENTS

KNOWN_STUDENTS = load_known_students()
