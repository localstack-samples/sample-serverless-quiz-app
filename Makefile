
usage:		    ## Show usage for this Makefile
	@cat Makefile | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

deploy:         ## Deploy the application to LocalStack
	bin/deploy.sh

deploy-cdk:     ## Deploy the application to LocalStack via CDK
	AWS_CMD="lstk aws" CDK_CMD="lstk cdk" bin/deploy_cdk.sh

web:            ## Open the Web app in the browser (after the app is deployed)
	DOMAIN_NAME=$$(lstk aws cloudfront list-distributions | jq -r '.DistributionList.Items[0].DomainName'); \
	    echo "CloudFront URL: https://$$DOMAIN_NAME"; \
	    open "https://$$DOMAIN_NAME"

save-state:     ## Save the application state to a local file
	lstk save app-state.snapshot

load-state:     ## Load the application state from a local file
	lstk load app-state.snapshot

clean:          ## Clean up any temporary files
	rm *.snapshot

hot-reload:
	lstk aws lambda update-function-code --function-name ScoringFunction --s3-bucket hot-reload --s3-key "$$(pwd)/lambdas/scoring"

start:          ## Start LocalStack
	@test -n "${LOCALSTACK_AUTH_TOKEN}" || (echo "LOCALSTACK_AUTH_TOKEN is not set. Find your token at https://app.localstack.cloud/workspace/auth-token"; exit 1)
	@LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) lstk start --timeout 30s

stop:           ## Stop LocalStack
	@lstk stop

logs:           ## Save the logs in a separate file
	@lstk logs > logs.txt

.PHONY: usage deploy web save-state load-state clean start stop logs
