# Shortcuts for the commands in CLAUDE.md / README.md. `make` alone lists them.
.DEFAULT_GOAL := help
.PHONY: help setup db server css test lint security check deploy deploy-status rollback logs console

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }'

build: ## Start PostgreSQL, install gems, prepare the database
	docker compose up -d db
	bin/setup --skip-server

up: db ## Run the Rails server
	bin/rails s

css: ## Rebuild the admin CSS on change
	bin/rails tailwindcss:watch

test: db ## Run the full spec suite
	bundle exec rspec

lint: ## Rubocop
	bin/rubocop

security: ## Brakeman scan
	bundle exec brakeman -q --no-pager

check: lint security test ## Lint, security scan and specs

deploy: ## Build HEAD on the server and roll it out
	bin/deploy

deploy-status: ## Pods, running image, images kept on the server
	bin/deploy status

rollback: ## Roll back: make rollback SHA=<short sha>
	@test -n "$(SHA)" || { echo "usage: make rollback SHA=<short sha>"; exit 1; }
	bin/deploy rollback $(SHA)

logs: ## Tail production web logs
	ssh $$(sed -n 's/^DEPLOY_HOST=//p' .env | tail -1) "kubectl -n village logs deploy/web -f --tail=100"

console: ## Rails console on production
	ssh -t $$(sed -n 's/^DEPLOY_HOST=//p' .env | tail -1) "kubectl -n village exec -it deploy/web -- bin/rails console"
