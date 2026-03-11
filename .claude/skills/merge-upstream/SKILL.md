---
name: merge-upstream
description: Merge an upstream Mastodon release into the theatl-social fork. Usage: /merge-upstream v{version}
---

# Merge Upstream Mastodon Release

Merge a specific upstream Mastodon release tag into the theatl-social fork (`forked-main`).

**Usage:** `/merge-upstream v4.5.7`

The version argument is **required** and must match `vX.Y.Z` format.

## Phase 0: Preflight

Run all checks. Stop and report on any failure.

```bash
# 1. Validate version argument
# Must match vX.Y.Z (e.g., v4.5.7, v4.6.0)
echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' || echo "FAIL: Invalid version format"

# 2. Verify upstream remote
git remote get-url upstream | grep -q 'mastodon/mastodon' || echo "FAIL: upstream remote not configured"

# 3. Fetch upstream tags
git fetch upstream --tags

# 4. Confirm tag exists
git tag -l "$VERSION" | grep -q "$VERSION" || echo "FAIL: Tag $VERSION not found in upstream"

# 5. Working tree must be clean
test -z "$(git status --porcelain)" || echo "FAIL: Working tree is dirty"

# 6. Must be on forked-main
test "$(git branch --show-current)" = "forked-main" || echo "FAIL: Not on forked-main. Please switch: git checkout forked-main"
```

If all checks pass, proceed automatically to Phase 1.

## Phase 1: Branch & Merge

```bash
# Create merge branch
git checkout -b "merge-$VERSION"

# Attempt merge
git merge "$VERSION"
```

After the merge command:

- **If clean (no conflicts):** Report success. Skip Phase 2 and go directly to Phase 3.
- **If conflicts:** List all conflicted files with `git diff --name-only --diff-filter=U`. Show the list to the user and ask whether to proceed with conflict resolution.

## Phase 2: Conflict Resolution

Resolve conflicts using the strategies below. For any conflicted file NOT listed here, flag it for human review — do not guess.

### Auto-resolve: version.rb

**File:** `lib/mastodon/version.rb`

Update all version components to match the upstream release, and set the fork prerelease string:

```ruby
def major
  # Set to upstream major (e.g., 4)
end

def minor
  # Set to upstream minor (e.g., 5)
end

def patch
  # Set to upstream patch (e.g., 7)
end

def default_prerelease
  # Set to 'theatlsocial-YYYYMMDD' using today's date
  'theatlsocial-YYYYMMDD'
end
```

Accept all other upstream changes in this file (method structure, new methods, etc.).

### Auto-resolve: vite.config.mts

**File:** `vite.config.mts`

Accept upstream structural changes but **preserve the fork's CDN_HOST support**. The fork adds CDN_HOST environment variable handling for production asset URLs. Keep that logic intact while accepting any new upstream configuration.

### Auto-resolve: Lock files

**Files:** `Gemfile.lock`, `yarn.lock`

```bash
git checkout --theirs Gemfile.lock
git checkout --theirs yarn.lock
git add Gemfile.lock yarn.lock
```

Accept the upstream versions. If the fork's `Gemfile` or `package.json` has diverged (check with `git diff HEAD -- Gemfile package.json`), remind the user that lock file regeneration is needed post-merge inside the Docker dev container — **never run bundle install or yarn install directly on the host**.

### Auto-resolve: package.json

**File:** `package.json`

```bash
git checkout --theirs package.json
git add package.json
```

The fork has no custom npm dependencies.

### Merge carefully: accounts_controller.rb

**File:** `app/controllers/api/v1/accounts_controller.rb`

This file contains critical fork-specific logic that must be preserved:

1. `include RegistrationHelper` — fork-specific module include
2. `DISABLE_API_REGISTRATIONS` environment variable check that blocks API signups
3. `TRUSTED_REGISTRATION_CLIENT_IDS` bypass allowing specific OAuth apps through
4. `WEB_SIGNUP_URL` / `web_signup_url` method providing a custom signup redirect
5. The structured 403 response body with `signup_url` field

Accept upstream changes to other parts of the controller, but ensure all five items above remain intact and functional.

### Merge carefully: app_sign_up_service.rb

**File:** `app/services/app_sign_up_service.rb`

Preserve the trusted app bypass for the registration block. This allows OAuth apps listed in `TRUSTED_REGISTRATION_CLIENT_IDS` to create accounts via the API even when `DISABLE_API_REGISTRATIONS` is set.

### Preserve entirely: registration_helper.rb

**File:** `app/helpers/registration_helper.rb` (if it exists)

This is a fork-only file. If it appears in the conflict list, it should be preserved entirely — it has no upstream equivalent.

### Unknown conflicts

For any file not listed above: **stop and show the conflict to the user**. Present the conflicted hunks and ask how to resolve. Do not guess.

### Gate

After all resolutions, show the user a summary of every resolution made. Wait for approval before running `git add` and committing.

## Phase 3: Validation

Run these checks and report results:

### 3.1 Version string

```bash
# Verify the version methods produce the expected output
grep -A2 'def major' lib/mastodon/version.rb
grep -A2 'def minor' lib/mastodon/version.rb
grep -A2 'def patch' lib/mastodon/version.rb
grep -A2 'def default_prerelease' lib/mastodon/version.rb
```

Confirm the version string will produce `X.Y.Z-theatlsocial-YYYYMMDD`.

### 3.2 Rubocop

```bash
bin/docker-rubocop
```

**CRITICAL:** Never run `rubocop` directly — always use the containerized wrapper.

On failure: report the errors to the user. Do **not** auto-fix with `--autocorrect`. Let the user decide how to proceed.

### 3.3 HAML Lint

```bash
bin/docker-haml-lint
```

**CRITICAL:** Never run `haml-lint` directly — always use the containerized wrapper.

On failure: report errors, let the user decide.

### 3.4 delegated-events check

```bash
grep -r 'delegated-events' package.json yarn.lock
```

This must return no results. The fork uses `@rails/ujs` instead of `delegated-events`. If found, it was re-introduced by the upstream merge and must be removed.

### 3.5 Year-boundary reminder

If the current month is December or January, remind the user:

> Check `spec/models/annual_reports_spec.rb` for hardcoded year literals that may need updating.

### Gate

Report pass/fail for each check. Pause and ask user to proceed.

## Phase 4: PR & Tag

### 4.1 Push

```bash
git push -u origin "merge-$VERSION"
```

If SSH fails, fall back to HTTPS:

```bash
git push -u https://github.com/theatl-social/theconnector.git "merge-$VERSION"
```

### 4.2 Create PR

**Confirm with user before creating.** Then:

```bash
gh pr create \
  --base forked-main \
  --title "Merge upstream Mastodon $VERSION" \
  --body "$(cat <<'PREOF'
## Summary
- Merge upstream Mastodon $VERSION into forked-main
- Updated fork version to $VERSION_STRING

## Upstream changelog
https://github.com/mastodon/mastodon/releases/tag/$VERSION

## Fork-specific conflict resolutions
$CONFLICT_SUMMARY

## Validation
- [x] rubocop passed
- [x] haml-lint passed
- [x] Version string correct
- [x] No re-introduction of delegated-events
- [ ] CI passes

## Post-merge
- Tag as `$TAG_NAME` after CI passes
PREOF
)"
```

Where:

- `$VERSION` = the upstream tag (e.g., `v4.5.7`)
- `$VERSION_STRING` = `4.5.7-theatlsocial-YYYYMMDD`
- `$TAG_NAME` = `v4.5.7-theatlsocial-YYYYMMDD`
- `$CONFLICT_SUMMARY` = bullet list of each conflicted file and how it was resolved

### 4.3 Post-PR reminders

After creating the PR, remind the user:

1. Wait for CI to pass on the PR
2. Review and merge the PR
3. After merging, tag the merge commit on `forked-main`:
   ```bash
   git checkout forked-main
   git pull
   git tag "$TAG_NAME"
   git push origin "$TAG_NAME"
   ```
