#!/usr/bin/env python3.13
"""
NLP CLI - Simple stdin/stdout interface for nlp_service
Bypasses msgpack serialization issues by using JSON over subprocess
"""

import sys
import json
import logging
import nlp_service

# Suppress most logging for clean JSON output
logging.basicConfig(level=logging.ERROR)

def main():
    try:
        # Read JSON request from stdin (line-delimited for Port compatibility)
        request_line = sys.stdin.readline()
        request = json.loads(request_line)
        
        function = request['function']
        args = request['args']
        
        # Call the appropriate function
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
        
        # Output JSON result to stdout
        print(json.dumps(result), flush=True)
        sys.exit(0)
        
    except Exception as e:
        # Output error as JSON
        error_result = {"error": str(e), "type": type(e).__name__}
        print(json.dumps(error_result), flush=True)
        sys.exit(1)

if __name__ == '__main__':
    main()
