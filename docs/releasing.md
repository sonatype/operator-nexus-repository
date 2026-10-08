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
| `RELEASE_PAT` | GitHub Personal Access Token with `repo` scope. **Must belong to a GitHub user listed in "Authorized Github User Accounts" on the [RH connect bundle project](https://connect.redhat.com/projects/64ef748bfe44a37dc8b33eea/settings).** Generate at github.com/settings/tokens → Tokens (classic). A fine-grained PAT scoped to `sonatype/certified-operators` (contents + pull requests: read/write) is a more secure alternative if supported by the RH connect project requirements. |

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

1. **Update `docker-nexus3` Dockerfile** — edit `Dockerfile.rh.ubi.java21` lines 23–24 and
   42–44 to reference the new NXRM version, then trigger:
   [docker-nexus-repository-red-hat-release](https://jenkins.ci.sonatype.dev/job/integrations/job/cloud/job/Red%20Hat/job/docker-nexus-repository-red-hat-release/)

2. **Build the operator image** — trigger with version `<operator_version>`:
   [operator-nexus-repository-release](https://jenkins.ci.sonatype.dev/job/nxrm/job/Red%20Hat/job/operator-nexus-repository-release/)

3. Wait ~30 minutes for both builds and Red Hat publishing to complete.

### Step 3 — Approve the gate

In the workflow run, click **Review pending deployments** → **Approve**.

The `bundle-and-pr` job runs automatically (120-minute job timeout):
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

## If `bundle-and-pr` fails

The `prepare` commit and `await-builds` approval are already done — you do not need to repeat
them. In the GitHub Actions UI, click **Re-run failed jobs** (not "Re-run all jobs") to rerun
only `bundle-and-pr` with the same inputs.

Common causes and fixes:

| Symptom | Fix |
|---|---|
| SHA not found within 90 min | Confirm the image is live at connect.redhat.com, then re-run |
| `new_version.sh bundle` fails | Check script output for the exact error, fix if needed, then re-run |
| Fork push conflict | RH upstream merged new changes; `gh repo sync` in `bundle-and-pr` mitigates this, but if it still fails, manually sync the fork and re-run |
| PR already exists (open from a previous release) | The job fails with an error message. Merge or close the existing PR, then re-run only `bundle-and-pr`. |

---

## First-release dry run

On the first real release using this workflow, run it **in parallel** with the existing manual
process. Compare the generated bundle files against what you would have produced manually. Only
retire the manual steps once the outputs match.
