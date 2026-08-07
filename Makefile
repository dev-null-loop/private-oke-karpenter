.PHONY: all gitops-push

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
