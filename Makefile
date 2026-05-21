
usage:		    ## Show usage for this Makefile
	@cat Makefile | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

deploy:         ## Deploy the application to LocalStack
	bin/deploy.sh

deploy-cdk:     ## Deploy the application to LocalStack via CDK
	AWS_CMD=awslocal CDK_CMD=cdklocal bin/deploy_cdk.sh

web:            ## Open the Web app in the browser (after the app is deployed)
	DOMAIN_NAME=$$(awslocal cloudfront list-distributions | jq -r '.DistributionList.Items[0].DomainName'); \
	    echo "CloudFront URL: https://$$DOMAIN_NAME"; \
	    open "https://$$DOMAIN_NAME"

save-state:     ## Save the application state to a local file
	lstk snapshot save app-state.zip

clean:          ## Clean up any temporary files
	rm *.zip

hot-reload:
	awslocal lambda update-function-code --function-name ScoringFunction --s3-bucket hot-reload --s3-key "$$(pwd)/lambdas/scoring"

start:          ## Start LocalStack (via lstk)
	@test -n "${LOCALSTACK_AUTH_TOKEN}" || (echo "LOCALSTACK_AUTH_TOKEN is not set. Find your token at https://app.localstack.cloud/workspace/auth-token"; exit 1)
	@LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) lstk start --non-interactive

stop:           ## Stop LocalStack
	@lstk stop

ready:          ## Wait until LocalStack is ready
	@echo Waiting on the LocalStack container...
	@for i in $$(seq 1 60); do \
	    curl -sf http://localhost:4566/_localstack/health >/dev/null && \
	        { echo LocalStack is ready to use!; exit 0; }; \
	    sleep 1; \
	done; echo Gave up waiting on LocalStack, exiting.; exit 1

logs:           ## Save the logs in a separate file
	@lstk logs > logs.txt

.PHONY: usage deploy web save-state clean start stop ready logs
