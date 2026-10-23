# Applying the eMudhra CA fix on older Nexus Repository HA Operator releases

> Draft, not yet published. The patched application images for the older lines have not been
> released yet, so the table in step 1 is a placeholder. Fill it in and complete the checklist
> at the end before publishing.

## Who this applies to

You run the Nexus Repository HA Operator from the OpenShift certified catalog at version
3.80.0-1 through 3.96.4-1 and haven't moved to 3.97.2-1 or later.

## What's affected

The Nexus Repository application image trusts certificate authorities from the compromised
eMudhra hierarchy (advisory: https://emudhra.we-have-a-problem.com/). Sonatype is releasing
patched application images for each supported release line.

## What we're doing and not doing

- **Operator 3.97.2-1** carries the fix for both the application image and the operator
  image. Upgrading to it also moves Nexus to the 3.97 line, so plan it as a Nexus upgrade.
- **Operator releases 3.80.0-1 through 3.96.4-1 are not being rebuilt.** Their operator
  images are unchanged. The operator image's OS trust bundle still includes the affected
  roots, but practical exposure is low: the operator mainly talks to the Kubernetes API,
  which is verified against the cluster CA, not the system bundle (NEXUS-56000, PR #76).
  [Not from the PR: the decision not to rebuild. Confirm it with the NEXUS-56000 author
  and security before publishing.]
- **Stay on your line and patch only the application image** using the steps below.

## Steps

1. Find your line in the table and copy the image reference:

   | Your Nexus line | Patched application image |
   |---|---|
   | 3.80.x | `registry.connect.redhat.com/sonatype/nexus-repository-manager@sha256:<3.80.1 digest>` |
   | 3.84.x | `registry.connect.redhat.com/sonatype/nexus-repository-manager@sha256:<3.84.x digest>` |
   | 3.90.x | `registry.connect.redhat.com/sonatype/nexus-repository-manager@sha256:<3.90.x digest>` |
   | 3.96.x | `registry.connect.redhat.com/sonatype/nexus-repository-manager@sha256:<3.96.x patched digest>` |

   **Disconnected or mirrored clusters:** mirror this digest into your registry first (for
   example with `oc image mirror`, or as an additional image in your `oc-mirror`
   `ImageSetConfiguration`), and make sure your image mirror rules cover
   `registry.connect.redhat.com/sonatype/nexus-repository-manager`. Your existing mirror was
   built from the operator bundle's `relatedImages`, which still lists the original,
   unpatched digest.

2. Edit your `NexusRepo` resource and set the image:

   ```yaml
   spec:
     statefulset:
       container:
         imageName: registry.connect.redhat.com/sonatype/nexus-repository-manager@sha256:<digest for your line>
   ```

3. The operator updates the StatefulSet and the pods restart. Plan this as a rolling
   restart in a maintenance window.

4. Verify:

   ```
   oc get pods -l app=nxrm -o jsonpath='{.items[*].spec.containers[?(@.name=="nxrm-app")].image}'
   ```

   The output should show the digest from step 1.

## Notes

- The `imageName` value in your `NexusRepo` resource controls the running Nexus image, not
  the operator bundle. Operator upgrades alone don't change it if you've set it explicitly.
- The older operator bundles still list the original application image digest in their
  `relatedImages`, in the `RELATED_IMAGE_NEXUS` environment variable and in the sample
  resource. Published bundles can't be changed, so catalog scanners will still report that
  digest for these versions even after you apply the override. Upgrading to 3.97.2-1 or
  later removes the discrepancy.
- Use the digest form, not a tag, so you can see exactly what's running.
- Stay on the same Nexus line. Don't jump lines using this procedure.
- If you use `imagePullSecrets`, no change is needed for this procedure. It only matters if
  you upgrade the operator, since the chart version appears in that secret's name.

## Before publishing (remove this section)

- [ ] Wait for the patched application images for 3.80, 3.84, 3.90 and 3.96 to be released
      (not yet created). Then fill in the digests with
      `scripts/get-rh-image-sha.sh <tag> registry.connect.redhat.com/sonatype/nexus-repository-manager`
      using the real tags. Table placeholders and the tag name `3.80.1-ubi-1` are assumed.
- [x] 3.97.2-ubi-1 contains the fix (confirmed), so the 3.97.2-1 statement above stands.
- [ ] Test the override on a cluster: that `imageName` beats the CSV's `RELATED_IMAGE_NEXUS`,
      and what the pod restart looks like (step 3 is untested).
- [ ] Check the `app=nxrm` label selector in step 4 against a real deployment.
- [ ] Ask the owner of NEXUS-56000 whether the operator contacts anything other than the
      Kubernetes API using the system CA bundle (PR #76 says "mainly"), and measure the
      released 3.96.4-1 operator image, which the PR lists as not done.
- [ ] Test the disconnected case: that a cluster mirrored from the old bundle can pull the
      separately mirrored patched digest, and what mirror rules (IDMS/ICSP) it needs.
- [ ] Get security and compliance sign-off on leaving the old operator images unpatched, and
      on the `relatedImages` mismatch, since the old bundles can't be corrected without
      per-line releases.
- [ ] Decide where it's published: this repo's `docs/`, Sonatype's public docs, or a support notice.
- [ ] Confirm Sonatype supports operator customers staying on 3.80 and 3.84. If not, shrink the table.
