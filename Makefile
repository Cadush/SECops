.PHONY: up down scan status pull vault-setup sops-setup clear report build scan-docker

up:
	docker compose up -d
	@echo ""
	@echo "SonarQube:        http://localhost:9000 (admin/admin)"
	@echo "Dependency-Track: http://localhost:8080"
	@echo "DefectDojo:       http://localhost:8888 (admin/admin)"
	@echo "Vault:            http://localhost:8200 (token: secops-dev-token)"
	@echo "ZAP API:          http://localhost:8090"

down:
	docker compose down

status:
	docker compose ps

pull:
	@echo "Baixando imagens das ferramentas..."
	docker compose pull
	docker pull zricethezav/gitleaks:latest
	docker pull trufflesecurity/trufflehog:latest
	docker pull semgrep/semgrep:latest
	docker pull cytopia/bandit
	docker pull securego/gosec
	docker pull presidentbeef/brakeman
	docker pull aquasec/trivy:latest
	docker pull anchore/syft:latest
	docker pull anchore/grype:latest
	docker pull ghcr.io/google/osv-scanner:latest
	docker pull hadolint/hadolint
	docker pull goodwithtech/dockle:latest
	docker pull bridgecrew/checkov
	docker pull checkmarx/kics:latest
	docker pull projectdiscovery/nuclei:latest
	docker pull secfigo/nikto
	docker pull paoloo/sqlmap
	docker pull sonarsource/sonar-scanner-cli
	@echo "Todas as imagens baixadas!"

scan:
	@test -n "$(REPO)" || (echo "Uso: make scan REPO=<url_ou_path> [DAST=<url>] [IMAGE=<docker_image>]" && exit 1)
	bash scripts/scan.sh $(REPO) $(if $(DAST),--dast $(DAST),) $(if $(IMAGE),--image $(IMAGE),)

build:
	docker build -f Dockerfile.scanner -t secops-scanner .
	@echo "Imagem secops-scanner construida com sucesso"

scan-docker:
	@test -n "$(REPO)" || (echo "Uso: make scan-docker REPO=<path>" && exit 1)
	@mkdir -p reports
	docker run --rm -v "$(shell realpath $(REPO)):/src" -v "$(shell pwd)/reports:/reports" secops-scanner
	@echo ""
	@echo "Abra: xdg-open $$(ls -td reports/*/ | head -1)report.html"

scan-remote:
	@test -n "$(REPO)" || (echo "Uso: make scan-remote REPO=<path> SERVER=<ip>" && exit 1)
	@test -n "$(SERVER)" || (echo "Uso: make scan-remote REPO=<path> SERVER=<ip>" && exit 1)
	bash scripts/scan-remote.sh $(REPO) --server $(SERVER)

dep-audit:
	@test -n "$(REPO)" || (echo "Uso: make dep-audit REPO=<path> [SNYK_TOKEN=<token>]" && exit 1)
	bash scripts/dep-audit.sh $(REPO) $(if $(SNYK_TOKEN),--snyk-token $(SNYK_TOKEN),)

# Build da imagem dep-audit para CI/CD
dep-audit-build:
	docker build -t secops/dep-audit:latest -f Dockerfile.dep-audit .

# Rodar dep-audit via container (para integrar em pipelines)
dep-audit-docker:
	@test -n "$(REPO)" || (echo "Uso: make dep-audit-docker REPO=<path> [SNYK_TOKEN=<token>] [FAIL_ON=high]" && exit 1)
	docker run --rm \
		-v $(shell realpath $(REPO)):/src \
		-v $(shell pwd)/reports:/reports \
		$(if $(SNYK_TOKEN),-e SNYK_TOKEN=$(SNYK_TOKEN),) \
		secops/dep-audit:latest /src \
		$(if $(SNYK_TOKEN),--snyk-token $(SNYK_TOKEN),) \
		$(if $(FAIL_ON),--fail-on $(FAIL_ON),)

vault-setup:
	bash scripts/vault.sh setup

sops-setup:
	bash scripts/sops.sh setup

ollama-setup:
	bash scripts/setup-ollama.sh

ollama-up:
	docker compose -f docker-compose.ollama.yml up -d
	@echo "Ollama rodando em http://localhost:11434"
	@echo "Baixar modelo: docker compose -f docker-compose.ollama.yml exec ollama ollama pull qwen2.5-coder:14b"

legacy-doc:
	@test -n "$(REPO)" || (echo "Uso: make legacy-doc REPO=<path> [PROVIDER=openai|ollama|bedrock] [MODEL=gpt-4o-mini]" && exit 1)
	OPENAI_API_KEY=$(OPENAI_API_KEY) LEGACY_DOC_PROVIDER=$(or $(PROVIDER),openai) LEGACY_DOC_MODEL=$(or $(MODEL),gpt-4o-mini) \
		bash scripts/legacy-doc.sh $(REPO) $(if $(OUTPUT),--output $(OUTPUT),)

clear:
	bash scripts/clear.sh

report:
	@test -n "$(DIR)" || (echo "Uso: make report DIR=reports/<timestamp>" && exit 1)
	bash scripts/report-html.sh $(DIR)
