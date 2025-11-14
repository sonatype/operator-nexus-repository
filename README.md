# operator-nexus-repository
IBM Operator for Sonatype Nexus Repository

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

Since StatefulSet names are immutable in Kubernetes, upgrading from older versions requires manual intervention to preserve your data:

1. **Backup your data** before proceeding with the upgrade
2. Note your current PVC names: `kubectl get pvc -n <namespace>`
3. Scale down the current deployment to 0 replicas
4. Delete the old StatefulSet (without deleting pods/PVCs):
   ```bash
   kubectl delete statefulset <old-statefulset-name> --cascade=orphan -n <namespace>
   ```
5. If using pre-provisioned storage, rename your PVCs to match the new naming pattern:
   ```bash
   kubectl patch pvc <old-pvc-name> -p '{"metadata":{"name":"<new-pvc-name>"}}' -n <namespace>
   ```
   Alternatively, update the PV's `claimRef` to point to the new PVC name
6. Apply the operator upgrade
7. Verify that the new StatefulSet is using your existing PVCs

For production environments, we recommend testing this upgrade process in a non-production environment first.