# Operator Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that reduces the 27-step manual operator release process to 8 steps by automating version file updates, image SHA retrieval, OLM bundle generation, and the certified-operators PR.

**Architecture:** A single `workflow_dispatch` workflow with three chained jobs: `prepare` (runs `new_version.sh image`, commits), `await-builds` (human approval gate while Jenkins runs), and `bundle-and-pr` (polls Red Hat API for SHAs, runs `new_version.sh bundle`, copies to `certified-operators` fork, opens PR to RH upstream). SHA retrieval is extracted into a standalone, testable shell script.

**Tech Stack:** GitHub Actions (`ubuntu-latest`), bash, `jq` (pre-installed on ubuntu-latest), `gh` CLI (pre-installed on ubuntu-latest), Red Hat connect REST API, `shellcheck`

**Spec:** `docs/superpowers/specs/2026-09-01-operator-release-automation-design.md`

## Global Constraints

- GH Actions jobs: `runs-on: ubuntu-latest` (GitHub-hosted)
- Workflow inputs: `operator_version` (e.g. `3.91.0-1`), `cert_app_version` (e.g. `3.91.0-ubi-1`), `previous_version` (e.g. `3.90.3-1`)
- Red Hat API base: `https://connect.redhat.com`
- Red Hat API tags endpoint: `POST /api/v2/projects/{projectId}/tags` — returns `{"tags":[{"name":"...","scan_status":"passed","digest":"sha256:..."}]}`
- Operator project ID: `64d3814688a42145092bb0ff`
- App project ID: `5e61d90a38776799eb517bd2`
- Operator registry prefix: `registry.connect.redhat.com/sonatype/nexus-repository-ha-operator-certified`
- App registry prefix: `registry.connect.redhat.com/sonatype/nexus-repository-manager`
- SHA polling: retry every 60s, up to 90 attempts (90-minute timeout)
- Secret `RH_API_TOKEN`: Red Hat connect API Bearer token (same as used by existing Jenkins jobs)
- Secret `RELEASE_PAT`: GitHub PAT with `repo` scope; **must belong to a user listed in "Authorized Github User Accounts" on the RH connect bundle project** (`https://connect.redhat.com/projects/64ef748bfe44a37dc8b33eea/settings`)
- GH Environment name: `operator-release-approval`
- Certified-operators PR title (exact): `operator nexus-repository-ha-operator-certified (<operator_version>)`
- Certified-operators commit message (exact): `operator nexus-repository-ha-operator-certified (<operator_version>)`

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| Create | `scripts/get-rh-image-sha.sh` | Polls RH connect API for an image SHA; retries up to 90 min |
| Create | `scripts/test-get-rh-image-sha.sh` | Bash tests for the above script using mock curl |
| Create | `.github/workflows/operator-release.yml` | Three-job release workflow |
| Create | `docs/releasing.md` | Human-readable release guide replacing the manual Confluence steps |

---

### Task 1: SHA Retrieval Script

**Files:**
- Create: `scripts/get-rh-image-sha.sh`
- Create: `scripts/test-get-rh-image-sha.sh`

**Interfaces:**
- Produces: `get-rh-image-sha.sh <projectId> <imageTag> <registryPrefix>`
  - Env vars consumed: `RH_API_TOKEN` (required), `RH_API_BASE` (default `https://connect.redhat.com`), `MAX_ATTEMPTS` (default `90`)
  - On success: prints `<registryPrefix>@sha256:<digest>` to stdout, exits 0
  - On timeout or missing token: prints error to stderr, exits 1

---

- [ ] **Step 1.1: Create the test script**

Create `scripts/test-get-rh-image-sha.sh`:

```bash
#!/bin/sh
# No set -e — tests intentionally invoke commands that exit non-zero

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

run_test() {
  name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Creates a temporary directory containing a mock `curl` binary that prints $1 and exits 0
mock_curl() {
  response="$1"
  mock_dir=$(mktemp -d)
  printf '#!/bin/sh\nprintf '"'"'%%s'"'"' '"'"'%s'"'"'\n' "$response" > "$mock_dir/curl"
  chmod +x "$mock_dir/curl"
  printf '%s' "$mock_dir"
}

# --- Test 1: returns full image ref when tag found with scan_status=passed ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.90.3-1","scan_status":"passed","digest":"sha256:abc123"}]}')
actual=$(PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" \
  "proj-id" "3.90.3-1" "registry.connect.redhat.com/sonatype/nxrm" 2>/dev/null)
run_test "returns full ref on success" \
  "registry.connect.redhat.com/sonatype/nxrm@sha256:abc123" "$actual"
rm -rf "$mock_dir"

# --- Test 2: exits 1 when scan_status is pending (simulates timeout with MAX_ATTEMPTS=1) ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.90.3-1","scan_status":"pending","digest":"sha256:abc123"}]}')
PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "3.90.3-1" "reg/img" 2>/dev/null; actual_exit=$?
run_test "exits 1 when scan_status is pending (timeout)" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 3: exits 1 when RH_API_TOKEN is empty ---
RH_API_TOKEN="" "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "tag" "reg/img" 2>/dev/null; actual_exit=$?
run_test "exits 1 when RH_API_TOKEN is empty" "1" "$actual_exit"

# --- Test 4: exits 1 when tag name is not in response ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.89.0-1","scan_status":"passed","digest":"sha256:old"}]}')
PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "3.90.3-1" "reg/img" 2>/dev/null; actual_exit=$?
run_test "exits 1 when requested tag not in response" "1" "$actual_exit"
rm -rf "$mock_dir"

# --- Test 5: picks correct tag when multiple tags present ---
mock_dir=$(mock_curl '{"tags":[{"name":"3.89.0-1","scan_status":"passed","digest":"sha256:old"},{"name":"3.90.3-1","scan_status":"passed","digest":"sha256:new"}]}')
actual=$(PATH="$mock_dir:$PATH" RH_API_TOKEN="t" MAX_ATTEMPTS=1 \
  "$SCRIPT_DIR/get-rh-image-sha.sh" "proj-id" "3.90.3-1" "reg/img" 2>/dev/null)
run_test "picks correct tag among multiple" "reg/img@sha256:new" "$actual"
rm -rf "$mock_dir"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 1.2: Run the tests — expect all to fail**

```bash
chmod +x scripts/test-get-rh-image-sha.sh
./scripts/test-get-rh-image-sha.sh
```

Expected: script errors or `FAIL` on all 5 tests (the implementation doesn't exist yet).

- [ ] **Step 1.3: Create `scripts/get-rh-image-sha.sh`**

```bash
#!/bin/sh
# Polls the Red Hat connect API until the given image tag is published with scan_status=passed.
# Usage: get-rh-image-sha.sh <projectId> <imageTag> <registryPrefix>
# Output: <registryPrefix>@<digest>  (e.g. registry.connect.redhat.com/sonatype/img@sha256:...)
# Env:
#   RH_API_TOKEN  - Red Hat connect Bearer token (required)
#   RH_API_BASE   - API base URL (default: https://connect.redhat.com)
#   MAX_ATTEMPTS  - number of 60-second retries before timeout (default: 90)

set -e

if [ -z "$RH_API_TOKEN" ]; then
  printf 'ERROR: RH_API_TOKEN must be set\n' >&2
  exit 1
fi

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <projectId> <imageTag> <registryPrefix>\n' "$0" >&2
  exit 1
fi

PROJECT_ID="$1"
IMAGE_TAG="$2"
REGISTRY_PREFIX="$3"
API_BASE="${RH_API_BASE:-https://connect.redhat.com}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-90}"

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  response=$(curl -sf -X POST \
    -H "Authorization: Bearer ${RH_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "${API_BASE}/api/v2/projects/${PROJECT_ID}/tags" 2>/dev/null || printf '{}')

  digest=$(printf '%s' "$response" | jq -r --arg tag "$IMAGE_TAG" \
    '[.tags[] | select(.name == $tag and .scan_status == "passed")] | first | .digest // empty' \
    2>/dev/null || true)

  if [ -n "$digest" ]; then
    printf '%s@%s\n' "$REGISTRY_PREFIX" "$digest"
    exit 0
  fi

  attempt=$((attempt + 1))
  remaining=$((MAX_ATTEMPTS - attempt))
  printf 'Tag %s not yet published (attempt %d/%d, %d remaining). Retrying in 60s...\n' \
    "$IMAGE_TAG" "$attempt" "$MAX_ATTEMPTS" "$remaining" >&2
  [ "$attempt" -lt "$MAX_ATTEMPTS" ] && sleep 60
done

printf 'ERROR: Timed out after %d attempts waiting for tag %s (scan_status=passed)\n' \
  "$MAX_ATTEMPTS" "$IMAGE_TAG" >&2
exit 1
```

- [ ] **Step 1.4: Make both scripts executable and run tests**

```bash
chmod +x scripts/get-rh-image-sha.sh
./scripts/test-get-rh-image-sha.sh
```

Expected: `5 passed, 0 failed`

If `jq` is not installed locally (macOS): `brew install jq`, then re-run.

- [ ] **Step 1.5: Run shellcheck on both scripts**

```bash
shellcheck scripts/get-rh-image-sha.sh scripts/test-get-rh-image-sha.sh
```

Expected: no errors. Install with `brew install shellcheck` if needed.

- [ ] **Step 1.6: Commit**

```bash
git add scripts/get-rh-image-sha.sh scripts/test-get-rh-image-sha.sh
git commit -m "feat: add Red Hat image SHA retrieval script with tests"
```

---

### Task 2: Workflow — `prepare` job

**Files:**
- Create: `.github/workflows/operator-release.yml`

**Interfaces:**
- Consumes (existing): `./scripts/new_version.sh image <operatorVersion> <certAppVersion>`
  - Writes `helm-charts/nxrm-ha/Chart.yaml`, `helm-charts/nxrm-ha/values.yaml`, `build/Dockerfile`
- Produces: workflow file with `workflow_dispatch` trigger and `prepare` job

---

- [ ] **Step 2.1: Create `.github/workflows/` directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2.2: Create the workflow file with the `prepare` job**

Create `.github/workflows/operator-release.yml`:

```yaml
name: Operator Release

on:
  workflow_dispatch:
    inputs:
      operator_version:
        description: 'New operator version (e.g. 3.91.0-1)'
        required: true
        type: string
      cert_app_version:
        description: 'Certified app image tag at RH (e.g. 3.91.0-ubi-1)'
        required: true
        type: string
      previous_version:
        description: 'Previous operator version for OLM replaces field (e.g. 3.90.3-1)'
        required: true
        type: string

jobs:
  prepare:
    name: Update version files
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.RELEASE_PAT }}

      - name: Shellcheck release scripts
        run: |
          shellcheck scripts/get-rh-image-sha.sh \
                     scripts/new_version.sh \
                     scripts/copy-to-certified.sh

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Update version files
        run: |
          ./scripts/new_version.sh image \
            "${{ inputs.operator_version }}" \
            "${{ inputs.cert_app_version }}"

      - name: Commit version files
        run: |
          git add helm-charts/nxrm-ha/Chart.yaml \
                  helm-charts/nxrm-ha/values.yaml \
                  build/Dockerfile
          git commit -m "release ${{ inputs.operator_version }}: update image version files"
          git push

      - name: Print next steps summary
        run: |
          {
            echo "## Version files updated — ${{ inputs.operator_version }}"
            echo ""
            echo "### Trigger both Jenkins builds now, then Approve the gate below"
            echo ""
            echo "**1. Update docker-nexus3 Dockerfile.rh.ubi.java17** with NXRM version \`${{ inputs.cert_app_version }}\`, then trigger:"
            echo "   https://jenkins.ci.sonatype.dev/job/integrations/job/cloud/job/Red%20Hat/job/docker-nexus-repository-red-hat-release/"
            echo ""
            echo "**2. Trigger operator image build** (uses the Dockerfile just committed) — specify version \`${{ inputs.operator_version }}\`:"
            echo "   https://jenkins.ci.sonatype.dev/job/nxrm/job/Red%20Hat/job/operator-nexus-repository-release/"
            echo ""
            echo "**3.** Wait ~30 min for both builds and Red Hat publishing to complete."
            echo ""
            echo "**4.** Return here → click **Review pending deployments** → **Approve**."
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 2.3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/operator-release.yml'))" \
  && echo "YAML valid"
```

Expected: `YAML valid`. Install pyyaml if needed: `pip3 install pyyaml`.

- [ ] **Step 2.4: Verify `new_version.sh image` produces correct output with the new version inputs**

Run on a throwaway branch — do **not** push:

```bash
git checkout -b test-prepare-step
./scripts/new_version.sh image 3.91.0-1 3.91.0-ubi-1
grep "appVersion: 3.91.0" helm-charts/nxrm-ha/Chart.yaml  && echo "Chart.yaml OK"
grep "3.91.0-ubi-1" helm-charts/nxrm-ha/values.yaml        && echo "values.yaml OK"
grep "3.91.0" build/Dockerfile                              && echo "Dockerfile OK"
git checkout main
git branch -D test-prepare-step
```

Expected: all three `OK` lines printed.

- [ ] **Step 2.5: Commit**

```bash
git add .github/workflows/operator-release.yml
git commit -m "feat: add operator-release workflow with prepare job"
```

---

### Task 3: Workflow — `await-builds` and `bundle-and-pr` jobs

**Files:**
- Modify: `.github/workflows/operator-release.yml`

**Interfaces:**
- Consumes from Task 1: `./scripts/get-rh-image-sha.sh <projectId> <imageTag> <registryPrefix>`
  - Env: `RH_API_TOKEN` — writes `<registryPrefix>@<digest>` to stdout
- Consumes (existing): `./scripts/new_version.sh bundle <prevVersion> <newVersion> <opSHA> <appSHA>`
  - Writes files under `deploy/` (see File Map in spec §5.3)
- Consumes (existing): `./scripts/copy-to-certified.sh <operatorVersion>`
  - Copies `deploy/olm-catalog/nexus-repository-ha-operator-certified/<version>/` to `../certified-operators/operators/nexus-repository-ha-operator-certified/<version>/`

---

- [ ] **Step 3.1: Append `await-builds` job to the workflow file**

Add after the closing line of the `prepare` job in `.github/workflows/operator-release.yml`:

```yaml

  await-builds:
    name: Await Jenkins builds (approve when both images published at RH)
    needs: prepare
    runs-on: ubuntu-latest
    environment: operator-release-approval
    steps:
      - name: Builds approved
        run: echo "Jenkins builds confirmed. Proceeding with bundle generation."
```

- [ ] **Step 3.2: Append `bundle-and-pr` job to the workflow file**

Add after the `await-builds` job:

```yaml

  bundle-and-pr:
    name: Generate bundle and open certified-operators PR
    needs: await-builds
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.RELEASE_PAT }}

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Retrieve operator image SHA
        id: operator_sha
        env:
          RH_API_TOKEN: ${{ secrets.RH_API_TOKEN }}
        run: |
          ref=$(./scripts/get-rh-image-sha.sh \
            "64d3814688a42145092bb0ff" \
            "${{ inputs.operator_version }}" \
            "registry.connect.redhat.com/sonatype/nexus-repository-ha-operator-certified")
          echo "ref=$ref" >> "$GITHUB_OUTPUT"

      - name: Retrieve app image SHA
        id: app_sha
        env:
          RH_API_TOKEN: ${{ secrets.RH_API_TOKEN }}
        run: |
          ref=$(./scripts/get-rh-image-sha.sh \
            "5e61d90a38776799eb517bd2" \
            "${{ inputs.cert_app_version }}" \
            "registry.connect.redhat.com/sonatype/nexus-repository-manager")
          echo "ref=$ref" >> "$GITHUB_OUTPUT"

      - name: Generate bundle files
        run: |
          ./scripts/new_version.sh bundle \
            "${{ inputs.previous_version }}" \
            "${{ inputs.operator_version }}" \
            "${{ steps.operator_sha.outputs.ref }}" \
            "${{ steps.app_sha.outputs.ref }}"

      - name: Commit bundle files
        run: |
          git add deploy/
          if git diff --cached --quiet; then
            echo "No bundle changes detected — skipping commit"
          else
            git commit -m "release ${{ inputs.operator_version }}: add OLM bundle"
            git push
          fi

      - name: Sync certified-operators fork with RH upstream
        env:
          GH_TOKEN: ${{ secrets.RELEASE_PAT }}
        run: |
          gh repo sync sonatype/certified-operators \
            --source redhat-openshift-ecosystem/certified-operators

      - name: Clone certified-operators fork
        env:
          RELEASE_PAT: ${{ secrets.RELEASE_PAT }}
        run: |
          git clone \
            "https://x-access-token:${RELEASE_PAT}@github.com/sonatype/certified-operators.git" \
            "${{ github.workspace }}/../certified-operators"
          cd "${{ github.workspace }}/../certified-operators"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Copy bundle to certified-operators
        run: ./scripts/copy-to-certified.sh "${{ inputs.operator_version }}"

      - name: Commit and push to certified-operators fork
        run: |
          cd "${{ github.workspace }}/../certified-operators"
          git add "operators/nexus-repository-ha-operator-certified/${{ inputs.operator_version }}/"
          git commit -m "operator nexus-repository-ha-operator-certified (${{ inputs.operator_version }})"
          git push origin main

      - name: Open PR to Red Hat upstream
        id: pr
        env:
          GH_TOKEN: ${{ secrets.RELEASE_PAT }}
        run: |
          existing=$(gh pr list \
            --repo redhat-openshift-ecosystem/certified-operators \
            --head "sonatype:main" \
            --json url \
            --jq '.[0].url // empty' 2>/dev/null || true)
          if [ -n "$existing" ]; then
            echo "PR already exists: $existing — skipping creation"
            echo "pr_url=$existing" >> "$GITHUB_OUTPUT"
          else
            pr_url=$(gh pr create \
              --repo redhat-openshift-ecosystem/certified-operators \
              --title "operator nexus-repository-ha-operator-certified (${{ inputs.operator_version }})" \
              --body "Automated release of nexus-repository-ha-operator-certified ${{ inputs.operator_version }}" \
              --head "sonatype:main" \
              --base main)
            echo "pr_url=$pr_url" >> "$GITHUB_OUTPUT"
          fi

      - name: Job summary
        run: |
          {
            echo "## Release ${{ inputs.operator_version }} — bundle complete"
            echo ""
            echo "| | |"
            echo "|---|---|"
            echo "| Operator image | \`${{ steps.operator_sha.outputs.ref }}\` |"
            echo "| App image | \`${{ steps.app_sha.outputs.ref }}\` |"
            echo "| Certified-operators PR | ${{ steps.pr.outputs.pr_url }} |"
            echo ""
            echo "### Remaining manual steps"
            echo "1. Monitor the PR above — Red Hat CI validates and auto-merges on pass"
            echo "2. \`git tag ${{ inputs.operator_version }} && git push --tags\`"
            echo "3. Set Jira fix version: https://jenkins.ci.sonatype.dev/job/integrations/job/Set%20Jira%20Fix%20Version/"
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 3.3: Validate the complete YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/operator-release.yml'))" \
  && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 3.4: Verify `copy-to-certified.sh` path resolution matches GH Actions clone target**

The script resolves `certified-operators` as `$PROJECT_ROOT/../certified-operators` where
`$PROJECT_ROOT` is the repo root. In GH Actions `${{ github.workspace }}` is the repo root
(`/home/runner/work/operator-nexus-repository/operator-nexus-repository`), so
`${{ github.workspace }}/../certified-operators` resolves to
`/home/runner/work/operator-nexus-repository/certified-operators` — which is exactly where the
`git clone` step above places the fork. Confirm by reading the script:

```bash
grep "DEST_DIR\|PROJECT_ROOT" scripts/copy-to-certified.sh
```

Expected output includes `"$(cd "$PROJECT_ROOT/.." && pwd)/certified-operators/..."` — the `..`
from the project root matches the `../certified-operators` clone target.

- [ ] **Step 3.5: Commit**

```bash
git add .github/workflows/operator-release.yml
git commit -m "feat: add await-builds gate and bundle-and-pr job to release workflow"
```

---

### Task 4: GitHub Environment setup, secrets docs, release guide

**Files:**
- Create: `docs/releasing.md`

**Interfaces:**
- No code interfaces — configuration and documentation only

---

- [ ] **Step 4.1: Create `docs/releasing.md`**

Create `docs/releasing.md`:

```markdown
# Releasing the Operator

The `Operator Release` GitHub Actions workflow automates the bulk of the release.
Full historical context in Confluence: *Releasing the OpenShift operator*.

## One-time repository setup

### 1. Create the `operator-release-approval` environment

GitHub repo → Settings → Environments → **New environment**

- Name: `operator-release-approval`
- Required reviewers: add at least one operator team member
- Leave deployment branch restrictions empty

### 2. Add repository secrets

GitHub repo → Settings → Secrets and variables → Actions → **New repository secret**

| Name | Value |
|---|---|
| `RH_API_TOKEN` | Red Hat connect API Bearer token. Find it at connect.redhat.com → your account. This is the same token the Jenkins jobs use. |
| `RELEASE_PAT` | GitHub Personal Access Token with `repo` scope. **Must belong to a GitHub user listed in "Authorized Github User Accounts" on the [RH connect bundle project](https://connect.redhat.com/projects/64ef748bfe44a37dc8b33eea/settings).** Generate at github.com/settings/tokens → Tokens (classic). |

### 3. Verify the PAT has write access to the fork

Run once to confirm:
```bash
GH_TOKEN=<your-pat> gh repo view sonatype/certified-operators
```

---

## Release steps

### Step 1 — Trigger the workflow

GitHub Actions → **Operator Release** → **Run workflow**

| Input | Example | Where to find it |
|---|---|---|
| `operator_version` | `3.91.0-1` | New version you are releasing |
| `cert_app_version` | `3.91.0-ubi-1` | The UBI image tag that will appear at RH after the build |
| `previous_version` | `3.90.3-1` | Latest entry in `deploy/olm-catalog/nexus-repository-ha-operator-certified/` |

The `prepare` job updates `Chart.yaml`, `values.yaml`, and `build/Dockerfile` and commits them.
The job summary shows both Jenkins job links.

### Step 2 — Trigger Jenkins builds (still manual)

Jenkins is not reachable from GitHub-hosted runners, so these two builds remain manual:

1. **Update `docker-nexus3` Dockerfile** — edit `Dockerfile.rh.ubi.java17` lines 20–21 and
   39–41 to reference the new NXRM version, then trigger:
   [docker-nexus-repository-red-hat-release](https://jenkins.ci.sonatype.dev/job/integrations/job/cloud/job/Red%20Hat/job/docker-nexus-repository-red-hat-release/)

2. **Build the operator image** — trigger with version `<operator_version>`:
   [operator-nexus-repository-release](https://jenkins.ci.sonatype.dev/job/nxrm/job/Red%20Hat/job/operator-nexus-repository-release/)

3. Wait ~30 minutes for both builds and Red Hat publishing to complete.

### Step 3 — Approve the gate

In the workflow run, click **Review pending deployments** → **Approve**.

The `bundle-and-pr` job runs automatically:
- Polls Red Hat API for both image SHAs (retries every 60s, up to 90 min)
- Generates OLM bundle manifests and commits them
- Syncs the `sonatype/certified-operators` fork, copies the bundle, opens a PR to RH upstream

### Step 4 — Review the PR

The job summary shows the PR URL. Red Hat's CI validates and auto-merges on pass.

### Step 5 — Finish up

```bash
git tag <operator_version>
git push --tags
```

Then set the Jira fix version via the
[Jenkins job](https://jenkins.ci.sonatype.dev/job/integrations/job/Set%20Jira%20Fix%20Version/).

---

## First-release dry run

On the first real release using this workflow, run it **in parallel** with the existing manual
process. Compare the generated bundle files against what you would have produced manually. Only
retire the manual steps once the outputs match.
```

- [ ] **Step 4.2: Run the full test suite and shellcheck one final time**

```bash
./scripts/test-get-rh-image-sha.sh
shellcheck scripts/get-rh-image-sha.sh \
           scripts/test-get-rh-image-sha.sh \
           scripts/new_version.sh \
           scripts/copy-to-certified.sh
```

Expected: `5 passed, 0 failed` and no shellcheck errors.

Note: `new_version.sh` and `copy-to-certified.sh` may already have shellcheck warnings. Fix any
`error`-level issues; `warning`-level issues in existing scripts can be addressed separately.

- [ ] **Step 4.3: Validate YAML one final time**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/operator-release.yml'))" \
  && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 4.4: Commit**

```bash
git add docs/releasing.md
git commit -m "docs: add operator release guide and GitHub environment setup instructions"
```

---

## Post-implementation checklist

Before the first real use:

- [ ] Create `operator-release-approval` environment in GitHub Settings (see `docs/releasing.md` §1)
- [ ] Add `RH_API_TOKEN` and `RELEASE_PAT` secrets to the repo (see `docs/releasing.md` §2)
- [ ] Confirm `RELEASE_PAT` owner is in the RH connect "Authorized Github User Accounts" list
- [ ] Do one dry-run release in parallel with the manual process to validate outputs match
