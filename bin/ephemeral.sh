#!/bin/bash

INSTANCE_NAME="instance-$(openssl rand -hex 4)"
echo "Creating ephemeral instance with name: $INSTANCE_NAME"

# TODO(lstk): no ephemeral-instance equivalent in lstk yet — this still requires the `localstack` CLI.
CREATE_RESPONSE=$(localstack ephemeral create \
  --name "$INSTANCE_NAME" \
  --lifetime 120 \
  --env LAMBDA_KEEPALIVE_MS=7200000 \
  --env EXTENSION_AUTO_INSTALL=localstack-extension-mailhog \
  --env DISABLE_CUSTOM_CORS_APIGATEWAY=1 \
  --env EXTRA_CORS_ALLOWED_ORIGINS='*' \
  --env DISABLE_CUSTOM_CORS_S3=1
)

if echo "$CREATE_RESPONSE" | grep -q '"endpoint_url"'; then
  echo "Ephemeral instance created successfully."
else
  echo "Error creating ephemeral instance:"
  echo "$CREATE_RESPONSE"
  exit 1
fi

ENDPOINT_URL=$(echo "$CREATE_RESPONSE" | jq -r '.endpoint_url')

export AWS_ENDPOINT_URL="$ENDPOINT_URL"
export ENDPOINT_URL="$ENDPOINT_URL"

echo "Deploying resources..."
bash bin/deploy.sh > /dev/null 2>&1
echo "Deployment completed."

DISTRIBUTION_ID=$(lstk aws cloudfront list-distributions --endpoint-url="$ENDPOINT_URL" | jq -r '.DistributionList.Items[0].Id')

if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "null" ]; then
  echo "Error retrieving CloudFront distribution ID."
  exit 1
fi

echo "Link to the ephemeral instance CloudFront distribution:"
echo "$ENDPOINT_URL/cloudfront/$DISTRIBUTION_ID/"
