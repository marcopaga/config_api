# CI/CD Setup Verification Checklist

This document helps you verify that the Renovate and GitHub Actions setup is working correctly.

## ✅ Files Created/Updated

### Renovate Configuration
- [x] `renovate.json` - Auto-merge configuration
- [x] `.github/RENOVATE.md` - Documentation guide

### GitHub Actions Workflows
- [x] `.github/workflows/elixir.yml` - Main CI (unit tests)
- [x] `.github/workflows/integration.yml` - HTTP integration tests
- [x] `.github/workflows/security.yml` - Security scanning
- [x] `.github/workflows/spec-validation.yml` - API spec validation (updated)

### Integration Test Scripts
- [x] `scripts/integration_test.sh` - HTTP endpoint testing script

### Documentation
- [x] `README.md` - Updated with CI badges
- [x] `.github/RENOVATE.md` - Complete Renovate guide

## 🧪 Local Verification

### Step 1: Check Integration Test Script

```bash
# Verify script exists and is executable
ls -la scripts/integration_test.sh

# Should show: -rwxr-xr-x
```

### Step 2: Test Integration Script Locally

```bash
# Start PostgreSQL
docker-compose up -d

# Initialize EventStore
mix event_store.create
mix event_store.init

# Start the application
iex -S mix

# In another terminal, run integration tests
./scripts/integration_test.sh

# Expected output: All tests passing ✓
```

### Step 3: Verify GitHub Actions Syntax

```bash
# Check workflow files are valid YAML
yamllint .github/workflows/*.yml

# Or use GitHub CLI
gh workflow list
```

## 🚀 GitHub Setup Required

### Enable Renovate

1. **Install Renovate App**
   - Go to: https://github.com/apps/renovate
   - Click "Configure"
   - Select your repository
   - Grant permissions

2. **Verify Installation**
   ```bash
   # Renovate should create an onboarding PR
   gh pr list --label dependencies
   ```

### Configure Branch Protection

**Critical for auto-merge to work!**

1. Go to: `https://github.com/YOUR_USERNAME/config_api/settings/branches`
2. Click "Add rule" or edit existing `main` branch rule
3. Configure:
   ```
   Branch name pattern: main

   ✅ Require status checks to pass before merging
   ✅ Require branches to be up to date before merging

   Status checks that are required:
     - Build and test
     - Integration tests
     - Contract Tests

   ✅ Allow auto-merge
   ⚠️ DO NOT enable "Require pull request reviews"
   ```

4. Save changes

### Enable GitHub Actions

1. Go to: `https://github.com/YOUR_USERNAME/config_api/actions`
2. If Actions are disabled, click "I understand my workflows, enable them"
3. Verify workflows appear:
   - Elixir CI
   - Integration Tests
   - Security Scanning
   - Specification Validation

## 🔍 Verification Tests

### Test 1: Push Changes to GitHub

```bash
# Add and commit all changes
git add .
git commit -m "feat: add Renovate auto-merge and integration tests

- Configure Renovate for auto-merge on patch/minor updates
- Add HTTP integration test suite with 12 test cases
- Add security scanning workflow with SBOM generation
- Update spec validation with pinned action versions
- Add comprehensive documentation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# Push to GitHub
git push origin feature/cqrs-migration
```

### Test 2: Verify CI Runs

```bash
# Watch workflow status
gh run watch

# Or check via web
gh browse --branch feature/cqrs-migration
```

**Expected Result**: All 4 workflows should run and pass ✓

### Test 3: Create Pull Request

```bash
# Create PR to main
gh pr create --title "Add Renovate auto-merge and integration tests" \
  --body "$(cat <<'EOF'
## Summary
- Enhanced Renovate configuration with auto-merge for low-risk updates
- HTTP integration test suite (12 test cases)
- Security scanning workflow
- Updated API specification validation

## Testing
- ✅ All unit tests passing (102 tests)
- ✅ Integration tests validate key CQRS use cases
- ✅ Security scans complete
- ✅ API specifications valid

## Auto-Merge Configuration
See `.github/RENOVATE.md` for complete documentation on:
- What gets auto-merged (patches/minors when tests pass)
- What requires manual review (major versions, EventStore)
- Safety mechanisms (required status checks, rate limits)

🤖 Generated with Claude Code
EOF
)"
```

### Test 4: Verify Status Checks

In the PR:
- [ ] "Build and test" check appears
- [ ] "Integration tests" check appears
- [ ] "Contract Tests" check appears
- [ ] All checks pass ✓

### Test 5: Test Renovate (After Merge)

After merging to `main`:

```bash
# Wait for Renovate to scan (usually within 1 hour)
# Check for Renovate PRs
gh pr list --author "renovate[bot]"

# Should see PRs for dependency updates
```

## 📊 Expected CI Workflow Results

### Elixir CI Workflow
```
✓ Checkout code
✓ Set up Elixir (1.18.4 / OTP 28.0.2)
✓ Restore dependencies cache
✓ Install dependencies
✓ Check code formatting
✓ Compile with warnings as errors
✓ Initialize EventStore
✓ Run unit tests (102 tests)
✓ Generate test coverage report
✓ Upload test results
```

### Integration Tests Workflow
```
✓ Checkout code
✓ Set up Elixir
✓ Install dependencies
✓ Compile application
✓ Initialize EventStore
✓ Start ConfigApi server in background
✓ Wait for server to be ready
✓ Run integration tests (12 tests)
  - Health check endpoint
  - List configurations (empty state)
  - Set configuration value (CQRS command)
  - Get configuration value (CQRS query)
  - Update configuration value
  - Verify immediate consistency
  - List configurations (with test key)
  - Get event history (event sourcing)
  - Time-travel query
  - Delete configuration
  - Verify deletion (404)
  - History persists after deletion
✓ Stop server
```

### Security Scanning Workflow
```
✓ Dependency security audit
  - Check for outdated dependencies
  - Check for known vulnerabilities
  - Generate dependency tree
✓ Docker image security scan
  - Scan postgres:14-alpine with Trivy
  - Upload results to GitHub Security
✓ Code quality checks
  - Check code formatting
  - Compile with warnings as errors
  - Check for unused dependencies
✓ SBOM generation
  - Generate Software Bill of Materials
✓ Security summary
```

### Specification Validation Workflow
```
✓ Validate OpenAPI spec
  - Lint spec/openapi/configapi-v1.yaml
  - Generate API documentation
✓ Validate JSON Schemas
  - ConfigValueSet schema
  - ConfigValueDeleted schema
  - ConfigValue aggregate schema
✓ Validate AsyncAPI spec
  - Lint spec/asyncapi/config-events-v1.yaml
✓ Run contract tests (61 tests)
✓ Generate specification report
```

## 🎯 Success Criteria

### All Green ✓
- [ ] Local integration tests pass
- [ ] All GitHub Actions workflows pass
- [ ] Renovate onboarding PR created
- [ ] Branch protection configured
- [ ] Auto-merge enabled
- [ ] CI badges show passing status

### Expected Timeline
- **T+0 min**: Push to GitHub
- **T+2 min**: CI workflows start
- **T+5 min**: All workflows complete
- **T+1 hour**: Renovate scans repository
- **T+1 hour**: Renovate creates first PR (if updates available)

## 🐛 Troubleshooting

### Integration Tests Fail Locally

**Issue**: Server not starting or tests timing out

**Solution**:
```bash
# Check PostgreSQL is running
docker-compose ps

# Check EventStore is initialized
psql -U postgres -d config_api_eventstore -c "\dt"

# Check server logs
iex -S mix
# Look for startup errors
```

### GitHub Actions Fail

**Issue**: "Unable to connect to database"

**Solution**: PostgreSQL service container in CI needs time to start. The health check should handle this, but if it fails:
- Check service configuration in workflow file
- Verify POSTGRES_DB matches EVENTSTORE_DATABASE

### Renovate Not Creating PRs

**Issue**: No PRs after 1 hour

**Possible causes**:
1. Renovate app not installed - Check: https://github.com/apps/renovate
2. Repository not selected in Renovate config
3. All dependencies already up to date
4. Renovate onboarding PR not merged yet

**Check status**:
```bash
# Look for Renovate dashboard issue
gh issue list --label renovate
```

### Auto-Merge Not Working

**Issue**: Renovate PR created but not auto-merging

**Check**:
1. Branch protection configured?
   ```bash
   gh api repos/:owner/:repo/branches/main/protection
   ```

2. All status checks passing?
   ```bash
   gh pr checks <PR_NUMBER>
   ```

3. "Allow auto-merge" enabled in repo settings?
   - Go to: Settings → General → Pull Requests
   - Check: "Allow auto-merge"

## 📝 Next Steps

After successful verification:

1. **Monitor First Week**
   - Watch Renovate PRs
   - Verify auto-merge behavior
   - Check no broken builds

2. **Adjust Configuration**
   - Tune rate limits if too many PRs
   - Add more package groups if needed
   - Adjust schedules to your preference

3. **Production Deployment**
   - Test auto-merged changes in staging first
   - Monitor error rates after updates
   - Set up alerts for failed CI runs

4. **Team Communication**
   - Share `.github/RENOVATE.md` with team
   - Document any custom rules
   - Set up notifications for `security` label

## 🎉 Success!

If all checks pass, you now have:

✅ **Automated dependency updates**
✅ **Auto-merge for low-risk changes**
✅ **Comprehensive CI test suite**
✅ **Security vulnerability scanning**
✅ **API specification validation**
✅ **Full CQRS integration tests**

**Your repository is now production-ready with automated dependency management!**

## 📚 Additional Resources

- [Renovate Documentation](https://docs.renovatebot.com/)
- [GitHub Actions Documentation](https://docs.github.com/actions)
- [GitHub Branch Protection](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Project CLAUDE.md](../CLAUDE.md) - Architecture and development guide
- [Renovate Guide](.github/RENOVATE.md) - Detailed Renovate management

---

**Questions or Issues?**

1. Check the troubleshooting section above
2. Review workflow logs: `gh run view <run-id>`
3. Check Renovate logs in PR descriptions
4. See `.github/RENOVATE.md` for configuration help
