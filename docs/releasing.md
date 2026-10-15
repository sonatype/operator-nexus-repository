# Releasing the Operator

This guide covers everything about releasing the Sonatype Nexus Repository operator for OpenShift:
what is released, who can run the automation, every step, dry runs, patch releases and troubleshooting.
Full historical context in Confluence: *Releasing the OpenShift operator*.

## Contents

1. [Overview](#overview)
2. [Who can run the release](#who-can-run-the-release)
3. [One-time repository setup](#one-time-repository-setup)
4. [Dry run (rehearsal)](#dry-run-rehearsal)
5. [Release steps](#release-steps)
6. [Version rules and patch releases](#version-rules-and-patch-releases)
7. [Troubleshooting](#troubleshooting)

## Overview

A release publishes a new `ClusterServiceVersion` (CSV) bundle for
`nexus-repository-ha-operator-certified` to Red Hat's `certified-operators` catalog. It needs two
container images already published at Red Hat Connect, and then a bundle PR.

| Artifact | Built by | Version example |
|---|---|---|
| Certified app image (`nexus-repository-manager`) | Jenkins job in `docker-nexus3` (`Jenkinsfile.rh`, builds `Dockerfile.rh.ubi.java21`) | `3.96.4-ubi-1` |
| Operator image (`nexus-repository-ha-operator-certified`) | Jenkins job `operator-nexus-repository-release` | `3.96.4-1` |
| OLM bundle (this repo, `deploy/olm-catalog/...`) | `Operator Release` GitHub workflow | `3.96.4-1` |

The `Operator Release` workflow (`.github/workflows/operator-release.yml`) has two jobs. Jenkins
cannot be reached from GitHub-hosted runners, so the two image builds stay manual and happen
between the jobs.

```
Run workflow ──► [approve] prepare ──► you run both Jenkins builds ──► [approve] bundle-and-pr
                 validate inputs         (~30 min, wait for images          read image SHAs from RH catalog,
                 detect previous         to be published at Red Hat)        generate bundle, commit,
                 version, update                                            push to certified-operators
                 version files, commit                                      fork, open PR to Red Hat
```

Both jobs use the `operator-release-approval` environment, because that is where the secrets live.
Each therefore waits for an approval from a required reviewer before it starts.

## Who can run the release

The repository is public, but that does not let anyone run the release.

- **Triggering a run** (`workflow_dispatch`) requires **write access** to this repository. Outside
  contributors, including anyone with a fork, cannot start workflows here, and fork pull requests
  do not receive secrets.
- **Running past the first job** requires approval from a **required reviewer** of the
  `operator-release-approval` environment: currently `bobotimi` and the `nxrm-techleads` team.
  Approval from either releases the job. Until approved, the jobs do not start and the secrets are
  not released.
- **Secrets** (`RELEASE_PAT`) are environment secrets, only available to jobs that pass the
  approval. `RELEASE_PAT` belongs to a user authorised on the Red Hat Connect project. Image digests
  are read from Red Hat's public catalog, so no Red Hat API key is needed.
- **Merging workflow changes** needs one approving review on `main` (branch protection).

Things to be aware of:
- The environment's deployment branches are restricted to `main`, so a run started from any other
  branch (for example one with a modified workflow) is blocked before it can read the secrets. This
  also means workflow changes must be merged to `main` before they can be run.
- "Prevent self-review" is off, so the person who starts a run can also approve it.
- Repository admins can bypass the environment protection. This is deliberate ("Allow administrators to
  bypass configured protection rules" is on) so a release is not blocked if no listed reviewer is
  available.

## One-time repository setup

### 1. Create the `operator-release-approval` environment

GitHub repo → Settings → Environments → **New environment**

- Name: `operator-release-approval`
- Required reviewers: `bobotimi` and the `nxrm-techleads` team
- Deployment branches: **Selected branches** → add `main`

### 2. Add the environment secret

On the environment page → **Environment secrets**. This must be an environment secret, not a
repository secret, so it is only released after approval.

| Name | Value |
|---|---|
| `RELEASE_PAT` | **Fine-grained** GitHub personal access token (the `sonatype` org rejects classic tokens). Resource owner `sonatype`, access to `sonatype/operator-nexus-repository` and `sonatype/certified-operators`, repository permissions Contents, Pull requests and **Workflows** read/write (Workflows is needed for `gh repo sync` when upstream changed `.github/workflows`). **Must belong to a GitHub user listed in "Authorized Github User Accounts" on the [RH connect bundle project](https://connect.redhat.com/projects/64ef748bfe44a37dc8b33eea/settings).** Create it at github.com/settings/personal-access-tokens; a `sonatype` org owner must approve the request before it has any access. Fine-grained tokens expire (maximum one year), so note the expiry and renew before it. |
| `UPSTREAM_PR_PAT` | **Classic** GitHub personal access token with the `public_repo` scope, used only by the "Open PR to Red Hat upstream" step. A fine-grained token cannot open a PR on `redhat-openshift-ecosystem/certified-operators` because that repo is outside its resource owner. Must belong to a user listed in "Authorized Github User Accounts" (same as `RELEASE_PAT`). Never use it against `sonatype` resources. Classic tokens can expire too, so note the expiry. |

Never paste secret values into chat, tickets or logs.

The workflow no longer uses `RH_API_TOKEN`: the old Red Hat Connect endpoint it called
(`connect.redhat.com/api/v2/...`) now returns an HTML 404, and image digests are read from the public
catalog instead. The Jenkins jobs keep their own Red Hat API keys (`preflight --pyxis-api-token`,
keys listed at connect.redhat.com/account/api-keys). Any `RH_API_TOKEN` secret left on the environment
can be deleted.

### 3. Verify the PAT has write access to the fork

```bash
GH_TOKEN=<your-pat> gh repo view sonatype/certified-operators
```

The dry run also checks this for you.

## Dry run (rehearsal)

Use this whenever you want to check the automation without releasing. `dry_run` is **ticked by
default**.

GitHub Actions → **Operator Release** → **Run workflow** → keep `dry_run` ticked → enter versions.

- `prepare` validates the inputs, detects the previous version and shows the version-file diff in
  the job summary. It does not commit or push.
- `bundle-and-pr` generates the OLM bundle using **placeholder image SHAs** and lists the generated
  files and the `replaces`/`skipRange` values in the job summary. It checks the Red Hat catalog
  lookup by fetching the digests of the previous release and comparing them with its bundle, and that
  `RELEASE_PAT` has push access to `sonatype/certified-operators`. It warns if an open PR from
  `sonatype:main` would block a real run. It does not commit, push to the fork or open a PR. The
  lookup of the new images cannot be tested in a dry run, because they are not published yet.
- Both approvals are still required. No Jenkins builds are needed: approve the second one straight
  away.

Untick `dry_run` only for a real release.

## Release steps

### Step 1: Trigger the workflow

GitHub Actions → **Operator Release** → **Run workflow** (branch `main`)

| Input | Example | Notes |
|---|---|---|
| `operator_version` | `3.96.4-1` | New operator version being released |
| `cert_app_version` | `3.96.4-ubi-1` | UBI app image tag that will appear at Red Hat after the build |
| `dry_run` | unticked for a real release | Default is ticked |

Approve the first gate (**Review pending deployments**). The `prepare` job then validates the
versions, auto-detects the previous version, updates `Chart.yaml`, `values.yaml` and
`build/Dockerfile`, and commits them to `main`. The job summary shows the detected previous version
and the Jenkins links. **Check the detected version there and cancel the run if it is wrong.**

### Step 2: Build the images in Jenkins (manual)

1. **Update `docker-nexus3`**: edit `Dockerfile.rh.ubi.java21` (`version`/`release` labels at lines
   23–24 and the `NEXUS_VERSION`, download URL and SHA-256 `ARG`s at lines 42–44) to the new NXRM
   version, then trigger
   [docker-nexus-repository-red-hat-release](https://jenkins.ci.sonatype.dev/job/integrations/job/cloud/job/Red%20Hat/job/docker-nexus-repository-red-hat-release/).
   Build from the commit with the version you are releasing: `main` may already contain a newer NXRM
   version.
2. **Build the operator image**: trigger
   [operator-nexus-repository-release](https://jenkins.ci.sonatype.dev/job/nxrm/job/Red%20Hat/job/operator-nexus-repository-release/)
   with version `<operator_version>`.
3. Wait about 30 minutes for both builds and Red Hat publishing (including the scan) to finish.
4. **Check the `latest` tag.** Red Hat usually moves `latest` to the new image on its own. If it does
   not, run **Sync Tags** on the image in Red Hat Connect: the
   [Nexus Repository Red Hat Universal Base Image](https://connect.redhat.com/projects/5e61d90a38776799eb517bd2/images)
   (app) and the
   [Nexus Repository HA Certified Operator](https://connect.redhat.com/projects/64d3814688a42145092bb0ff/images)
   (operator). The workflow only waits for the version tag to be published and certified, so it does
   not notice a stale `latest`, and users pulling `latest` would miss the release.

### Step 3: Approve the second gate

When both images show as published at connect.redhat.com, click **Review pending deployments** →
**Approve**. `bundle-and-pr` then (240-minute job timeout):

- confirms the previous version is still the latest on `main`
- polls the Red Hat catalog for both image SHAs (every 60 s, up to 90 min). An image counts once it
  is published and marked certified; the lookup fails if the catalog returns different digests for
  one tag
- generates the OLM bundle with `scripts/new_version.sh bundle`
- syncs the `sonatype/certified-operators` fork, copies the bundle in, pushes it
- opens a PR to `redhat-openshift-ecosystem/certified-operators`
- waits for Red Hat to merge it, then commits the bundle to `main`

### Step 4: Review the PR

The job summary links the PR. The workflow then waits for it (up to 2 hours, or until the PR fails). Red Hat's
certification pipeline validates the submission, which typically takes 35 to 55 minutes (recent PRs: 36, 37 and 54 minutes from pipeline start to merge, of which the preflight test is 20 to 35), and
auto-merges on pass.

- **Merged:** the workflow commits the bundle to `main` and finishes. Only now is the release
  recorded in this repository.
- **Pipeline failed (PR stays open):** Red Hat marks the PR with the `operator-hosted-pipeline/failed` label and the job stops early and fails, with
  **nothing committed to `main` for the bundle**. Red Hat leaves the PR open, so fix it there: read the bot's Pipeline Summary comment and
  push a change to the PR branch (`main` of `sonatype/certified-operators`). That re-runs Red Hat's
  validation on the same PR. Do **not** re-run the release workflow, because it would fail on the
  open PR. If the failure was on Red Hat's side (as in September 2025, when a pipeline bug failed the preflight test), comment `/pipeline restart operator-hosted-pipeline` on the PR instead of changing anything. When the PR merges, run **Operator Release - Finalize** (below).
- **Not merged in time, or merged later:** the job fails after the 2-hour wait. When the PR
  merges, run **Operator Release - Finalize**.
- **Closed without merging:** nothing was committed to `main`. Fix the cause and re-run the release.

### Step 4b: Finalize (after fixes, or when Red Hat merged late)

GitHub Actions → **Operator Release - Finalize** → **Run workflow** (branch `main`).

- `operator_version`: leave **blank** to use the latest PR opened from `sonatype:main`, or enter the
  version (for example `3.96.4-1`). GitHub cannot pre-fill this field with the expected version, so
  blank means "the PR the release workflow opened".
- Keep `dry_run` ticked first to see the change, then untick it.
- It refuses to run unless that PR is **merged**. It copies the merged `manifests/` and `metadata/`
  from `redhat-openshift-ecosystem/certified-operators` into
  `deploy/olm-catalog/nexus-repository-ha-operator-certified/<version>/` and commits to `main`, so
  any correction made in the PR is kept.
- It uses the same `operator-release-approval` environment, so it needs the same approval.

If a fix was needed, also correct its cause in the bundle templates or `scripts/new_version.sh`
through a normal PR, otherwise the next release repeats the problem.

Do not start another release while the PR is open, because a second PR from `sonatype:main` is
rejected.

### Step 5: Finish up

The workflow (or Finalize) tags the commit that holds the bundle with `<operator_version>` and pushes
the tag. It skips if the tag already exists on `origin`. The tag step needs `RELEASE_PAT` to have
Contents read/write, which it already does.

Set the Jira fix version via the
[Jenkins job](https://jenkins.ci.sonatype.dev/job/integrations/job/Set%20Jira%20Fix%20Version/).

## Version rules and patch releases

- `operator_version` must look like `3.96.4-1` and `cert_app_version` like `3.96.4-ubi-1`.
- The **previous version** is auto-detected as the highest directory under
  `deploy/olm-catalog/nexus-repository-ha-operator-certified/` (version sort). It feeds the CSV
  field `olm.replaces`. `olm.skipRange` is `<operator_version`.
- `operator_version` must be newer than the previous version.
- **Patch releases** need nothing special: `3.96.4-1` after `3.96.0-1` gives `replaces: 3.96.0-1`,
  `skipRange: <3.96.4-1`, app version `3.96.4`, chart version `96.4.0`.
- **Backports are not supported.** The operator publishes to a single `stable` channel where each
  release replaces exactly one earlier release, and `package.yaml` points the channel head at the
  version being released. A backport such as `3.90.4-1` replacing `3.90.3-1` would create a second
  channel head and move the head backwards, which is an invalid catalog. Supporting it would need a
  separate channel per release line (templates and package file changes), so the workflow rejects
  any `operator_version` older than the latest release.

## Troubleshooting

### If the first job fails

Nothing has been published. Fix the cause and re-run the workflow. If `prepare` pushed its commit
before failing, check `main` before re-running.

### If `bundle-and-pr` fails

The `prepare` commit is already done. In the Actions UI use **Re-run failed jobs** (not "Re-run all
jobs") to rerun only `bundle-and-pr` with the same inputs. Re-running a job that uses the
environment asks for approval again.

| Symptom | Fix |
|---|---|
| SHA not found within 90 min | Confirm the image is published and certified at connect.redhat.com. The lookup can also be tried by hand: `scripts/get-rh-image-sha.sh <tag> <registry>/sonatype/<image>` |
| "Red Hat catalog returned HTTP ..." | The catalog API is down or its address changed. Retry later, or check `https://catalog.redhat.com/api/containers/v1` |
| `new_version.sh bundle` fails | Check script output for the exact error, fix if needed, then re-run |
| Fork push conflict | RH upstream merged new changes. `gh repo sync` in `bundle-and-pr` mitigates this; if it still fails, manually sync the fork and re-run |
| PR already exists (open from a previous release) | Merge or close the existing PR, then re-run only `bundle-and-pr` |
| Red Hat pipeline failed on the PR | Push a fix (or comment `/pipeline restart operator-hosted-pipeline`), then run Operator Release - Finalize once it merges. Do not re-run the release |
| PR closed without merging | Nothing was committed for the bundle. If the PR can be reopened after a fix, do that and run Finalize once it merges; otherwise fix the cause and re-run the release |
| "previous_version ... no longer matches" | Another release landed on `main` during the wait. Re-run the whole workflow from the start so the previous version is re-detected |
| "operator_version ... is older than the latest released version" | Wrong version typed. Backports are not supported (see above) |
| "`sonatype` forbids access via a personal access token (classic)" | `RELEASE_PAT` holds a classic token. Replace it with a fine-grained one (see Secrets) |
| `Resource not accessible by personal access token (createPullRequest)` | The PR step is using a fine-grained token. It must use the classic `UPSTREAM_PR_PAT` environment secret |
| `Upstream commits contain workflow changes, which require the workflow scope` | `RELEASE_PAT` lacks the Workflows read/write permission. Add it, or click Sync fork on `sonatype/certified-operators`, then re-run only `bundle-and-pr` |
| Empty token / authentication errors | The job did not get the environment secret: check `RELEASE_PAT` is an environment secret on `operator-release-approval` and the run was approved |

## First-release comparison

On the first real release using this workflow, run it **in parallel** with the existing manual
process. Compare the generated bundle files against what you would have produced manually. Only
retire the manual steps once the outputs match.
