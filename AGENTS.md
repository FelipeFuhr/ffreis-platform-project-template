# Agent Context

**This repo:** `ffreis-platform-project-template` — public-safe website project
template with site-data contract validation, quality checks, and GitHub Actions OIDC
deployment workflows. Starting point for new website projects.

## Non-obvious facts

- **Compiler is configured via env/secrets, not hardcoded.** `WEBSITE_COMPILER`,
  `WEBSITE_COMPILER_CLI`, `WEBSITE_COMPILER_REPO` control which compiler is used.
  This keeps the template generic while remaining compatible with the fleet compiler.

- **`src/data/site.contract.yaml` is the schema source of truth** for this template.
  Content repos validate against it. Do not remove or rename it.

- **DynamoDB lock management** via `make lock-cleanup` and `make lock-info`. If a
  Terraform apply is interrupted, locks may need manual cleanup before retrying.

- **OIDC for credentials** — no static AWS keys in secrets. Temporary credentials
  only.

- **`src/data/` structure:**
  - `site.yaml` — stable site-wide config
  - `site.contract.yaml` — JSON Schema for data validation
  - `site.d/` — per-section overlays

## Structure

```
src/
  assets/        ← CSS, JS, images, fonts
  data/          ← site.yaml, site.contract.yaml, site.d/
  templates/     ← layout/, partials/, pages/
sanity/          ← optional sanity-check fixtures
.github/workflows/
```

## Build/test

```bash
make check       # full local quality bundle
```
