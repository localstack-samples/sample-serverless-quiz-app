#!/usr/bin/env bash

set -euo pipefail

# CDK invokes `python3 app.py` (see cdk/cdk.json) using whatever python3 is
# first on PATH, so make sure the venv holding cdk/requirements.txt (if any)
# is active even if the caller forgot to source it themselves.
if [ -f .venv/bin/activate ]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
fi

AWS_CMD=${AWS_CMD:-aws}
CDK_CMD=${CDK_CMD:-npx cdk}

# stub build the frontend code since the CDK stack needs this code to
# synthesise the FrontendStack, but we don't yet know the backend URL to inject
# into the static HTML
if [ ! -d frontend/build ]; then
    (cd frontend
    echo "REACT_APP_API_ENDPOINT=https://example.com" > .env.local
    npx react-scripts build
    )
fi

# bootstrap the stack
(cd cdk
$CDK_CMD bootstrap
)

# deploy bulk of the application
(cd cdk
$CDK_CMD deploy --require-approval never QuizAppStack
)

# get the backend API url
API_URL=$($AWS_CMD cloudformation describe-stacks --stack-name QuizAppStack --query Stacks[0].Outputs[0].OutputValue --output text)
echo "Backend API URL: $API_URL"

# build the frontend code
(cd frontend
echo "REACT_APP_API_ENDPOINT=$API_URL" > .env.local
npx react-scripts build
)

# deploy the frontend stack
(cd cdk
$CDK_CMD deploy --require-approval never FrontendStack
)

# sync the frontend build to S3 and invalidate CloudFront ourselves, rather than
# via the CDK BucketDeployment construct (see the comment in frontend_stack.py
# for why that doesn't work against LocalStack)
FRONTEND_OUTPUTS=$($AWS_CMD cloudformation describe-stacks --stack-name FrontendStack --query 'Stacks[0].Outputs')
BUCKET_NAME=$(echo "$FRONTEND_OUTPUTS" | jq -r '.[] | select(.OutputKey=="WebAppBucketName") | .OutputValue')
DISTRIBUTION_ID=$(echo "$FRONTEND_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DistributionId") | .OutputValue')
DOMAIN_NAME=$(echo "$FRONTEND_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DistributionDomainName") | .OutputValue')

$AWS_CMD s3 sync --delete frontend/build "s3://$BUCKET_NAME" >/dev/null
$AWS_CMD cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*" >/dev/null

echo
echo "CloudFront URL: https://$DOMAIN_NAME"
echo "Backend API URL: $API_URL"
