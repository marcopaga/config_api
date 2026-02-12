# Renovate Configuration Guide

This document explains the Renovate dependency automation setup for ConfigApi and how to manage it.

## Overview

Renovate automatically creates pull requests to update dependencies when:
- New versions are available
- Security vulnerabilities are discovered
- Lock files need maintenance

**Auto-merge is enabled** for low-risk updates when all CI tests pass.

## Configuration File

The configuration is in `renovate.json` at the repository root.

## Auto-Merge Rules

### ✅ Automatically Merged (when tests pass)

The following updates are auto-merged if all CI checks pass:

1. **Hex Package Patches & Minors**
   - `jason` 1.4.0 → 1.4.1 ✓ (patch)
   - `plug` 1.15.0 → 1.16.0 ✓ (minor)
   - Requires: All tests passing

2. **Docker Image Patches**
   - `postgres:14.10-alpine` → `14.11-alpine` ✓
   - Minor/major versions require manual review

3. **Development Dependencies**
   - Test-only packages auto-merge more aggressively
   - Lower risk since they don't affect production

4. **GitHub Actions Patches**
   - `actions/checkout@v4.2.1` → `v4.2.2` ✓
   - Actions are pinned to SHA digests for security
   - Minor/major versions require manual review

5. **Lock File Maintenance**
   - Weekly automatic updates to `mix.lock`
   - Keeps dependencies fresh without version bumps

### ⚠️ Manual Review Required

These updates will NOT auto-merge and require your approval:

1. **Major Version Updates**
   - `plug` 1.x → 2.x ❌
   - Breaking changes likely
   - Labeled: `dependencies`, `major-update`

2. **EventStore Ecosystem**
   - `eventstore`, `postgrex` ❌
   - Critical for event sourcing core
   - Grouped together for testing
   - Labeled: `EventStore ecosystem`

3. **HTTP Stack Updates**
   - `plug_cowboy`, `plug`, `cowboy` ❌
   - Grouped for compatibility testing
   - Labeled: `HTTP stack`

4. **Runtime Version Changes**
   - Erlang/Elixir in `.tool-versions` ❌
   - Monthly schedule
   - Labeled: `runtime`

5. **Security Vulnerabilities**
   - Major version updates for security ❌
   - Immediate attention required
   - Labeled: `security`

## Safety Mechanisms

### Required Status Checks

Renovate will **only** auto-merge if these CI jobs pass:
- ✅ **Build and test** - Unit tests (102 tests)
- ✅ **Integration tests** - HTTP endpoint testing
- ✅ **Contract Tests** - API specification validation

If any check fails, the PR remains open for manual review.

### Rate Limiting

To prevent PR spam:
- **Max 5 concurrent PRs** - Won't flood your inbox
- **Max 2 PRs per hour** - Controlled rollout
- **Max 3 branch updates** - Limits git churn

### Stability Period

- **3-day stability window** - Waits for package to stabilize
- Avoids immediately pulling in broken releases
- Can be adjusted per package if needed

### Schedule

- **Default schedule**: Monday mornings at 3 AM UTC
- Avoids mid-week disruption
- Security updates: Immediate (bypass schedule)

## GitHub Branch Protection

For auto-merge to work, configure these branch protection rules on `main`:

1. **Settings → Branches → Branch protection rules → Add rule**

2. **Configure:**
   ```
   Branch name pattern: main

   ✅ Require status checks to pass before merging
   ✅ Require branches to be up to date before merging

   Required status checks:
     - Build and test
     - Integration tests
     - Contract Tests

   ⚠️ DO NOT enable "Require pull request reviews before merging"
      (This would block auto-merge)

   ✅ Allow auto-merge
   ```

3. **Save changes**

## Dependency Groups

Renovate groups related packages for easier review:

### EventStore Ecosystem
- `eventstore`
- `postgrex`

**Why grouped**: These must be compatible for event sourcing to work.

### HTTP Stack
- `plug_cowboy`
- `plug`
- `cowboy`

**Why grouped**: Web server stack must be compatible.

### JSON/Schema Libraries
- `jason`
- `ex_json_schema`
- `yaml_elixir`

**Why grouped**: Schema validation dependencies work together.

## Managing Renovate PRs

### Review a PR

1. Click on the Renovate PR
2. Review the changelog/release notes (linked in PR description)
3. Check CI status - all checks must be green
4. Review code changes if major version

### Approve Auto-Merge PR

If CI passes and you're satisfied:
```bash
# Auto-merge will trigger automatically when CI passes
# No action needed!
```

### Manually Merge a PR

If you want to merge before auto-merge:
```bash
gh pr merge <PR_NUMBER> --squash
```

### Close/Ignore a PR

If you don't want a specific update:

1. Close the PR
2. Add to `renovate.json`:
   ```json
   "packageRules": [
     {
       "matchPackageNames": ["package-name"],
       "enabled": false
     }
   ]
   ```

### Pin a Version

To prevent updates to a specific package:
```json
"packageRules": [
  {
    "matchPackageNames": ["eventstore"],
    "matchCurrentVersion": "1.4.8",
    "enabled": false
  }
]
```

## Monitoring

### Renovate Dashboard

Enable the Renovate dashboard in GitHub:
- Shows all pending updates
- Displays dependency graph
- Highlights security issues

### Notifications

Configure GitHub notifications for:
- `dependencies` label - All Renovate PRs
- `security` label - Security updates
- `major-update` label - Breaking changes

### Failed Auto-Merge

If auto-merge fails:
1. Check CI logs in the PR
2. Fix the issue (update code if needed)
3. CI will re-run automatically
4. Auto-merge will retry if CI passes

## Troubleshooting

### "Auto-merge not working"

**Check:**
1. Branch protection configured correctly?
2. All required status checks passing?
3. "Allow auto-merge" enabled in repo settings?

### "Too many Renovate PRs"

**Solutions:**
1. Adjust rate limits in `renovate.json`:
   ```json
   "prConcurrentLimit": 3,
   "prHourlyLimit": 1
   ```

2. Change schedule to less frequent:
   ```json
   "schedule": ["before 3am on the first day of the month"]
   ```

### "Security vulnerability not auto-merging"

**Expected behavior**: Security updates for major versions require manual review.

**Reason**: Major versions may have breaking changes that need code updates.

**Action**: Review the PR, update code if needed, and merge manually.

### "EventStore update broke tests"

1. Close the Renovate PR
2. Check EventStore changelog for breaking changes
3. Update code to handle changes
4. Manually update dependencies:
   ```bash
   mix deps.update eventstore
   mix test
   ```
5. Commit changes

## Customizing Renovate

### Add a New Package Group

```json
"packageRules": [
  {
    "description": "Group monitoring dependencies",
    "matchPackageNames": ["telemetry", "telemetry_metrics"],
    "groupName": "monitoring",
    "automerge": true
  }
]
```

### Change Auto-Merge Behavior

**Disable auto-merge globally:**
```json
"packageRules": [
  {
    "matchPackageNames": ["*"],
    "automerge": false
  }
]
```

**Enable auto-merge for specific package:**
```json
"packageRules": [
  {
    "matchPackageNames": ["jason"],
    "automerge": true
  }
]
```

### Adjust Stability Period

**Global:**
```json
"stabilityDays": 7
```

**Per package:**
```json
"packageRules": [
  {
    "matchPackageNames": ["eventstore"],
    "stabilityDays": 14
  }
]
```

## Best Practices

### Do ✅

- Review major version updates carefully
- Monitor security alerts immediately
- Keep EventStore ecosystem updates together
- Test auto-merged PRs in staging before production
- Check changelogs for breaking changes

### Don't ❌

- Ignore security updates
- Auto-merge major versions without testing
- Disable Renovate completely
- Merge PRs with failing tests
- Update Erlang/Elixir without local testing

## Security Considerations

### GitHub Actions Pinning

All GitHub Actions are pinned to **SHA digests** for security:
```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

This prevents supply chain attacks via compromised action tags.

### Vulnerability Alerts

Renovate integrates with GitHub Security:
- Immediate PRs for vulnerabilities
- Bypasses normal schedule
- Labeled with `security`
- Requires manual review for major versions

### Audit Trail

All auto-merged PRs have:
- Full CI test results
- Changelog links
- Dependency diff
- Commit history

## Support

### Renovate Documentation
- [Official Docs](https://docs.renovatebot.com/)
- [Configuration Options](https://docs.renovatebot.com/configuration-options/)
- [Preset Configs](https://docs.renovatebot.com/presets-default/)

### Project-Specific Help

See `CLAUDE.md` for:
- Architecture details
- Testing requirements
- Dependency relationships
- Development workflow

### Getting Help

1. Check Renovate dashboard for status
2. Review CI logs for test failures
3. Check `renovate.json` for configuration
4. See Renovate docs for advanced configuration

## Example Workflows

### Scenario: New Hex Package Version

1. **Monday 3 AM UTC**: Renovate detects `jason` 1.4.1 → 1.4.2
2. **Renovate**: Creates PR with changelog
3. **GitHub Actions**: Runs all CI tests
4. **CI passes**: All 102 unit tests + integration tests ✓
5. **Auto-merge**: PR automatically squash-merged
6. **Done**: Dependency updated, no manual intervention

### Scenario: EventStore Major Update

1. **Renovate**: Detects `eventstore` 1.4.8 → 2.0.0
2. **Renovate**: Creates PR labeled `EventStore ecosystem`, `major-update`
3. **Auto-merge**: Disabled (major version)
4. **You**: Review changelog, see breaking changes
5. **You**: Update code to handle API changes
6. **You**: Manually test locally
7. **You**: Approve and merge PR
8. **Done**: Major update completed safely

### Scenario: Security Vulnerability

1. **GitHub Security**: Detects vulnerability in `plug` 1.14.0
2. **Renovate**: Immediate PR (bypasses schedule)
3. **Renovate**: Labels with `security`
4. **CI**: Runs all tests
5. **You**: Notified via GitHub
6. **You**: Review security advisory
7. **Auto-merge**: Merges if patch/minor, otherwise needs approval
8. **Done**: Security patched quickly

## Monitoring Auto-Merged PRs

### Recommended Practice

After auto-merge:
1. Monitor production for 24 hours
2. Check error rates/logs
3. Run smoke tests in staging
4. Rollback if issues found:
   ```bash
   git revert <commit-hash>
   git push
   ```

### Staging Environment

Consider:
- Auto-merge to staging branch first
- Promote to production after verification
- Use Renovate `baseBranches` config

## Summary

✅ **Auto-merge enabled** for low-risk updates
✅ **All tests must pass** before merge
✅ **Major versions** require manual review
✅ **Security updates** prioritized
✅ **Rate limited** to prevent spam
✅ **Scheduled** for Monday mornings
✅ **Grouped** by dependency relationships

This setup balances **automation** with **safety**, keeping dependencies current while protecting production stability.
