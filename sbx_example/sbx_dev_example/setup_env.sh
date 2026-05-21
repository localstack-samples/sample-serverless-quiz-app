#!/usr/bin/env bash
# Source this (don't execute it) to load the platform's default AWS
# endpoint + region into the current shell. The endpoint URL is the
# internal gateway the team's services share — it's set explicitly so
# engineers don't have to remember to pass --endpoint-url on every call.
#
# Use:  source sbx_example/sbx_dev_example/setup_env.sh
#
# To persist across all bash invocations in this sandbox:
#   sudo tee -a /etc/sandbox-persistent.sh < sbx_example/sbx_dev_example/setup_env.sh

export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_DEFAULT_OUTPUT="json"
