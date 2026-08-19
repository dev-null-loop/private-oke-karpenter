.PHONY: all init fmt plan apply destroy clean gitops-push gitops-bootstrap gitops-patch-kpo-ssh-key

all: init plan

init:
	terraform init -upgrade
plan:
	terraform plan
apply:
	terraform apply -auto-approve
destroy:
	terraform destroy -auto-approve
clean:
	rm -v -rf .terraform

gitops-push:
	@test -n "$(MSG)" || (echo 'Usage: make gitops-push MSG="..."' && exit 1)
	git add gitops/c
	git commit -m "$(MSG)"
	git push origin main

gitops-bootstrap:
	kubectl apply -k gitops/c

gitops-patch-kpo-ssh-key:
	@test -n "$$(sed -n 's/^[[:space:]]*ssh_public_key[[:space:]]*=[[:space:]]*\"\\(.*\\)\"$$/\\1/p' karpenter.auto.tfvars | head -n 1)" || (echo 'Usage: add ssh_public_key = "ssh-ed25519 AAAA..." inside the karpenter block in local karpenter.auto.tfvars' && exit 1)
	@key="$$(sed -n 's/^[[:space:]]*ssh_public_key[[:space:]]*=[[:space:]]*\"\\(.*\\)\"$$/\\1/p' karpenter.auto.tfvars | head -n 1)"; \
	kubectl patch ocinodeclass -n karpenter karpenter-general --type merge -p "$$(printf '{\"spec\":{\"sshAuthorizedKeys\":[%s]}}' "$$(printf '%s' "$$key" | jq -R -s '.')")"
