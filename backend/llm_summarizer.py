"""
HuggingFace LLM integration for summarizing lecture emotion & attendance reports.
"""
import os
import logging
from typing import Any, Optional
import pandas as pd
from transformers import pipeline

logger = logging.getLogger(__name__)

# Initialize HuggingFace pipeline (cached after first use)
_summarizer = None


def _input_token_length(summarizer: Any, text: str) -> int:
    tok = getattr(summarizer, "tokenizer", None)
    if tok is None:
        return max(len(text.strip()) // 4, 1)
    max_in = getattr(tok, "model_max_length", 1024) or 1024
    # Avoid absurd sentinel values some tokenizers expose
    if max_in > 10_000:
        max_in = 1024
    ids = tok.encode(text, truncation=True, max_length=max(max_in - 2, 16))
    return len(ids)


def _safe_generation_lengths(n_input_tokens: int, max_length: int, min_length: int) -> tuple[int, int]:
    """
    BART summarization crashes (e.g. 'index out of range in self') when min_length is
    unrealistically large relative to encoded input length.
    HF max_length/min_length are in *summary tokens*, not characters.
    """
    req_max = int(max(max_length, 8))
    req_min = int(max(min_length, 4))

    if req_min >= req_max:
        req_min = max(4, req_max // 2)

    cap_max = max(24, min(256, req_max))
    cap_max = min(cap_max, max(req_min + 2, max(24, min(n_input_tokens, 1024) // 2 + 16)))

    out_max = max(req_min + 1, cap_max)

    slack = max(8, n_input_tokens // 4 + 8)
    out_min = max(5, min(req_min, slack, out_max - 1))

    if out_min >= out_max:
        out_min = max(4, out_max // 3)

    return out_max, out_min


def _pipeline_summarize(
    summarizer: Any,
    text: str,
    max_length: int,
    min_length: int,
) -> str:
    text = (text or "").strip()
    if not text:
        return "No content to summarize."

    n_in = _input_token_length(summarizer, text)
    # Too little signal for abstractive summarization — avoids decoder edge cases.
    if n_in < 18:
        return text[:900] + ("…" if len(text) > 900 else "")

    out_max, out_min = _safe_generation_lengths(n_in, max_length, min_length)

    outputs = summarizer(
        text,
        max_length=out_max,
        min_length=out_min,
        do_sample=False,
        truncation=True,
    )

    if not outputs:
        return text[:900] + ("…" if len(text) > 900 else "")

    txt = outputs[0].get("summary_text") or ""
    return txt.strip() or text[:900]


def get_summarizer(model_name: str = "facebook/bart-large-cnn"):
    """Lazy-load the summarization pipeline."""
    global _summarizer
    if _summarizer is None:
        logger.info(f"Loading HuggingFace model: {model_name}")
        _summarizer = pipeline("summarization", model=model_name)
    return _summarizer


def generate_lecture_summary(
    lecture_id: str,
    csv_data: pd.DataFrame,
    max_length: int = 150,
    min_length: int = 50,
    model_name: str = "facebook/bart-large-cnn"
) -> dict:
    """
    Generate a summary of a lecture's emotion & attendance data using HuggingFace LLM.
    
    Args:
        lecture_id: The lecture identifier
        csv_data: DataFrame containing emotion/attendance records
        max_length: Max summary length (words)
        min_length: Min summary length (words)
        model_name: HuggingFace model to use
    
    Returns:
        dict with 'summary', 'insights', and 'metrics'
    """
    if csv_data.empty:
        return {
            "lecture_id": lecture_id,
            "summary": "No data available for this lecture.",
            "insights": [],
            "metrics": {}
        }
    
    # Compute metrics
    metrics = compute_metrics(csv_data)
    
    # Build context for LLM
    context = format_context(lecture_id, csv_data, metrics)
    
    # Generate summary
    summarizer = get_summarizer(model_name)
    try:
        summary_text = _pipeline_summarize(summarizer, context, max_length, min_length)
    except Exception as e:
        logger.error(f"Summarization error: {e}")
        summary_text = "Error generating summary. Please try again."
    
    # Extract insights
    insights = extract_insights(metrics)
    
    return {
        "lecture_id": lecture_id,
        "summary": summary_text,
        "insights": insights,
        "metrics": metrics
    }


def compute_metrics(df: pd.DataFrame) -> dict:
    """Extract key metrics from emotion/attendance data."""
    metrics = {
        "total_students": len(df),
        "attended": len(df[df.get("attended", False) == True]) if "attended" in df.columns else 0,
        "attendance_rate": 0.0
    }
    
    if metrics["total_students"] > 0:
        metrics["attendance_rate"] = round(
            (metrics["attended"] / metrics["total_students"]) * 100, 2
        )
    
    # Emotion stats (if emotion column exists)
    if "dominant_emotion" in df.columns:
        emotion_counts = df["dominant_emotion"].value_counts()
        metrics["emotion_distribution"] = emotion_counts.to_dict()
        metrics["most_common_emotion"] = emotion_counts.idxmax() if len(emotion_counts) > 0 else "unknown"
        
        # Average emotion confidence
        if "emotion_confidence" in df.columns:
            metrics["avg_emotion_confidence"] = round(df["emotion_confidence"].mean(), 3)
    
    return metrics


def format_context(lecture_id: str, df: pd.DataFrame, metrics: dict) -> str:
    """Format data into a narrative context for LLM summarization."""
    context = f"""
Lecture Report: {lecture_id}

Attendance Summary:
- Total Students: {metrics['total_students']}
- Students Attended: {metrics['attended']}
- Attendance Rate: {metrics['attendance_rate']}%

Emotion Analysis:
"""
    
    if "emotion_distribution" in metrics:
        for emotion, count in metrics["emotion_distribution"].items():
            pct = round((count / metrics['total_students']) * 100, 1)
            context += f"- {emotion}: {count} students ({pct}%)\n"
        context += f"\nMost Common Emotion: {metrics.get('most_common_emotion', 'N/A')}"
        if "avg_emotion_confidence" in metrics:
            context += f"\nAverage Emotion Confidence: {metrics['avg_emotion_confidence']}\n"
    
    context += "\nProvide a concise summary of the lecture's emotional climate and attendance."
    return context


def extract_insights(metrics: dict) -> list:
    """Extract actionable insights from metrics."""
    insights = []
    
    if metrics["attendance_rate"] < 80:
        insights.append(f"⚠️ Low attendance: {metrics['attendance_rate']}% (target: 80%+)")
    
    if "emotion_distribution" in metrics:
        negative_emotions = metrics["emotion_distribution"].get("sad", 0) + \
                          metrics["emotion_distribution"].get("angry", 0) + \
                          metrics["emotion_distribution"].get("fear", 0)
        neg_pct = round((negative_emotions / metrics["total_students"]) * 100, 1) if metrics["total_students"] > 0 else 0
        
        if neg_pct > 30:
            insights.append(f"📉 High negative emotions: {neg_pct}% of class")
        elif metrics["emotion_distribution"].get("happy", 0) > metrics["total_students"] * 0.6:
            insights.append("✅ Positive class engagement detected")
    
    return insights


def summarize_context_text(
    lecture_id: str,
    context: str,
    max_length: int = 150,
    min_length: int = 50,
    model_name: str = "facebook/bart-large-cnn",
) -> dict:
    """Summarize a plain-text report built by the Shiny Reports panel (no CSV required)."""
    text = (context or "").strip()
    if not text:
        return {
            "lecture_id": lecture_id or "",
            "summary": "No report text was provided.",
            "insights": [],
            "metrics": {},
        }

    max_chars = int(os.getenv("LLM_CONTEXT_MAX_CHARS", "6000"))
    if len(text) > max_chars:
        text = text[:max_chars] + "\n...[truncated for model input]"

    summarizer = get_summarizer(model_name)
    try:
        summary_text = _pipeline_summarize(summarizer, text, max_length, min_length)
    except Exception as e:
        logger.error("Context summarization error: %s", e)
        excerpt = text[:900] + ("…" if len(text) > 900 else "")
        summary_text = excerpt or "Error generating summary. Check backend logs or model availability."

    return {
        "lecture_id": lecture_id or "",
        "summary": summary_text,
        "insights": [],
        "metrics": {"input_chars": len(text)},
    }


def summarize_from_csv_file(
    csv_path: str,
    lecture_id: Optional[str] = None,
    **kwargs
) -> dict:
    """
    Load CSV file and generate summary.
    
    Args:
        csv_path: Path to CSV file
        lecture_id: Lecture identifier (auto-extracted from filename if not provided)
        **kwargs: Passed to generate_lecture_summary()
    
    Returns:
        Summarization result dict
    """
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"CSV file not found: {csv_path}")
    
    df = pd.read_csv(csv_path)
    lecture_id = lecture_id or os.path.basename(csv_path).replace(".csv", "")
    
    return generate_lecture_summary(lecture_id, df, **kwargs)
