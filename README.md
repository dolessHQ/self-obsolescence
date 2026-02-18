# self-obsolescence

Central repository for reusable agent skills that are distributed through GitHub and installed with Vercel's Skills CLI.

## What This Directory Is For

This folder is the source of truth for shared skills.

- Author and maintain skills in this repo.
- Push updates to GitHub.
- Install/update those skills in agent environments via `npx skills add ...`.

## Structure

```text
.
├── skills/
│   └── <skill-name>/
│       └── SKILL.md
└── scripts/
    ├── copy-claude-skills.sh
    └── copy-codex-skills.sh
```

- `skills/`: canonical skill definitions that are meant to be published.
- `scripts/`: helper scripts for copying local skills into this repository.

## Authoring Workflow

1. Add or update a skill in `skills/<skill-name>/SKILL.md`.
2. Keep YAML frontmatter (`name`, `description`) accurate.
3. Commit and push changes to GitHub.
4. Install from GitHub using Skills CLI.

## Install With Vercel Skills

Use the Skills CLI with your GitHub repo:

```bash
npx skills add <owner>/<repo> --list
npx skills add <owner>/<repo> --skill <skill-name> -a codex
```

Examples:

```bash
# Install all skills for Codex + Claude Code
npx skills add <owner>/<repo> --all -a codex -a claude-code

# Install one skill for Codex
npx skills add <owner>/<repo> --skill fetch-rules -a codex
```

## Useful Local Helpers

```bash
scripts/copy-claude-skills.sh
scripts/copy-codex-skills.sh
```

Both scripts accept optional skill names as arguments to copy specific skills.

## References

- [skills.sh](https://skills.sh)
- [skills.sh docs](https://skills.sh/docs)
- [vercel-labs/skills](https://github.com/vercel-labs/skills)
