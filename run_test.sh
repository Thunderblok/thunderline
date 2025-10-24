#!/bin/bash
# Simple test runner that uses iex to properly start all dependencies

cd /home/mo/DEV/Thunderline

# Run the test in iex with proper supervision
iex -S mix -e "
# Load the test script
Code.eval_file(\"test_message_flow.exs\")

# Exit after test completes
System.halt(0)
"
