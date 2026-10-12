# Bootstrap

ArgoCD can't install itself, so this one step is applied by hand (or via
`bakuran-infra/scripts/bootstrap-argocd.sh`). Everything else is reconciled.

1. `kubectl create ns argocd`
2. `kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
3. Create the repo secret (`repo-bakuran-gitops`, SSH key from Bitwarden)
4. `kubectl -n argocd apply -f bootstrap/root-app.yaml`
