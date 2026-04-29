from deepface import DeepFace
import random
import tempfile
import os

EMOTION_MAPPING = {
    'happy': 'Happy',
    'neutral': 'Neutral',
    'sad': 'Bored',
    'disgust': 'Bored',
    'angry': 'Confused',
    'fear': 'Confused',
    'surprise': 'Confused'
}

ENGAGEMENT_SCORES = {
    'Happy': 0.95,
    'Neutral': 0.65,
    'Confused': 0.40,
    'Bored': 0.20
}

def analyze_emotion(image_bytes):
    with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as temp_file:
        temp_file.write(image_bytes)
        temp_path = temp_file.name
    try:
        result = DeepFace.analyze(img_path=temp_path, actions=['emotion'], enforce_detection=False)
        if result:
            dominant = result[0]['dominant_emotion']
            emotion = EMOTION_MAPPING.get(dominant, 'Neutral')
            confidence = result[0]['emotion'][dominant] / 100.0
            engagement_score = ENGAGEMENT_SCORES[emotion]
            # Focus score: higher for Happy/Neutral
            if emotion in ['Happy', 'Neutral']:
                focus_score = random.uniform(0.7, 1.0)
            else:
                focus_score = random.uniform(0.2, 0.6)
            return {
                'emotion': emotion,
                'confidence': confidence,
                'engagement_score': engagement_score,
                'focus_score': focus_score
            }
        return {
            'emotion': 'Neutral',
            'confidence': 0.5,
            'engagement_score': 0.65,
            'focus_score': 0.5
        }
    except Exception as e:
        print(f'Error in emotion analysis: {e}')
        return {
            'emotion': 'Neutral',
            'confidence': 0.5,
            'engagement_score': 0.65,
            'focus_score': 0.5
        }
    finally:
        os.unlink(temp_path)
