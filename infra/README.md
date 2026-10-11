# infra (reference)

Applications here are **not** auto-applied by the root app (the root only
recurses `applications/`). They're kept as ready-to-adopt references.

`ingress-nginx.yaml` — installs ingress-nginx as NodePorts `32080`/`32443`.
If ingress-nginx is already installed manually, remove that install first
(`kubectl delete -f <the static manifest>`) before moving the file into
`applications/`, or ArgoCD and the manual objects will fight.
