# Operator Release Automation — Design Spec

**Date:** 2026-09-01  
**Status:** Draft  
**Scope:** GitHub Actions workflow to automate the OpenShift operator release pipeline

---

## 1. Problem

Releasing a new version of the Nexus Repository HA OpenShift operator requires 27 manual steps
across four repositories and two Jenkins jobs. The most painful segments are:

- Manually navigating Red Hat catalog UI to copy-paste two image SHA digests
- Running four scripts in sequence across two repos
- Opening a PR with a precise title format to Red Hat's upstream certified-operators repo

The process is documented in Confluence and is triggered entirely by a human reading the NXRM
release checklist. There is no automation beyond the two Jenkins build jobs that already exist.

---

## 2. Goals

- Reduce the operator release to: trigger two Jenkins jobs → approve one gate → review one PR
- Eliminate all manual file edits, SHA hunting, script runs, and PR mechanics
- Keep humans in the loop for the two Docker image builds (which require internal Jenkins) and
  the final certified-operators PR review
- Do not change the operator architecture (Helm-based, no Go rewrite warranted — see §9)

---

## 3. Out of Scope

- Automating the `docker-nexus3` Dockerfile.rh.ubi.java17 update (step 8 in Confluence): that
  step requires knowledge of the NXRM artifact SHA from the upstream release process, which is
  outside this repo's boundary. It stays manual for now.
- Automatically detecting new NXRM versions (version polling / scheduling): the team wants to
  control the release trigger. That can be added later on top of this workflow.
- The two Jenkins builds themselves: both require Docker and internal network access
  (`jenkins.ci.sonatype.dev` is not reachable from GitHub-hosted runners).
- Git tagging (step 26) and Jira fix version (step 27): low-effort manual steps; out of scope.

---

## 4. Architecture

### 4.1 Repositories involved

| Repository | Role |
|---|---|
| `sonatype/operator-nexus-repository` | Source of truth; workflow lives here |
| `sonatype/certified-operators` | Sonatype's fork of the RH upstream; workflow commits here |
| `redhat-openshift-ecosystem/certified-operators` | RH upstream; workflow opens a PR here |

### 4.2 What stays manual vs. what the workflow does

```
Human                              GitHub Actions Workflow
────────────────────────────────   ──────────────────────────────────────────────
Trigger workflow_dispatch          [job: prepare]
  inputs: operatorVersion,           └─ run new_version.sh image
          certAppVersion,            └─ commit + push release branch
          previousVersion
                                   [job: await-builds]  ← manual approval gate
Update docker-nexus3 Dockerfile      └─ blocked until human clicks Approve
Trigger Jenkins operator build
Trigger Jenkins UBI image build    [job: bundle-and-pr]
Wait ~30 min for RH to publish       └─ poll RH API for both image SHAs
Click Approve in GH Actions UI       └─ run new_version.sh bundle
                                     └─ commit bundle files to main
                                     └─ sync certified-operators fork
                                     └─ run copy-to-certified.sh
                                     └─ commit + push to certified-operators fork
                                     └─ open PR to RH upstream (correct title)
Review auto-created PR
```

### 4.3 Workflow file

Single file: `.github/workflows/operator-release.yml`

Three jobs chained with `needs`:
1. `prepare` — file templating + commit
2. `await-builds` — manual approval gate (GH environment protection rule)
3. `bundle-and-pr` — SHA retrieval, bundle generation, certified-operators PR

---

## 5. Job Design

### 5.1 `prepare` job

**Inputs** (from `workflow_dispatch`):

| Input | Example | Description |
|---|---|---|
| `operator_version` | `3.91.0-1` | New operator version |
| `cert_app_version` | `3.91.0-ubi-1` | New certified app image version (tag at RH) |
| `previous_version` | `3.90.3-1` | Previous operator version (for `olm.replaces`) |

**Steps:**
1. `actions/checkout@v4` on `main`
2. Configure git user (`github-actions[bot]`)
3. Run `./scripts/new_version.sh image ${{ inputs.operator_version }} ${{ inputs.cert_app_version }}`
   — this updates `helm-charts/nxrm-ha/Chart.yaml`, `helm-charts/nxrm-ha/values.yaml`,
   and `build/Dockerfile`
4. Commit the three changed files with message:
   `release ${{ inputs.operator_version }}: update image version files`
5. Push directly to `main`
6. Print summary with links to both Jenkins jobs for the human to click

Note: pushing directly to `main` matches the existing release pattern (Confluence step 5 says
"push to main"). The branch is linear; no PR needed for this mechanical step.

### 5.2 `await-builds` job

**Depends on:** `prepare`

This job is gated by a GitHub Environment named `operator-release-approval`. The environment must
be configured in GitHub Settings with at least one required reviewer from the operator team.

When the `prepare` job finishes, GitHub shows a "Review deployments" button in the Actions UI.
The human uses this to signal that:
- Both Jenkins builds have finished
- Both images have been published to the Red Hat catalog

The job has one placeholder step (`echo "Builds approved"`) to satisfy GH Actions syntax; the
real gate is the environment protection rule pause before the job is allowed to start.

### 5.3 `bundle-and-pr` job

**Depends on:** `await-builds`

**Steps:**

1. `actions/checkout@v4` on `main` (picks up the `prepare` commit)

2. **Retrieve operator image SHA** from Red Hat connect API:
   ```
   POST https://connect.redhat.com/api/v2/projects/64d3814688a42145092bb0ff/tags
   Authorization: Bearer ${{ secrets.RH_API_TOKEN }}
   ```
   Filter tags where `name == operator_version` and `scan_status == "passed"`.
   Extract `digest` field → full ref:
   `registry.connect.redhat.com/sonatype/nexus-repository-ha-operator-certified@{digest}`

3. **Retrieve app image SHA** from Red Hat connect API:
   ```
   POST https://connect.redhat.com/api/v2/projects/5e61d90a38776799eb517bd2/tags
   Authorization: Bearer ${{ secrets.RH_API_TOKEN }}
   ```
   Filter tags where `name == cert_app_version` and `scan_status == "passed"`.
   Extract `digest` field → full ref:
   `registry.connect.redhat.com/sonatype/nexus-repository-manager@{digest}`

   Both retrieval steps retry with 60-second backoff for up to 90 minutes. If either SHA is not
   found within the timeout, the job fails with a clear error message and the SHA can be supplied
   manually as a re-run input (see §7 error handling).

4. **Generate bundle files:**
   ```
   ./scripts/new_version.sh bundle \
     ${{ inputs.previous_version }} \
     ${{ inputs.operator_version }} \
     <operator-image-ref> \
     <app-image-ref>
   ```
   This generates the OLM bundle manifests under
   `deploy/olm-catalog/nexus-repository-ha-operator-certified/${{ inputs.operator_version }}/`.

5. Commit bundle files to `main`:
   ```
   git add deploy/olm-catalog/...
   git commit -m "release ${{ inputs.operator_version }}: add OLM bundle"
   git push
   ```

6. **Sync certified-operators fork:**
   ```
   gh repo sync sonatype/certified-operators --source redhat-openshift-ecosystem/certified-operators
   ```

7. **Checkout certified-operators** into a subdirectory:
   ```
   git clone https://x-access-token:${{ secrets.RELEASE_PAT }}@github.com/sonatype/certified-operators.git ../certified-operators
   ```

8. **Copy bundle files:**
   ```
   cd ${{ github.workspace }}
   ./scripts/copy-to-certified.sh ${{ inputs.operator_version }}
   ```
   The script resolves the certified-operators path relative to the workspace, so the clone in
   step 7 must be at `${{ github.workspace }}/../certified-operators`.

9. **Commit and push to certified-operators fork:**
   ```
   cd ../certified-operators
   git add operators/nexus-repository-ha-operator-certified/${{ inputs.operator_version }}/
   git commit -m "operator nexus-repository-ha-operator-certified (${{ inputs.operator_version }})"
   git push origin main
   ```
   The commit message format matches the required PR title format (Confluence step 19).

10. **Open PR to RH upstream:**
    ```
    gh pr create \
      --repo redhat-openshift-ecosystem/certified-operators \
      --title "operator nexus-repository-ha-operator-certified (${{ inputs.operator_version }})" \
      --body "Automated release of ${{ inputs.operator_version }}" \
      --head sonatype:main \
      --base main
    ```
    Uses `RELEASE_PAT` (must belong to a user in the "Authorized Github User Accounts" list on
    the Red Hat connect bundle project).

11. Post a GitHub Actions job summary with: PR link, both image SHAs used, and a reminder to
    tag the release and set the Jira fix version.

---

## 6. Secrets and Credentials

| Secret name | Where stored | What it is |
|---|---|---|
| `RH_API_TOKEN` | `operator-nexus-repository` repo secrets | Red Hat connect API token (already used by Jenkins; same credential) |
| `RELEASE_PAT` | `operator-nexus-repository` repo secrets | GitHub Personal Access Token of an authorized team member. Needs: `repo` scope on `sonatype/certified-operators` + `public_repo` scope to open PRs on `redhat-openshift-ecosystem/certified-operators`. Must belong to a user in the RH connect "Authorized Github User Accounts" list. |

The `GITHUB_TOKEN` (automatic) is used for the `await-builds` environment gate and Actions
summary. It does not need additional configuration.

### GitHub Environment

Create an environment named `operator-release-approval` in the repo settings with:
- Required reviewers: at least one person from the operator team
- No deployment branch restrictions (the workflow runs on `main`)

---

## 7. Error Handling

| Failure point | Behaviour |
|---|---|
| `new_version.sh image` fails | Job fails immediately; no commit is made; safe to re-run |
| SHA not found within 90 min | Job fails with message: "Image not yet published at RH. Re-run the `bundle-and-pr` job after confirming the image is live." |
| `new_version.sh bundle` fails | Job fails; the `prepare` commit and `await-builds` approval are already done; re-run only `bundle-and-pr` with the same inputs |
| certified-operators fork push fails | Likely a merge conflict from RH upstream changes; `gh repo sync` is run first to mitigate; if it still fails, a clear error is surfaced |
| PR already open from a previous release | The job checks for an open PR from `sonatype:main` and **fails loudly** with instructions to close/merge it before re-running. This prevents a new release's bundle from being silently appended to the old PR under the wrong title. |

---

## 8. Testing Plan

Because this workflow touches live external systems (Red Hat API, certified-operators upstream),
full end-to-end testing requires a real release. The following staged approach reduces risk:

1. **Unit test scripts locally** — run `new_version.sh image` and `new_version.sh bundle` with
   dummy SHAs against a test branch to verify they produce correct output before wiring into GH
   Actions.

2. **Dry-run the workflow on a shadow release** — on the next real release, run the workflow in
   parallel with the existing manual process. Compare outputs. Only switch to the automated path
   once outputs match.

3. **API exploration sprint (1 day before implementation)** — manually call the Red Hat connect
   API (`POST /api/v2/projects/{id}/tags`) with the existing `RH_API_TOKEN` to confirm the
   response shape and that `digest` is in the expected format. This validates the SHA retrieval
   design before committing to it.

4. **certified-operators PR dry run** — test the `gh pr create` command against a test fork
   (not the real upstream) to verify title format and token permissions.

---

## 9. Go Operator Assessment (conclusion)

Rewriting the operator in Go is not recommended at this time. The operator does pure declarative
templating: a 5-line `watches.yaml` maps one CRD to one Helm chart. There is no custom
reconciliation logic, no Nexus API interaction, and no complex upgrade lifecycle. The Helm operator
base image is actively maintained by the Operator Framework project and already passes Red Hat
certification. A Go rewrite would require operator-sdk/kubebuilder boilerplate, controller
unit-test infrastructure, and a CRD schema migration — all for no user-visible benefit.

The only scenario that would justify a rewrite is if the team later needs: richer CRD status
conditions fed from the Nexus REST API, custom upgrade sequencing (e.g., drain-before-replace),
or admission webhook validation. None of those are current requirements.

---

## 10. Future Extension: Automated Version Detection

The current design still requires a human to initiate the workflow. A future extension could add
a scheduled GH Actions job (daily) that:

1. Calls the Red Hat Pyxis catalog API to fetch the latest published NXRM UBI image tag
2. Compares it against `appVersion` in `helm-charts/nxrm-ha/Chart.yaml`
3. If a new version exists, creates a Jira ticket and/or opens a draft PR with `prepare` changes

This is additive — it does not change the architecture above, only adds a trigger.

---

## Appendix: Reduced Manual Steps After Automation

| # | Step | Who |
|---|---|---|
| 1 | Update docker-nexus3 Dockerfile.rh.ubi.java17 with new NXRM version | Human |
| 2 | Trigger Jenkins NXRM UBI image build | Human |
| 3 | Trigger `operator-release` workflow_dispatch with 3 inputs | Human |
| 4 | Trigger Jenkins operator image build (link shown in workflow summary) | Human |
| 5 | Wait ~30 min for both builds + RH publishing | — |
| 6 | Click Approve in GH Actions environment gate | Human |
| 7 | Review auto-created certified-operators PR | Human |
| 8 | Git tag + Jira fix version | Human |

Down from 27 steps to 8, with 4 of those being one-click actions.
