"""
NLP Service using Spacy for Thunderline
Provides named entity recognition, tokenization, POS tagging, and text analysis
"""

import logging
import spacy
from typing import Dict, List, Any, Optional

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global NLP model - loaded once and reused
_nlp_model = None


def load_model(model_name: str = "en_core_web_sm") -> spacy.Language:
    """
    Load Spacy language model
    
    Args:
        model_name: Name of the Spacy model (default: en_core_web_sm)
        
    Returns:
        Loaded Spacy language model
    """
    global _nlp_model
    
    if _nlp_model is None:
        logger.info(f"Loading Spacy model: {model_name}")
        _nlp_model = spacy.load(model_name)
        logger.info(f"Spacy model loaded successfully")
    
    return _nlp_model


def extract_entities(text: str, opts: Optional[Dict] = None) -> Dict[str, Any]:
    """
    Extract named entities from text using Spacy NER
    
    Args:
        text: Input text to analyze
        opts: Optional configuration (model_name, include_confidence, etc.)
        
    Returns:
        Dict with entities, labels, and metadata
    """
    opts = opts or {}
    nlp = load_model(opts.get("model_name", "en_core_web_sm"))
    
    logger.info(f"Extracting entities from text (length: {len(text)})")
    
    doc = nlp(text)
    
    entities = []
    for ent in doc.ents:
        entity_data = {
            "text": ent.text,
            "label": ent.label_,
            "start": ent.start_char,
            "end": ent.end_char
        }
        
        # Include confidence scores if available
        if hasattr(ent, "_") and hasattr(ent._, "confidence"):
            entity_data["confidence"] = ent._.confidence
            
        entities.append(entity_data)
    
    result = {
        "status": "success",
        "text": text,
        "entities": entities,
        "entity_count": len(entities),
        "labels": list(set([ent["label"] for ent in entities]))
    }
    
    logger.info(f"Extracted {len(entities)} entities")
    return result


def tokenize(text: str, opts: Optional[Dict] = None) -> Dict[str, Any]:
    """
    Tokenize text and provide detailed token information
    
    Args:
        text: Input text to tokenize
        opts: Optional configuration
        
    Returns:
        Dict with tokens and their linguistic features
    """
    opts = opts or {}
    nlp = load_model(opts.get("model_name", "en_core_web_sm"))
    
    logger.info(f"Tokenizing text (length: {len(text)})")
    
    doc = nlp(text)
    
    tokens = []
    for token in doc:
        token_data = {
            "text": token.text,
            "lemma": token.lemma_,
            "pos": token.pos_,
            "tag": token.tag_,
            "dep": token.dep_,
            "is_alpha": token.is_alpha,
            "is_stop": token.is_stop,
            "is_punct": token.is_punct
        }
        tokens.append(token_data)
    
    result = {
        "status": "success",
        "text": text,
        "tokens": tokens,
        "token_count": len(tokens)
    }
    
    logger.info(f"Tokenized into {len(tokens)} tokens")
    return result


def analyze_sentiment(text: str, opts: Optional[Dict] = None) -> Dict[str, Any]:
    """
    Analyze text sentiment (basic implementation using linguistic features)
    
    Args:
        text: Input text to analyze
        opts: Optional configuration
        
    Returns:
        Dict with sentiment analysis results
    """
    opts = opts or {}
    nlp = load_model(opts.get("model_name", "en_core_web_sm"))
    
    logger.info(f"Analyzing sentiment for text (length: {len(text)})")
    
    doc = nlp(text)
    
    # Simple sentiment analysis based on linguistic patterns
    # For production, consider using a specialized sentiment model
    
    positive_indicators = 0
    negative_indicators = 0
    
    for token in doc:
        # Very basic sentiment - enhance with a proper sentiment lexicon
        if token.pos_ == "ADJ":
            # Check if adjective is in common positive/negative lists
            # This is a simplified example
            if token.text.lower() in ["good", "great", "excellent", "wonderful", "amazing"]:
                positive_indicators += 1
            elif token.text.lower() in ["bad", "terrible", "awful", "horrible", "poor"]:
                negative_indicators += 1
    
    total_indicators = positive_indicators + negative_indicators
    
    if total_indicators == 0:
        sentiment = "neutral"
        score = 0.0
    elif positive_indicators > negative_indicators:
        sentiment = "positive"
        score = positive_indicators / total_indicators
    elif negative_indicators > positive_indicators:
        sentiment = "negative"
        score = -(negative_indicators / total_indicators)
    else:
        sentiment = "neutral"
        score = 0.0
    
    result = {
        "status": "success",
        "text": text,
        "sentiment": sentiment,
        "score": score,
        "positive_indicators": positive_indicators,
        "negative_indicators": negative_indicators
    }
    
    logger.info(f"Sentiment: {sentiment} (score: {score})")
    return result


def analyze_syntax(text: str, opts: Optional[Dict] = None) -> Dict[str, Any]:
    """
    Analyze syntactic structure of text
    
    Args:
        text: Input text to analyze
        opts: Optional configuration
        
    Returns:
        Dict with syntactic analysis including noun chunks, dependency parse
    """
    opts = opts or {}
    nlp = load_model(opts.get("model_name", "en_core_web_sm"))
    
    logger.info(f"Analyzing syntax for text (length: {len(text)})")
    
    doc = nlp(text)
    
    # Extract noun chunks
    noun_chunks = []
    for chunk in doc.noun_chunks:
        noun_chunks.append({
            "text": chunk.text,
            "root": chunk.root.text,
            "root_dep": chunk.root.dep_,
            "root_head": chunk.root.head.text
        })
    
    # Extract sentences
    sentences = []
    for sent in doc.sents:
        sentences.append({
            "text": sent.text,
            "root": sent.root.text,
            "start": sent.start_char,
            "end": sent.end_char
        })
    
    result = {
        "status": "success",
        "text": text,
        "noun_chunks": noun_chunks,
        "sentences": sentences,
        "sentence_count": len(sentences)
    }
    
    logger.info(f"Found {len(noun_chunks)} noun chunks and {len(sentences)} sentences")
    return result


def process_text(text: str, opts: Optional[Dict] = None) -> Dict[str, Any]:
    """
    Full NLP processing pipeline - entities, tokens, sentiment, syntax
    
    Args:
        text: Input text to process
        opts: Optional configuration (include_entities, include_tokens, etc.)
        
    Returns:
        Dict with complete NLP analysis
    """
    opts = opts or {}
    
    logger.info(f"Processing text with full NLP pipeline (length: {len(text)})")
    
    result = {
        "status": "success",
        "text": text
    }
    
    # Include entities if requested (default: True)
    if opts.get("include_entities", True):
        entities_result = extract_entities(text, opts)
        result["entities"] = entities_result["entities"]
        result["entity_labels"] = entities_result["labels"]
    
    # Include tokens if requested (default: False, can be verbose)
    if opts.get("include_tokens", False):
        tokens_result = tokenize(text, opts)
        result["tokens"] = tokens_result["tokens"]
        result["token_count"] = tokens_result["token_count"]
    
    # Include sentiment if requested (default: True)
    if opts.get("include_sentiment", True):
        sentiment_result = analyze_sentiment(text, opts)
        result["sentiment"] = sentiment_result["sentiment"]
        result["sentiment_score"] = sentiment_result["score"]
    
    # Include syntax if requested (default: True)
    if opts.get("include_syntax", True):
        syntax_result = analyze_syntax(text, opts)
        result["noun_chunks"] = syntax_result["noun_chunks"]
        result["sentences"] = syntax_result["sentences"]
    
    logger.info(f"Full NLP processing complete")
    return result


# Health check function
def health_check() -> Dict[str, str]:
    """
    Check if NLP service is healthy
    
    Returns:
        Dict with health status
    """
    try:
        nlp = load_model()
        # Simple test
        doc = nlp("Test")
        return {
            "status": "healthy",
            "model": "en_core_web_sm",
            "version": spacy.__version__
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }
