# PA-015: OpenRouter model tooling — continuation notes

## Where this came from

Originally developed on branch `feature/PA-015_python_tooling` in the **private**
`git@github.com:qalti/aiqa.git` repo (5 commits, tip `348b8b6`, last touched 2026-03-31).
That work never got a PR against the public repo — `scripts/` on public `main` had none
of it before this branch.

Ported here verbatim via `git diff origin/main...feature/PA-015_python_tooling` from the
private repo, applied on top of public `main` — the 5 shared files it touches
(`.gitignore`, `Makefile`, `DEVELOPER.md`, `README.md`, `scripts/build_qalti.py`) were
byte-identical between private main and public main at the time, so the patch applied
with zero conflicts. Nothing was rewritten or reconciled by hand.

## What's included (staged on `feature/openrouter_model_tooling`, uncommitted)

- `scripts/check_model_availability.py` (388 lines) — OpenRouter model discovery /
  availability checking
- `scripts/update_open_router_models.py` (483 lines) — updates the tracked model list
- `scripts/monitor_openrouter.py` (35 lines)
- `pyproject.toml` (new) — Python 3.10+ requirement, tooling config
- `.env.example` (new, force-added — public `.gitignore` has a blanket `.env*` rule that
  would otherwise exclude it, same as in the private repo)
- Makefile: switched from black/flake8 to `ruff` for format/lint, added `SCRIPTS_DIR`
- `DEVELOPER.md` / `README.md`: Python 3.10+ requirement noted, minor doc formatting
- `scripts/build_qalti.py`: import reordering, minor formatting only

## What's NOT done yet

- **Not committed.** Files are staged (`git status` on `feature/openrouter_model_tooling`
  shows them all as new/modified) but no commit was made.
- **Not run.** The scripts haven't been executed against this checkout — `make venv`
  needs to install `ruff requests python-dotenv` first, and the OpenRouter scripts need
  a real `OPENROUTER_API_KEY` to test against.
- **No PR opened.** Unlike PA-016 (dateformatter/retry work), which has an active PR
  history on public `qalti/qalti` (#1 merged, #2/#3 closed duplicates, #4 open at
  `feature/dateformatter_centralization`), this OpenRouter tooling has no PR yet — this
  branch would be the first.
- No verification that these scripts still make sense against whatever OpenRouter model
  catalogue looks like now vs. late March.

## Next steps

1. `cd ~/Development/qalti && git commit` the staged changes (blocked by an auto-mode
   permission gate during the port — needs a manual commit).
2. `make venv && make format && make lint` to confirm the ruff migration works cleanly.
3. Smoke-test `check_model_availability.py` / `update_open_router_models.py` against a
   live `OPENROUTER_API_KEY`.
4. Push to your fork and open a PR against `qalti/qalti` `main`, same pattern as PR #4.

## Source reference (before the private repo is deleted)

- Private branch: `feature/PA-015_python_tooling`, tip `348b8b67e9f3ef85131dd94afdeb8702936a7c4c`
- Full 5-commit list:
  - `348b8b6` Refactor OpenRouter scripts: fix CLI/analysis structure, improve exception handling
  - `e5d7e62` feat: standardize OpenRouter API key usage, improve CLI and docs
  - `3552b5a` docs: require Python 3.10+ and improve setup clarity
  - `141a2bb` review fixes
  - `dba92d7` feat(scripts): add OpenRouter model discovery and availability checking tools
