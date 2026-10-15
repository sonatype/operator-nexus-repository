# operator-nexus-repository
IBM Operator for Sonatype Nexus Repository

# Releasing

Releases of the operator are done with the `Operator Release` GitHub Actions workflow. See
[docs/releasing.md](docs/releasing.md) for the full process: who can run it, the dry-run mode, the
step-by-step release, patch and backport releases, and troubleshooting.

### Happy path

1. Run **Operator Release** with `dry_run` off and approve the first gate. The version files are
   updated on `main`.
2. Build the app and operator images in Jenkins and wait for Red Hat to publish them.
3. Approve the second gate. The workflow reads both image digests from Red Hat's catalog, generates
   the OLM bundle, pushes it to the `sonatype/certified-operators` fork and opens a PR to
   `redhat-openshift-ecosystem/certified-operators`.
4. Red Hat's pipeline validates the PR (usually 15 to 30 minutes) and merges it.
5. The workflow sees the merge, commits the bundle to `main` and finishes. Then tag the release and
   set the Jira fix version.

Rehearse first with `dry_run` ticked (the default): nothing is committed, pushed or opened.

### When something goes wrong

| Scenario | What the workflow does | What you do |
|---|---|---|
| Images not yet published at Red Hat | Polls every 60 s for up to 90 min, then fails. Nothing was published. | Check Jenkins and Red Hat, then **Re-run failed jobs**. |
| Catalog unavailable, or different digests for one tag | Fails immediately and refuses to guess. | Retry later, or investigate the catalog. |
| Red Hat's checks fail on the PR (PR stays open) | Stops early with an error. Nothing is committed to `main` for the bundle. | Push a fix to the PR branch (`main` of the fork). Red Hat re-validates the same PR. When it merges, run **Operator Release - Finalize**. Do not re-run the release. |
| PR not merged within 60 min | Fails after the wait. Nothing is committed to `main` for the bundle. | When the PR merges, run **Operator Release - Finalize**. |
| PR closed without merging | Fails. Nothing is committed to `main` for the bundle. | Fix the cause and re-run the release. |
| Another release PR is already open | Fails before opening a new one. | Merge or close the old PR first. |
| Re-run after a partial run | Skips the version-file commit if the files are already updated. | **Re-run failed jobs**. |

**Operator Release - Finalize** copies the bundle that Red Hat actually merged (including any fixes
made in the PR) into `deploy/` on `main`. Leave its version blank to use the latest PR opened from
`sonatype:main`. If a fix was needed, also correct its cause in the bundle templates or
`scripts/new_version.sh`, so the next release does not repeat it.

# Pre-requisites

### Storage
The default configuration uses an emptyDir volume for storing Nexus Repository logs. However, we strongly recommend that 
you configure dynamic provisioning of persistent storage based on your deployment environment as explained below.
    
#### Cloud deployments (AWS/Azure)
* Ensure the appropriate Container Storage Interface (CSI) driver(s) are installed for your chosen OpenShift cloud deployment. Please refer to OpenShift documentation for details on configuring CSI drivers. 
  
Note: if you're using Red Hat OpenShift on AWS (ROSA), CSI drivers for dynamically provisioning EBS volumes are installed by default; you should see associated storage classes for them in your cluster web console similar to what's shown below:

  ![ROSA Default Storage Classe](doc%2Fimages%2Frosa%20default%20storage%20classes.png)

#### On premise deployments
1. Attach separate disks (i.e. separate from the root disk) to your worker nodes.
2. Install the Local Storage Operator. Please refer to Open Shift [persistent storage](https://docs.openshift.com/container-platform/4.13/storage/persistent_storage/persistent_storage_local/persistent-storage-local.html) documentation
  and the [Local Storage Operator](https://github.com/openshift/local-storage-operator) documentation
3. Use the Local Storage Operator to automatically create persistent volumes for your chosen storage class name as documented [here](https://docs.openshift.com/container-platform/4.13/storage/persistent_storage/persistent_storage_local/persistent-storage-local.html)

#### Configuring the operator for dynamic persistent volume provisioning
* Set the `nexusData.storageClass.name` parameter to a storage class name. This could be one of the default storage classes automatically created in your OpenShift cluster (e.g., if you're using ROSA) or one that you would like the operator to create.
  * If you would like to create a dedicated storage class (i.e., you don't want to use the default), then in addition to specifying a value for `nexusData.storageClass.name`, you must also set `nexusData.storageClass.enabled` parameter to `true`.
  * Set the `nexusData.volumeClaimTemplate.enabled` parameter to true.

## Upgrade Notes

### PersistentVolumeClaim (PVC) Naming Changes

**Starting from version 3.85.0+**, the StatefulSet naming pattern has been updated to remove the chart version component. This ensures that PVCs maintain consistent names across operator upgrades, enabling proper data persistence.

**Previous naming pattern:**
- StatefulSet: `nxrm-ha-<chart-version>-nexusrepo-statefulset` (e.g., `nxrm-ha-84-0-0-nexusrepo-statefulset`)
- PVC: `nexusdata-nxrm-ha-<chart-version>-nexusrepo-statefulset-<ordinal>`

**New naming pattern:**
- StatefulSet: `nxrm-ha-nexusrepo-statefulset`
- PVC: `nexusdata-nxrm-ha-nexusrepo-statefulset-<ordinal>`

#### Upgrading from versions prior to 3.85.0

Since StatefulSet names are immutable in Kubernetes, upgrading from older versions requires manual intervention to preserve your data. **Note**: PVC names cannot be renamed in Kubernetes, so we must recreate the PVC while preserving the underlying PersistentVolume.

**Prerequisites:**
- Ensure you have a backup of your Nexus Repository data
- Plan for downtime during the migration process
- Test this procedure in a non-production environment first

**Migration Steps:**

1. **Backup your data** - This is critical before proceeding!

2. **Identify your current resources:**
   ```bash
   kubectl get statefulset,pvc,pv -n <namespace> | grep nexus
   ```
   Note the names of your StatefulSet, PVC, and the bound PV.

3. **Get the PersistentVolume name bound to your PVC:**
   ```bash
   export OLD_PVC_NAME="nexusdata-nxrm-ha-<version>-nexusrepo-statefulset-0"
   export PV_NAME=$(kubectl get pvc $OLD_PVC_NAME -n <namespace> -o jsonpath='{.spec.volumeName}')
   echo "PV Name: $PV_NAME"
   ```

4. **Ensure the PV reclaim policy is set to Retain** (prevents data loss when PVC is deleted):
   ```bash
   kubectl patch pv $PV_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
   ```

5. **Scale down the StatefulSet to 0 replicas:**
   ```bash
   kubectl scale statefulset <old-statefulset-name> --replicas=0 -n <namespace>
   ```
   Wait for all pods to terminate.

6. **Delete the old PVC** (the PV will be retained due to the Retain policy):
   ```bash
   kubectl delete pvc $OLD_PVC_NAME -n <namespace>
   ```

7. **Delete the old StatefulSet:**
   ```bash
   kubectl delete statefulset <old-statefulset-name> -n <namespace>
   ```

8. **Release the PV by removing the claimRef** (allows it to be bound to a new PVC):
   ```bash
   kubectl patch pv $PV_NAME -p '{"spec":{"claimRef":null}}'
   ```
   Verify the PV status changes to "Available":
   ```bash
   kubectl get pv $PV_NAME
   ```

9. **Deploy the upgraded operator** with the fixed naming pattern. The new StatefulSet will be created with the name `nxrm-ha-nexusrepo-statefulset`, and it will create a new PVC named `nexusdata-nxrm-ha-nexusrepo-statefulset-0`.

10. **Verify the new PVC has bound to your existing PV:**
    ```bash
    kubectl get pvc -n <namespace>
    kubectl get pv $PV_NAME
    ```
    The PVC should show status "Bound" and should be bound to your existing PV (which contains your data).

11. **Verify the StatefulSet pod is running and using the correct volume:**
    ```bash
    kubectl get pods -n <namespace>
    kubectl describe pod nxrm-ha-nexusrepo-statefulset-0 -n <namespace> | grep -A 5 "Volumes:"
    ```

**Important Notes:**
- If the new PVC doesn't automatically bind to the released PV, you may need to edit the PV's `spec.claimRef` to explicitly point to the new PVC name before deploying
- For dynamic provisioning scenarios where you cannot preserve the PV, consider backing up data, performing a fresh install, and restoring the data
- After successful migration, future upgrades will not require these steps as the StatefulSet name will remain constant