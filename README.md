# operator-nexus-repository
IBM Operator for Sonatype Nexus Repository

# Pre-requisites

## Storage

### Local storage

By default, this chart uses local volume storage. You'll need to create a directories
on each node in your Kubernetes/Open shift cluster for storing nexus repository runtime (logs, config dump etc) data. 
The following constraints should be adhered to regarding the names and number of directories to create on each node.

* The directory names must have the prefix specified for the ```nexusData.pv.directoryPrefix``` specified in the [values.yaml](helm-charts%2Fsonatype-nexus-repository%2Fvalues.yaml). It is best for this to be a sub dorectory of ```/var``` 

* The directory names must have an integer as the suffix beginning with 0.

* The number of directories you create should be driven by the value specified for the ```statefulset.replicaCount``` in the 
 [values.yaml](helm-charts%2Fsonatype-nexus-repository%2Fvalues.yaml).

* You must chown all the directories you create to ```200:200```

* For example, if the value of ```nexusData.pv.directoryPrefix``` is ```/var/nexus-repo-work/work``` and ```statefulset.replicaCount``` is 3, then you should create the following directories on each node:

```
mkdir -p /var/nexus-repo-work/work0
mkdir -p /var/nexus-repo-work/work1
mkdir -p /var/nexus-repo-work/work2
```

and chown: ```chown -R 200:200 /var/nexus-repo-work/ ```


### Network storage
This chart also support NFS storage. If you wish to use NFS storage do as follows:
* Set ```nexusData.nfs.enabled``` to true in your values.yaml 
* Set ```nexusData.local.enabled``` to false in your values.yaml
* Apply addition configuration for your NFS via the ```nexusData.nfs``` section in your values.yaml
  * Create directories on your NFS server based on the following constraints:
      * The directory names must have the prefix specified for the ```nexusData.pv.directoryPrefix``` specified in the [values.yaml](helm-charts%2Fsonatype-nexus-repository%2Fvalues.yaml).
      * The directory names must have an integer as the suffix beginning with 0.
      * The number of directories you create should be driven by the value specified for the ```statefulset.replicaCount``` in the [values.yaml](helm-charts%2Fsonatype-nexus-repository%2Fvalues.yaml).
      * You must set appropriate write permissions for all subdirectories 
      * For example, if the value of ```nexusData.pv.directoryPrefix``` is ```/nexus-repo-work/work``` and ```statefulset.replicaCount``` is 3, then you should create the following directories on each node:
          ```
          mkdir -p /nfs_root/nexus-repo-work/work0
          mkdir -p /nfs_root/nexus-repo-work/work1
          mkdir -p /nfs_root/nexus-repo-work/work2
          ```
      * Ensure the appropriate write permissions are set for the above subdirectories on your NFS server