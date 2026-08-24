.PHONY: all init fmt plan apply destroy clean gitops-push gitops-bootstrap gitops-patch-kpo-ssh-key demand-small demand-single-node demand-delete

all: init plan

init:
	terraform init -upgrade
plan:
	terraform plan
apply:
	terraform apply -auto-approve
destroy:
	terraform destroy -auto-approve -var='enable_kubeconfigs=false'
clean:
	rm -v -rf .terraform

gitops-push:
	@test -n "$(MSG)" || (echo 'Usage: make gitops-push MSG="..."' && exit 1)
	git add gitops/c
	git commit -m "$(MSG)"
	git push origin main

gitops-bootstrap:
	@kubectl get crd applications.argoproj.io >/dev/null 2>&1 || (echo 'Argo CD CRD applications.argoproj.io is missing. Install Argo CD first, then re-run make gitops-bootstrap.' && exit 1)
	kubectl apply -k gitops/c

demand-small:
	printf '%s\n' \
	  'apiVersion: apps/v1' \
	  'kind: Deployment' \
	  'metadata:' \
	  '  name: inflate' \
	  '  namespace: default' \
	  'spec:' \
	  '  replicas: 1' \
	  '  selector:' \
	  '    matchLabels:' \
	  '      app: inflate' \
	  '  template:' \
	  '    metadata:' \
	  '      labels:' \
	  '        app: inflate' \
	  '    spec:' \
	  '      terminationGracePeriodSeconds: 0' \
	  '      containers:' \
	  '      - name: inflate' \
	  '        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7' \
	  '        resources:' \
	  '          requests:' \
	  '            cpu: "500m"' \
	  '            memory: "512Mi"' | kubectl apply -f -

demand-single-node:
	printf '%s\n' \
	  'apiVersion: apps/v1' \
	  'kind: Deployment' \
	  'metadata:' \
	  '  name: inflate' \
	  '  namespace: default' \
	  'spec:' \
	  '  replicas: 1' \
	  '  selector:' \
	  '    matchLabels:' \
	  '      app: inflate' \
	  '  template:' \
	  '    metadata:' \
	  '      labels:' \
	  '        app: inflate' \
	  '    spec:' \
	  '      terminationGracePeriodSeconds: 0' \
	  '      nodeSelector:' \
	  '        karpenter.sh/nodepool: karpenter-general' \
	  '      containers:' \
	  '      - name: inflate' \
	  '        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7' \
	  '        resources:' \
	  '          requests:' \
	  '            cpu: "1500m"' \
	  '            memory: "2Gi"' | kubectl apply -f -

demand-delete:
	kubectl delete deployment inflate --ignore-not-found

gitops-patch-kpo-ssh-key:
	@test -n "$$(sed -n 's/^[[:space:]]*ssh_public_key[[:space:]]*=[[:space:]]*\"\\(.*\\)\"$$/\\1/p' karpenter.auto.tfvars | head -n 1)" || (echo 'Usage: add ssh_public_key = "ssh-ed25519 AAAA..." inside the karpenter block in local karpenter.auto.tfvars' && exit 1)
	@key="$$(sed -n 's/^[[:space:]]*ssh_public_key[[:space:]]*=[[:space:]]*\"\\(.*\\)\"$$/\\1/p' karpenter.auto.tfvars | head -n 1)"; \
	kubectl patch ocinodeclass -n karpenter karpenter-general --type merge -p "$$(printf '{\"spec\":{\"sshAuthorizedKeys\":[%s]}}' "$$(printf '%s' "$$key" | jq -R -s '.')")"
