# AGENTS.md

## Purpose

This repository is the canonical source for our reusable agent skills.

- Skills are authored and versioned here.
- Changes are pushed to GitHub.
- Consumers install skills from the GitHub repo using Vercel's Skills CLI (`npx skills add ...`).

## Repository Contract

Use this repo as a skills catalog, not as a general app/service codebase.

- Each skill lives in `skills/<skill-name>/`.
- Every skill directory must include `SKILL.md`.
- `SKILL.md` must contain YAML frontmatter with at least:
  - `name`
  - `description`
- Optional skill assets go inside the same skill folder (for example `scripts/`, `references/`, `assets/`).

## Workflow

1. Create or update skill files under `skills/`.
2. Validate structure and metadata consistency.
3. Commit and push to GitHub.
4. Install from GitHub with the Skills CLI:
   - `npx skills add <owner>/<repo>`
   - `npx skills add <owner>/<repo> --list`
   - `npx skills add <owner>/<repo> --skill <skill-name> -a <agent>`

## Local Sync Helpers

This repo includes helper scripts for importing local skills:

- `scripts/copy-claude-skills.sh`
- `scripts/copy-codex-skills.sh`

Use these scripts to copy selected skills from local agent directories into this repository before committing.

## References

- [skills.sh](https://skills.sh)
- [Skills docs](https://skills.sh/docs)
- [Vercel Skills CLI repository](https://github.com/vercel-labs/skills)
