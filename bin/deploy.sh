#!/bin/bash

set -e
set -o pipefail

AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-"http://localhost:4566"}

# Detect host architecture so we create Lambda functions with a matching
# runtime image. If the host is aarch64/arm64 (Apple Silicon, ARM sandboxes)
# but the function is created with the default x86_64 architecture, the
# Lambda runtime container will fail with "exec format error" — every
# invocation then hangs for ~90s and returns HTTP 502.
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    aarch64|arm64) LAMBDA_ARCH="arm64" ;;
    x86_64|amd64)  LAMBDA_ARCH="x86_64" ;;
    *) echo "Unsupported host arch: $HOST_ARCH" >&2; exit 1 ;;
esac
export LAMBDA_ARCH

# Colors for logging
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

error_log() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

trap 'error_log "An error occurred. Exiting..."; exit 1' ERR

# Create DynamoDB tables
log "Creating DynamoDB tables..."

log "Creating 'Quizzes' table..."
awslocal dynamodb create-table \
    --table-name Quizzes \
    --attribute-definitions AttributeName=QuizID,AttributeType=S \
    --key-schema AttributeName=QuizID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --output text >/dev/null

log "Creating 'UserSubmissions' table..."
awslocal dynamodb create-table \
    --table-name UserSubmissions \
    --attribute-definitions \
        AttributeName=SubmissionID,AttributeType=S \
        AttributeName=QuizID,AttributeType=S \
        AttributeName=Score,AttributeType=N \
    --key-schema AttributeName=SubmissionID,KeyType=HASH \
    --global-secondary-indexes \
        '[
            {
                "IndexName": "QuizID-Score-index",
                "KeySchema": [
                    {"AttributeName": "QuizID", "KeyType": "HASH"},
                    {"AttributeName": "Score", "KeyType": "RANGE"}
                ],
                "Projection": {"ProjectionType": "ALL"},
                "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
            }
        ]' \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --output text >/dev/null

log "DynamoDB tables created successfully."

# Create SQS queue
log "Creating SQS queue 'QuizSubmissionQueue'..."
awslocal sqs create-queue --queue-name QuizSubmissionQueue >/dev/null
log "SQS queue 'QuizSubmissionQueue' created successfully."

# Zip Lambda functions
log "Zipping Lambda functions..."
zip -j get_quiz_function.zip lambdas/get_quiz/handler.py >/dev/null
zip -j create_quiz_function.zip lambdas/create_quiz/handler.py >/dev/null
zip -j submit_quiz_function.zip lambdas/submit_quiz/handler.py >/dev/null
zip -j scoring_function.zip lambdas/scoring/handler.py >/dev/null
zip -j get_submission_function.zip lambdas/get_submission/handler.py >/dev/null
zip -j get_leaderboard_function.zip lambdas/get_leaderboard/handler.py >/dev/null
zip -j list_quizzes_function.zip lambdas/list_quizzes/handler.py >/dev/null
zip -j retry_quizzes_writes_function.zip lambdas/retry_quizzes_writes/handler.py >/dev/null
log "Lambda functions zipped successfully."

# Function names and their policy files
FUNCTIONS=(
  "CreateQuizFunction configurations/create_quiz_policy.json CreateQuizRole"
  "GetQuizFunction configurations/get_quiz_policy.json GetQuizRole"
  "SubmitQuizFunction configurations/submit_quiz_policy.json SubmitQuizRole"
  "ScoringFunction configurations/scoring_policy.json ScoringRole"
  "GetSubmissionFunction configurations/get_submission_policy.json GetSubmissionRole"
  "GetLeaderboardFunction configurations/get_leaderboard_policy.json GetLeaderboardRole"
  "ListPublicQuizzesFunction configurations/list_quizzes_policy.json ListQuizzesRole"
  "RetryQuizzesWritesFunction configurations/retry_quizzes_writes_policy.json RetryQuizzesWritesRole"
)

# Create IAM policies and roles
log "Creating IAM policies and roles for Lambda functions..."
for FUNCTION_INFO in "${FUNCTIONS[@]}"; do
  read FUNCTION_NAME POLICY_FILE ROLE_NAME <<< "$FUNCTION_INFO"

  log "Creating IAM policy for $FUNCTION_NAME..."
  awslocal iam create-policy \
      --policy-name ${FUNCTION_NAME}Policy \
      --policy-document file://${POLICY_FILE} >/dev/null

  log "Creating IAM role $ROLE_NAME..."
  ROLE_ARN=$(awslocal iam create-role \
      --role-name ${ROLE_NAME} \
      --assume-role-policy-document file://configurations/lambda_trust_policy.json \
      --query 'Role.Arn' --output text)

  log "Attaching policy to role $ROLE_NAME..."
  awslocal iam attach-role-policy \
      --role-name ${ROLE_NAME} \
      --policy-arn arn:aws:iam::000000000000:policy/${FUNCTION_NAME}Policy
done
log "IAM policies and roles created successfully."

# Create IAM Policy and Role for State Machine
log "Creating IAM policy and role for State Machine..."
awslocal iam create-policy \
    --policy-name SendEmailStateMachinePolicy \
    --policy-document file://configurations/state_machine_policy.json >/dev/null

awslocal iam create-role \
    --role-name SendEmailStateMachineRole \
    --assume-role-policy-document file://configurations/state_machine_trust_policy.json >/dev/null

awslocal iam attach-role-policy \
    --role-name SendEmailStateMachineRole \
    --policy-arn arn:aws:iam::000000000000:policy/SendEmailStateMachinePolicy
log "IAM policy and role for State Machine created successfully."

# Deploy Lambdas
log "Deploying Lambda functions..."
# Array of Lambda functions and their zip files
LAMBDAS=(
  "CreateQuizFunction create_quiz_function.zip CreateQuizRole"
  "GetQuizFunction get_quiz_function.zip GetQuizRole"
  "SubmitQuizFunction submit_quiz_function.zip SubmitQuizRole"
  "ScoringFunction scoring_function.zip ScoringRole"
  "GetSubmissionFunction get_submission_function.zip GetSubmissionRole"
  "GetLeaderboardFunction get_leaderboard_function.zip GetLeaderboardRole"
  "ListPublicQuizzesFunction list_quizzes_function.zip ListQuizzesRole"
  "RetryQuizzesWritesFunction retry_quizzes_writes_function.zip RetryQuizzesWritesRole"
)

for LAMBDA_INFO in "${LAMBDAS[@]}"; do
  read FUNCTION_NAME ZIP_FILE ROLE_NAME <<< "$LAMBDA_INFO"

  log "Creating Lambda function $FUNCTION_NAME (arch=$LAMBDA_ARCH)..."
  awslocal lambda create-function \
      --function-name ${FUNCTION_NAME} \
      --runtime python3.10 \
      --architectures ${LAMBDA_ARCH} \
      --handler handler.lambda_handler \
      --zip-file fileb://${ZIP_FILE} \
      --role arn:aws:iam::000000000000:role/${ROLE_NAME} \
      --timeout 180 \
      --output text >/dev/null
done
log "Lambda functions deployed successfully."

# SQS Trigger
log "Setting up SQS trigger for ScoringFunction..."
QUEUE_URL=$(awslocal sqs get-queue-url --queue-name QuizSubmissionQueue --query 'QueueUrl' --output text)
QUEUE_ARN=$(awslocal sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

awslocal lambda create-event-source-mapping \
    --function-name ScoringFunction \
    --batch-size 10 \
    --event-source-arn $QUEUE_ARN >/dev/null
log "SQS trigger set up successfully."

# Create REST API
log "Creating REST API..."
API_ID=$(awslocal apigateway create-rest-api \
    --name 'QuizAPI' \
    --query 'id' --output text)
log "REST API 'QuizAPI' created with ID: $API_ID"

# Get Root Resource ID
PARENT_ID=$(awslocal apigateway get-resources \
    --rest-api-id $API_ID \
    --query 'items[0].id' --output text)
log "Root resource ID: $PARENT_ID"

# Create API Gateway resources and methods
ENDPOINTS=(
  "getquiz GET GetQuizFunction"
  "createquiz POST CreateQuizFunction"
  "submitquiz POST SubmitQuizFunction"
  "getsubmission GET GetSubmissionFunction"
  "getleaderboard GET GetLeaderboardFunction"
  "listquizzes GET ListPublicQuizzesFunction"
)

for ENDPOINT_INFO in "${ENDPOINTS[@]}"; do
  read PATH_PART HTTP_METHOD FUNCTION_NAME <<< "$ENDPOINT_INFO"

  log "Setting up API endpoint /$PATH_PART [$HTTP_METHOD] -> $FUNCTION_NAME"

  RESOURCE_ID=$(awslocal apigateway create-resource \
      --rest-api-id $API_ID \
      --parent-id $PARENT_ID \
      --path-part $PATH_PART \
      --query 'id' --output text)

  awslocal apigateway put-method \
      --rest-api-id $API_ID \
      --resource-id $RESOURCE_ID \
      --http-method $HTTP_METHOD \
      --authorization-type "NONE" >/dev/null

  awslocal apigateway put-integration \
      --rest-api-id $API_ID \
      --resource-id $RESOURCE_ID \
      --http-method $HTTP_METHOD \
      --type AWS_PROXY \
      --integration-http-method POST \
      --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:${FUNCTION_NAME}/invocations >/dev/null

  awslocal apigateway put-method \
      --rest-api-id $API_ID \
      --resource-id $RESOURCE_ID \
      --http-method OPTIONS \
      --authorization-type "NONE" >/dev/null

  awslocal apigateway put-integration \
      --rest-api-id $API_ID \
      --resource-id $RESOURCE_ID \
      --http-method OPTIONS \
      --type MOCK \
      --request-templates '{ "application/json": "{\"statusCode\": 200}" }' >/dev/null

  awslocal apigateway put-method-response \
      --rest-api-id $API_ID \
      --resource-id $RESOURCE_ID \
      --http-method OPTIONS \
      --status-code 204 \
      --response-parameters "method.response.header.Access-Control-Allow-Headers=true,method.response.header.Access-Control-Allow-Origin=true,method.response.header.Access-Control-Allow-Methods=true" >/dev/null

  awslocal apigateway put-integration-response \
      --rest-api-id $API_ID \
      --resource-id $RESOURCE_ID \
      --http-method OPTIONS \
      --status-code 204 \
      --response-parameters "{\"method.response.header.Access-Control-Allow-Headers\": \"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'\", \"method.response.header.Access-Control-Allow-Origin\": \"'*'\", \"method.response.header.Access-Control-Allow-Methods\": \"'OPTIONS,$HTTP_METHOD'\"}" >/dev/null
done
log "API endpoints set up successfully."

# Deploy API
log "Deploying API..."
awslocal apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name prod >/dev/null
API_ENDPOINT="http://localhost:4566/_aws/execute-api/$API_ID/prod"
log "API deployed. Endpoint: $API_ENDPOINT"

# SQS DLQ -> EventBridge Pipes -> SNS
log "Setting up SQS DLQ, EventBridge Pipes, and SNS..."
SNS_TOPIC_ARN=$(awslocal sns create-topic --name DLQAlarmTopic --output json | jq -r '.TopicArn')
DLQ_URL=$(awslocal sqs create-queue --queue-name QuizSubmissionDLQ --output json | jq -r '.QueueUrl')
DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
log "SNS Topic ARN: $SNS_TOPIC_ARN"
log "DLQ ARN: $DLQ_ARN"

# Configure SQS Redrive Policy
log "Configuring SQS Redrive Policy..."
awslocal sqs set-queue-attributes \
    --queue-url $QUEUE_URL \
    --attributes '{
        "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$DLQ_ARN'\",\"maxReceiveCount\":\"1\"}",
        "VisibilityTimeout": "10"
    }' >/dev/null
log "SQS Redrive Policy configured."

# Verify Email Identity for SES
log "Verifying email identity for SES..."
awslocal ses verify-email-identity --email your.email@example.com >/dev/null
awslocal ses verify-email-identity --email admin@localstack.com >/dev/null
log "Email identity verified. Check your email to confirm."

# Subscribe Email to SNS Topic
log "Subscribing email to SNS Topic..."
awslocal sns subscribe \
    --topic-arn $SNS_TOPIC_ARN \
    --protocol email \
    --notification-endpoint your.email@example.com >/dev/null
log "Email subscribed to SNS Topic."

# Create IAM Role for Pipe
log "Creating IAM Role for EventBridge Pipe..."
awslocal iam create-role \
    --role-name PipeRole \
    --assume-role-policy-document file://configurations/pipe_role_trust_policy.json >/dev/null

awslocal iam put-role-policy \
    --role-name PipeRole \
    --policy-name PipePolicy \
    --policy-document file://configurations/pipe_role_policy.json >/dev/null
log "IAM Role for Pipe created."

# Create EventBridge Pipe
log "Creating EventBridge Pipe..."
awslocal pipes create-pipe \
  --name DLQToSNSPipe \
  --source $DLQ_ARN \
  --target $SNS_TOPIC_ARN \
  --role-arn arn:aws:iam::000000000000:role/PipeRole >/dev/null
log "EventBridge Pipe created."

# Create State Machine
log "Creating Step Functions State Machine..."
awslocal stepfunctions create-state-machine \
    --name SendEmailStateMachine \
    --definition file://configurations/statemachine.json \
    --role-arn arn:aws:iam::000000000000:role/SendEmailStateMachineRole >/dev/null
log "State Machine created."

# Deploy Frontend
log "Deploying frontend..."
pushd frontend >/dev/null
if [ -d "node_modules" ]; then
    log "node_modules directory already present. Skipping npm install."
else
    log "node_modules directory not found. Installing dependencies..."
    npm install >/dev/null
fi

log "Building the project..."
npm run build >/dev/null

log "Uploading frontend build to S3..."
awslocal s3 mb s3://webapp >/dev/null
awslocal s3 sync --delete ./build s3://webapp >/dev/null
awslocal s3 website s3://webapp --index-document index.html --error-document index.html >/dev/null
popd >/dev/null
log "Frontend deployed to S3."

# Create CloudFront Distribution
log "Creating CloudFront Distribution..."
DISTRIBUTION=$(awslocal cloudfront create-distribution-with-tags \
  --distribution-config-with-tags "$(jq '{DistributionConfig: ., Tags: {Items: [{Key: "_custom_id_", Value: "quiz-app"}]}}' configurations/distribution-config.json)")
DOMAIN_NAME=$(echo "$DISTRIBUTION" | jq -r '.Distribution.DomainName')
log "CloudFront Distribution created. Domain Name: https://$DOMAIN_NAME"

# Setup Chaos Testing
log "Setting up Chaos Testing..."
awslocal sns create-topic --name QuizzesWriteFailures --output json >/dev/null

WRITE_FAILURES_QUEUE_URL=$(awslocal sqs create-queue --queue-name QuizzesWriteFailuresQueue --attributes VisibilityTimeout=60 --output json | jq -r '.QueueUrl')
WRITE_FAILURES_QUEUE_ARN=$(awslocal sqs get-queue-attributes --queue-url $WRITE_FAILURES_QUEUE_URL --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

awslocal sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:000000000000:QuizzesWriteFailures \
    --protocol sqs \
    --notification-endpoint $WRITE_FAILURES_QUEUE_ARN \
    --output text >/dev/null

awslocal lambda create-event-source-mapping \
    --function-name RetryQuizzesWritesFunction \
    --batch-size 10 \
    --event-source-arn $WRITE_FAILURES_QUEUE_ARN \
    --enabled \
    --output text >/dev/null
log "Chaos Testing setup completed."

# API Gateway permissions
log "Setting up API Gateway permissions for Lambda functions..."
API_NAME="QuizAPI"
API_ID=$(awslocal apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id" \
  --output text)

LAMBDA_PERMISSIONS=(
  "CreateQuizFunction POST createquiz"
  "SubmitQuizFunction POST submitquiz"
  "GetQuizFunction GET getquiz"
  "GetSubmissionFunction GET getsubmission"
  "GetLeaderboardFunction GET getleaderboard"
  "ListPublicQuizzesFunction GET listquizzes"
)

for PERMISSION_INFO in "${LAMBDA_PERMISSIONS[@]}"; do
  read FUNCTION_NAME HTTP_METHOD PATH_PART <<< "$PERMISSION_INFO"

  log "Adding permission for $FUNCTION_NAME to be invoked by API Gateway..."
  awslocal lambda add-permission \
      --function-name ${FUNCTION_NAME} \
      --statement-id AllowAPIGatewayInvoke \
      --action lambda:InvokeFunction \
      --principal apigateway.amazonaws.com \
      --source-arn "arn:aws:execute-api:us-east-1:000000000000:${API_ID}/*/${HTTP_METHOD}/${PATH_PART}" >/dev/null
done
log "API Gateway permissions set."

# Set SQS Queue Policy for QuizzesWriteFailuresQueue
log "Setting SQS Queue Policy for QuizzesWriteFailuresQueue..."
QUEUE_URL=$(awslocal sqs get-queue-url --queue-name QuizzesWriteFailuresQueue --output text --query QueueUrl)

policy_json=$(cat configurations/sqs_queue_policy.json | jq -c . | jq -R .)

awslocal sqs set-queue-attributes --queue-url "$QUEUE_URL" --attributes "{\"Policy\":$policy_json}" >/dev/null

awslocal sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All >/dev/null
log "SQS Queue Policy set."

# Cleanup
log "Cleaning up temporary files..."
rm *.zip
log "Cleanup completed."

log "Starting seed process..."
./bin/seed.sh
log "Seed process completed successfully."

# Final Output
log "Deployment completed successfully."
echo
echo -e "${BLUE}CloudFront URL:${NC} https://${DOMAIN_NAME}"
echo -e "${BLUE}API Gateway Endpoint:${NC} ${API_ENDPOINT}"
