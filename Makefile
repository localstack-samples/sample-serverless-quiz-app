
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
	localstack state export app-state.zip

load-state:     ## Load the application state from a local file
	localstack state import app-state.zip

clean:          ## Clean up any temporary files
	rm *.zip

hot-reload:     ## Reconfigure the Lambda function to enable hot reloading
	awslocal lambda update-function-code --function-name ScoringFunction --s3-bucket hot-reload --s3-key "$$(pwd)/lambdas/scoring"

start-debug:    ## Start LocalStack with Lambda debug mode enabled
	DEBUG=1 LOCALSTACK_LAMBDA_DEBUG_MODE=1 \
		LOCALSTACK_LAMBDA_DEBUG_MODE_CONFIG_PATH=/tmp/debug_config.yml \
        localstack start --volume $$(pwd)/etc/debug-config.yml:/tmp/debug_config.yml

.PHONY: usage deploy web save-state load-state clean
