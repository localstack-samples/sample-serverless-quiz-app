SBX_NAME   ?= localstack-test
SBX_AGENT  ?= claude
REPO_ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

usage:          ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

run:            ## Start and attach to the sandbox — creates it if needed (blocking)
	cd $(REPO_ROOT) && sbx run --name $(SBX_NAME) $(SBX_AGENT) $(REPO_ROOT)

configure:      ## Publish ports and inject token — run from a second terminal while 'make run' is active
	$(MAKE) publish-ports
	@if [ -n "$(LOCALSTACK_AUTH_TOKEN)" ]; then \
	  $(MAKE) inject-token; \
	fi

publish-ports:  ## Publish required ports (7681 demo terminal, 4566 LocalStack API)
	cd $(REPO_ROOT) && sbx ports $(SBX_NAME) --publish 7681:7681/tcp || true
	cd $(REPO_ROOT) && sbx ports $(SBX_NAME) --publish 4566:4566/tcp || true

inject-token:   ## Inject LOCALSTACK_AUTH_TOKEN into the sandbox (requires token to be set)
	@test -n "$(LOCALSTACK_AUTH_TOKEN)" || (echo "ERROR: LOCALSTACK_AUTH_TOKEN is not set"; exit 1)
	cd $(REPO_ROOT) && sbx exec -d $(SBX_NAME) bash -c \
	  "grep -q LOCALSTACK_AUTH_TOKEN /etc/sandbox-persistent.sh 2>/dev/null || \
	   echo 'export LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN)' >> /etc/sandbox-persistent.sh"

exec:           ## Open an interactive shell in the sandbox
	cd $(REPO_ROOT) && sbx exec $(SBX_NAME) bash

ports:          ## List published ports for the sandbox
	cd $(REPO_ROOT) && sbx ports $(SBX_NAME)

rm:             ## Destroy the sandbox (irreversible)
	cd $(REPO_ROOT) && sbx rm $(SBX_NAME)

.PHONY: usage run configure publish-ports inject-token exec ports rm
