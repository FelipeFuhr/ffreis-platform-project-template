# Layered Site Data

Put frequently changing site data in this directory.

The website compiler should merge these files on top of `src/data/site.yaml` at build time.

Typical uses:

- campaigns
- pricing
- schedules
- testimonials
- feature flags for content sections

Keep stable global settings in `src/data/site.yaml` and evolving content in this directory.