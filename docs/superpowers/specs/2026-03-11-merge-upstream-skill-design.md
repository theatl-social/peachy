# Design: merge-upstream Claude Code Skill

**Date:** 2026-03-11
**Status:** Implemented
**Location:** `.claude/skills/merge-upstream/SKILL.md`

> Naming updated 2026-07-28 for the theconnector → peachy rebrand: the integration
> branch is `main` (not `forked-main`), the prerelease string is `peachy-{date}` (not
> `theatlsocial-{date}`), and the fork remote is `theatl-social/peachy`. The 2026-03-11
> date above is the original design date and is left as-is.

## Overview

A Claude Code skill that automates merging new upstream Mastodon releases into the peachy fork. Invoked with `/merge-upstream v{version}`. Automates mechanical steps, pauses at gates for human review, and embeds fork-specific conflict resolution knowledge.

## Invocation

```
/merge-upstream v4.5.7
```

Takes a single required argument: the upstream Mastodon release tag (e.g., `v4.5.7`).

## Skill File Structure

The skill file at `.claude/skills/merge-upstream/SKILL.md` uses YAML frontmatter:

```yaml
---
name: merge-upstream
description: Merge an upstream Mastodon release into the peachy fork. Usage: /merge-upstream v{version}
---
```

## Phases

### Phase 0: Preflight

**Actions (automated):**

- Validate version argument matches `vX.Y.Z` format
- Verify `upstream` remote exists and points to `mastodon/mastodon`
- Run `git fetch upstream --tags`
- Confirm the tag exists in upstream
- Check working tree is clean (`git status --porcelain` is empty)
- Confirm current branch is `main`. If not, **stop and ask the user to switch** — do not auto-switch, as the user may have in-progress work on the current branch

**Gate:** Auto-proceed if all checks pass. Stop and report on any failure.

### Phase 1: Branch & Merge

**Actions (automated):**

- Create branch: `git checkout -b merge-v{version}`
- Attempt merge: `git merge v{version}`
- Report conflict summary (list of conflicted files)

**Gate:**

- **If merge is clean (no conflicts):** Report success, skip Phase 2, proceed directly to Phase 3.
- **If conflicts exist:** Pause. Show conflict list, ask user whether to proceed with resolution.

### Phase 2: Conflict Resolution

**Auto-resolve known fork files:**

| File                        | Strategy                                                                                                                                                                                            |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/mastodon/version.rb`   | Take upstream `major`/`minor`/`patch`, set `default_prerelease` to `'peachy-{date}'` (see Version Bump Logic)                                                                                       |
| `vite.config.mts`           | Keep fork's CDN_HOST additions, accept upstream structural changes                                                                                                                                  |
| `Gemfile.lock`, `yarn.lock` | Accept upstream version (`git checkout --theirs`). Lock file regeneration is a human post-step if the fork's Gemfile/package.json diverges — run inside the Docker dev container, never on the host |
| `package.json`              | Take upstream (fork has no custom dependencies)                                                                                                                                                     |

**Merge carefully (preserve fork logic):**

| File                                                | What to preserve                                                                                                                                                                                               |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/controllers/api/v1/accounts_controller.rb`     | `include RegistrationHelper`, `DISABLE_API_REGISTRATIONS` check, `TRUSTED_REGISTRATION_CLIENT_IDS` bypass, `WEB_SIGNUP_URL` / `web_signup_url` method, and the structured 403 response with `signup_url` field |
| `app/services/app_sign_up_service.rb`               | Trusted app bypass for registration block                                                                                                                                                                      |
| `app/helpers/registration_helper.rb` (if it exists) | Entire file is fork-specific — preserve completely                                                                                                                                                             |

**Flag for human review:** Any conflicted file not in the known list above.

**Gate:** Pause. Show all resolutions for user review before committing.

### Phase 3: Validation

**Actions (automated):**

- Verify version string in `lib/mastodon/version.rb` produces correct output
- Run `bin/docker-rubocop` (containerized — never run rubocop directly)
  - On failure: report the errors to the user. Do **not** auto-fix — let the user decide whether to run `--autocorrect` or fix manually
- Run `bin/docker-haml-lint` (containerized — never run haml-lint directly)
  - On failure: report errors, same approach as rubocop
- Check that `delegated-events` hasn't been re-introduced in `package.json`
- Remind user to check `annual_reports_spec.rb` if merging near a year boundary (Dec/Jan) — look for hardcoded year literals

**Gate:** Pause. Report results (pass/fail for each check), ask user to proceed.

### Phase 4: PR & Tag

**Actions (automated with confirmation):**

- Push branch to origin
- Create PR to `main` with structured body (see PR Template below)

**Gate:** Confirm before creating PR.

**Post-PR reminders:**

1. Wait for CI to pass on the PR
2. Merge the PR
3. Tag the merge commit: `v{version}-peachy-{date}`

## Version Bump Logic

Update `lib/mastodon/version.rb` — all three version components must be updated, not just patch:

- `major` → match upstream release major
- `minor` → match upstream release minor
- `patch` → match upstream release patch
- `default_prerelease` → `'peachy-{date}'` where `{date}` is `YYYYMMDD` of the merge day

Example for `v4.6.0` merged on 2026-03-15:

```ruby
def major
  4
end

def minor
  6
end

def patch
  0
end

def default_prerelease
  'peachy-20260315'
end
```

## PR Template

**Title:** `Merge upstream Mastodon v{version}`

**Body:**

```markdown
## Summary

- Merge upstream Mastodon v{version} into main
- Updated fork version to {version}-peachy-{date}

## Upstream changelog

[Link to github.com/mastodon/mastodon/releases/tag/v{version}]

## Fork-specific conflict resolutions

- [List of files that had conflicts and how they were resolved]

## Validation

- [ ] rubocop passed
- [ ] haml-lint passed
- [ ] Version string correct
- [ ] No re-introduction of delegated-events
- [ ] CI passes

## Post-merge

- Tag as `v{version}-peachy-{date}` after CI passes
```

Where `{date}` is the merge day in `YYYYMMDD` format.

## Key Constraints

- **Never run Ruby tooling directly** — always use `bin/docker-rubocop`, `bin/docker-haml-lint`
- **Push via HTTPS** if SSH fails: `git push https://github.com/theatl-social/peachy.git`
- **Pre-commit hooks** use husky + lint-staged; avoid `--no-verify`
- **Fork uses `@rails/ujs`** not `delegated-events` — verify this isn't re-introduced
