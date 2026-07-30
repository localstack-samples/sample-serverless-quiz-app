#!/bin/bash

API_NAME="QuizAPI"

# Check if AWS_ENDPOINT_URL is set, otherwise default to localhost:4566
AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-"http://localhost:4566"}

API_ID=$(lstk aws apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id" \
  --output text)

if [ -z "$API_ID" ]; then
  echo "Error: API ID not found."
  exit 1
fi

API_ENDPOINT="$AWS_ENDPOINT_URL/_aws/execute-api/$API_ID/prod"

echo "REACT_APP_API_ENDPOINT=$API_ENDPOINT" > .env.local

echo "API endpoint fetched and stored in .env.local"
