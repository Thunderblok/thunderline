#!/usr/bin/env python3.13
"""
NLP CLI - JSON stdin/stdout interface for Thunderline NLP Bridge

Contract (line-delimited JSON):
  STDIN:  {"op": "analyze", "text": "...", "lang": "en", "schema_version": "1.0"}
  STDOUT: {"ok": true, "entities": [...], "tokens": [...], "schema_version": "1.0"}

Supports both legacy nlp_service functions and new spaCy-based analyze op.
"""

import sys
import json
import logging

# Try to import existing nlp_service (legacy support)
try:
    import nlp_service
    HAS_NLP_SERVICE = True
except ImportError:
    HAS_NLP_SERVICE = False

# Try to import spaCy for new analyze operation
try:
    import spacy
    nlp_en = spacy.load("en_core_web_sm")
    HAS_SPACY = True
except (ImportError, OSError):
    HAS_SPACY = False

# Log to stderr only (stdout reserved for JSON)
logging.basicConfig(
    level=logging.ERROR,
    format="%(asctime)s [NLP-CLI] %(levelname)s: %(message)s",
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

SCHEMA_VERSION = "1.0"


def analyze_spacy(text, lang="en"):
    """New spaCy-based analysis (preferred)."""
    if not HAS_SPACY:
        return {
            "ok": False,
            "error": "spaCy not available. Install: pip install spacy && python -m spacy download en_core_web_sm"
        }
    
    doc = nlp_en(text)
    
    return {
        "ok": True,
        "schema_version": SCHEMA_VERSION,
        "entities": [
            {"text": ent.text, "label": ent.label_, "start": ent.start_char, "end": ent.end_char}
            for ent in doc.ents
        ],
        "tokens": [
            {"text": tok.text, "lemma": tok.lemma_, "pos": tok.pos_, "dep": tok.dep_}
            for tok in doc
        ]
    }


def handle_request(request):
    """Route request to appropriate handler."""
    
    # New spaCy-based analyze operation
    if request.get("op") == "analyze":
        if request.get("schema_version") != SCHEMA_VERSION:
            return {
                "ok": False,
                "error": f"Schema version mismatch. Expected {SCHEMA_VERSION}, got {request.get('schema_version')}"
            }
        
        text = request.get("text")
        lang = request.get("lang", "en")
        
        if not text:
            return {"ok": False, "error": "Missing 'text' parameter"}
        
        result = analyze_spacy(text, lang)
        
        # Echo request ID for correlation
        if "_req_id" in request:
            result["_req_id"] = request["_req_id"]
        
        return result
    
    # Legacy nlp_service function calls
    function = request.get('function')
    if not function:
        return {"error": "Missing 'op' or 'function' in request"}
    
    if not HAS_NLP_SERVICE:
        return {"error": "nlp_service module not available"}
    
    args = request.get('args', [])
    
    try:
        if function == 'extract_entities':
            result = nlp_service.extract_entities(*args)
        elif function == 'tokenize':
            result = nlp_service.tokenize(*args)
        elif function == 'analyze_sentiment':
            result = nlp_service.analyze_sentiment(*args)
        elif function == 'analyze_syntax':
            result = nlp_service.analyze_syntax(*args)
        elif function == 'process_text':
            result = nlp_service.process_text(*args)
        else:
            result = {"error": f"Unknown function: {function}"}
        
        return result
        
    except Exception as e:
        return {"error": str(e), "type": type(e).__name__}


def main():
    """Main event loop - process line-delimited JSON."""
    logger.info(f"NLP CLI started (schema v{SCHEMA_VERSION})")
    logger.info(f"spaCy available: {HAS_SPACY}, nlp_service available: {HAS_NLP_SERVICE}")
    
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            
            try:
                request = json.loads(line)
                response = handle_request(request)
            except json.JSONDecodeError as e:
                logger.error(f"Invalid JSON: {e}")
                response = {"ok": False, "error": f"Invalid JSON: {str(e)}"}
            
            # Write response to stdout (flush immediately for Port compatibility)
            print(json.dumps(response), flush=True)
    
    except KeyboardInterrupt:
        logger.info("Shutdown requested")
        sys.exit(0)
    except Exception as e:
        logger.exception("Fatal error in main loop")
        sys.exit(1)


if __name__ == '__main__':
    main()
