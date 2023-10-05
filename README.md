# operator-nexus-repository
IBM Operator for Sonatype Nexus Repository

# Pre-requisites

### Storage
The default configuration uses an emptyDir volume for storing Nexus Repository logs. However, we strongly recommend that 
you configure dynamic provisioning of persistent storage based on your deployment environment as explained below.
    
#### Cloud deployments (AWS/Azure)
* Ensure the appropriate Container Storage Interface (CSI) driver(s) are installed for your chosen OpenShift cloud deployment. Please, refer to OpenShift documentation for details on configuring CSI drivers. 
  
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