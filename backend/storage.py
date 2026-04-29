import pandas as pd
import os
from datetime import datetime

CSV_PATH = 'data/emotion_records.csv'

def append_record(record):
    df = pd.DataFrame([record])
    if not os.path.exists(CSV_PATH):
        df.to_csv(CSV_PATH, index=False)
    else:
        df.to_csv(CSV_PATH, mode='a', header=False, index=False)
