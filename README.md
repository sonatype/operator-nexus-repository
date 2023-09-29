# operator-nexus-repository
IBM Operator for Sonatype Nexus Repository

# Pre-requisites

### Storage
The default configuration uses an emptyDir volume for storing Nexus Repository logs. However, we strongly recommend that 
you configure dynamic provisioning of persistent storage based on your deployment environment as explained below.
    
#### Cloud deployments (AWS/Azure/Google Cloud)
* Ensure the appropriate Container Storage Interface (CSI) driver(s) are installed for your chosen OpenShift cloud deployment. Please, refer to OpenShift documentation for details on configuring CSI drivers.

#### On premise deployments
* Attach separate disks (i.e. separate from the root disk) to your worker nodes and use the local volume provisioner to dynamically request storage via your chosen storage class.
