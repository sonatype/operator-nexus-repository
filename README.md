# operator-nexus-repository
IBM Operator for Sonatype Nexus Repository

# Pre-requisites

### Storage
The default configuration uses an emptyDir volume for storing Nexus Repository logs. However, we strongly recommend that 
you configure dynamic provisioning of persistent storage based on your deployment environment as explained below.
    
#### Cloud deployments (AWS/Azure/Google Cloud)
* Ensure the appropriate Container Storage Interface (CSI) driver(s) are installed for your chosen OpenShift cloud deployment. Please, refer to OpenShift documentation for details on configuring CSI drivers.

#### On premise deployments
1. Attach separate disks (i.e. separate from the root disk) to your worker nodes.
2. Install the Local Storage Operator Please refer to Open Shift documentation: https://docs.openshift.com/container-platform/4.13/storage/persistent_storage/persistent_storage_local/persistent-storage-local.html
  and the Local Storage Operator documentation: https://github.com/openshift/local-storage-operator
3. Use the Local Storage Operator to automatically create persistent volumes for your chosen storage class name.
4. Specify the storage class name from step 3 as the value of the `nexusData.storageClass.name` property and also set `nexusData.volumeClaimTemplate.enabled` to true.