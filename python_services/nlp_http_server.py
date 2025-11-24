#!/usr/bin/env python3.13
"""
Thunderline NLP HTTP Server
Simple Flask wrapper around nlp_service for reliable communication
"""

import os
import sys
import logging
from flask import Flask, request, jsonify
import nlp_service

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create Flask app
app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'service': 'thunderline-nlp',
        'model': 'en_core_web_sm'
    })

@app.route('/entities', methods=['POST'])
def extract_entities():
    """Extract named entities from text"""
    try:
        data = request.get_json()
        text = data.get('text')
        opts = data.get('opts', {})
        
        if not text:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        result = nlp_service.extract_entities(text, opts)
        return jsonify(result)
    
    except Exception as e:
        logger.error(f"Error in extract_entities: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@app.route('/tokenize', methods=['POST'])
def tokenize():
    """Tokenize text"""
    try:
        data = request.get_json()
        text = data.get('text')
        opts = data.get('opts', {})
        
        if not text:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        result = nlp_service.tokenize(text, opts)
        return jsonify(result)
    
    except Exception as e:
        logger.error(f"Error in tokenize: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@app.route('/sentiment', methods=['POST'])
def analyze_sentiment():
    """Analyze sentiment of text"""
    try:
        data = request.get_json()
        text = data.get('text')
        opts = data.get('opts', {})
        
        if not text:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        result = nlp_service.analyze_sentiment(text, opts)
        return jsonify(result)
    
    except Exception as e:
        logger.error(f"Error in analyze_sentiment: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@app.route('/syntax', methods=['POST'])
def analyze_syntax():
    """Analyze syntactic structure"""
    try:
        data = request.get_json()
        text = data.get('text')
        opts = data.get('opts', {})
        
        if not text:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        result = nlp_service.analyze_syntax(text, opts)
        return jsonify(result)
    
    except Exception as e:
        logger.error(f"Error in analyze_syntax: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@app.route('/process', methods=['POST'])
def process_text():
    """Full NLP processing pipeline"""
    try:
        data = request.get_json()
        text = data.get('text')
        opts = data.get('opts', {})
        
        if not text:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        result = nlp_service.process_text(text, opts)
        return jsonify(result)
    
    except Exception as e:
        logger.error(f"Error in process_text: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('NLP_SERVER_PORT', 5555))
    logger.info(f"Starting NLP HTTP server on port {port}...")
    app.run(host='127.0.0.1', port=port, debug=False)
