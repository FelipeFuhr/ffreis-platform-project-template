# Public Template Boundary

This repository is intended to become a public website template.

## Public Core

The public core includes:

- website source structure under `src/`
- site contract and layered data model
- CI and deploy workflow examples
- repository hygiene and quality tooling

## Private Adapters

Keep these outside the public template:

- shared infrastructure outputs
- private workflow repositories
- bootstrap tooling
- private Terraform modules
- account-specific bucket, role, and distribution names

## Recommended Integration Pattern

1. create the website repository from this template
2. provision infrastructure in a separate private repository
3. feed the deploy role, bucket, and CDN identifiers into GitHub variables and secrets
4. keep the website repository generic and reusable