# Security

## What is in scope

This repository is **desired state for a cluster**: manifests, Helm values, ArgoCD Applications, alert rules and runbooks. A problem
here means something like:

- a manifest that would expose a service to the internet when its access policy says otherwise;
- a workflow or check that can be made to pass while doing nothing (the estate has found two of these and treats them as security bugs,
  not style);
- a secret, key or credential committed by mistake — `check-repo-hygiene` in `homelab-context` fails the build on the shapes it knows,
  and it is not exhaustive.

## What is not in scope

The household network, the router, the hosts and the DNS zones are **not** in this repository, and probing them is out of scope: they
serve one household, not a service. Anything you find there is welcome as a report, not as a test.

## Reporting

Open an issue in this repository, marked clearly, and say if it is a live exposure — that is the channel that exists today. Please do not
paste a working exploit or a credential into it.

A dedicated address (`security@bismigel.dev`) is being set up; it is written here only once it delivers, because an address that bounces
silently is worse than none.

Expect an answer from one person, not a team: this is a homelab. What you will get is an honest reply about whether it is fixed, being
fixed, or accepted with the reason — the estate records accepted risks in its own ADRs, including one about a disk image in this
repository's history that contained a host private key.
