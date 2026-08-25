---
myst:
  html_meta:
    description: "An explanation and comparison of the two approaches to disaster recovery supported by LXD: replicators and storage replication."
---

(exp-disaster-recovery)=
# Disaster recovery

## Approaches to disaster recovery

You can prepare for cross-site, active-passive disaster recovery by setting up at least two LXD deployments: a primary deployment that runs day-to-day workloads, and a standby that is ready to take over if the primary deployment fails.
To minimize data loss in the event of a disaster (the recovery point objective, or RPO), data from the primary deployment must be regularly backed up on the standby.
A mechanism to efficiently promote the standby to take over workloads is also critical for minimizing downtime (the recovery time objective, or RTO).

LXD supports two approaches to active-passive disaster recovery, each of which use different mechanisms for replication and recovery:

1. You can use LXD replicators to manage both replication and recovery.
   Replicators are LXD entities that regularly sync instances between two clusters through cluster links.
   Following a disaster, you can also use replicators to fail over from the primary to the standby deployment.
2. Alternatively, LXD provides a recovery tool to support disaster recovery if you have configured replication at the storage array level.
   In this setup, you must configure replication separately, through your remote storage vendor.
   After a disaster, you can use the `lxd recover` command to recreate the primary LXD deployment on the standby.

We recommend that you use replicators to manage disaster recovery end-to-end with LXD.
Use storage replication when you require replication at the storage array level, or if you are unable to use cluster links.

The table below provides a comparison of these two approaches; detailed explanations are provided in the sections that follow.

```{table} Comparison of replicators and storage replication
:name: replicator_storage_replication_comparison

| | Replicators | Storage replication |
|---|---|---|
| **Level** | LXD instance layer | Storage array layer |
| **Replication mechanism** | Incremental instance refresh over cluster links | Vendor storage replication (Ceph RBD mirroring, PowerFlex RCG, etc.) |
| **Scheduling** | Controlled by LXD ({config:option}`replicator-conf:schedule` config key) | Controlled by the storage vendor |
| **Requires cluster link** | Yes | No |
| **Recovery method** | Promote standby project with the LXD CLI or UI | Promote storage array, then run `lxd recover` |
| **Snapshot support** | Automatic pre-replication snapshots | Depends on storage vendor |
```

(exp-replicators)=
## Replicators

(exp-replicators-concepts)=
### Leader and standby projects

To set up replication between two clusters, you must create projects with the same name on both clusters, as well as a replicator on the leader cluster.

In the process, you must configure the project on the standby cluster with a {config:option}`project-replica:replica.cluster` configuration key that identifies the cluster link through which the project will receive replication data.
You do not need to configure the project on the leader cluster with this key, because the replicator defines the cluster link through which to send replication data.

Replication is then configured at the project level.
Every project has a replica mode:

- `leader`: The project is writable.
  Instances in this project are the source of replication.
  The replicator runs from this cluster.
- `standby`: Instances in this project are replicas, kept in sync by the replicator.
  New instances cannot be created directly in this project, and existing instances cannot be started.
  The project must be promoted to `leader` during a failover before instances can be started.
- (empty): The project is not part of any replication setup.
  This is the default for new projects.

You can manage the replica mode through the LXD CLI or UI.
For details, refer to {ref}`howto-replicators-dr`.
Note that the replica mode is not a configuration key and cannot be set in the same way as configuration options.

(exp-replicators-how)=
### How replication works

When a replicator runs, LXD performs an incremental refresh of every instance in the leader project to the standby project.
Instances that do not yet exist on the standby are created; existing instances are updated to match the leader's current state.

Before each refresh, LXD creates a point-in-time snapshot of each instance on the leader.
This provides a consistent rollback point on the source cluster in case anything goes wrong during replication.
The exception is instances that already have a {config:option}`instance-snapshots:snapshots.schedule` configured: their scheduled snapshots already provide point-in-time history, so LXD skips the extra snapshot to avoid redundancy.

Replication can be triggered manually through the LXD CLI or UI, or scheduled automatically using a cron expression in the {config:option}`replicator-conf:schedule` configuration key.
For details, see the instructions on {ref}`running replicators <howto-replicators-run>`.

(exp-replicators-failover)=
### Failover and recovery

If the leader cluster fails, you can {ref}`promote the standby project <>`.
This makes the project writable and allows instances to be started.
If the leader cluster is unreachable, validation against it is skipped automatically.
You can can force-promote a cluster to skip all validation, which is useful when the leader is known to be down or during a planned takeover.

When the original leader comes back online, you can re-sync the cluster with the new leader by running the replicator in restore mode, then returning both projects to their original roles.
In restore mode, the remote leader's instance list is used as the authoritative source: instances that were created on the new leader after failover are also created on the recovering cluster, not just the instances that existed before the failure.

See {ref}`howto-replicators-dr` for step-by-step instructions.

## Storage replication

### Replication and promotion

Disaster recovery with storage replication relies on the storage layer to replicate instances and custom volumes to the standby deployment.
If a disaster occurs, you can consolidate the storage layer and recover the resources to make them available on the standby.

You must configure replication outside of LXD, according to the concepts and constructs of the storage vendor.
Likewise, when a disaster occurs, you must use the storage vendor to promote the standby storage array to become the active deployment.

LXD provides support for this recovery process through the `lxd recover` CLI command, which facilitates recovering the workload on the secondary deployment.

(disaster-recovery-replication-limitations)=
### Known storage array limitations

Recovery with storage replication is only possible when using remote {ref}`storage-drivers` that support volume recovery (see {ref}`storage-drivers-features`).
When setting up replication, consider the following limitations:

(disaster-recovery-replication-limitations-powerflex)=
#### PowerFlex

Cannot replicate and recover volumes with snapshots
: In {ref}`PowerFlex <storage-powerflex>`, a volume's snapshot appears as its own volume but is still logically connected to its parent volume (vTree).
  When replicating a volume inside a RCG, its snapshots are not replicated; this causes inconsistencies on the secondary location.
  A volume's snapshot can be replicated but will be placed inside a new vTree, losing the logical relation to its parent volume.
  During recovery, LXD notices this inconsistency and raises an error.

(disaster-recovery-replication-cephrdb)=
#### Ceph RBD

Cannot use journaling mode
: On {ref}`Ceph RBD <storage-ceph>` storage arrays, it's possible to configure mirroring using either journaling or snapshot mode.
  However, with LXD, only snapshot mode is supported. This is because the volumes need to be mapped to the host for read access during recovery, which might not be possible due to missing kernel features.

## `lxd recover`

LXD provides a tool for recreating a {ref}`LXD database <database>` based on data in storage pools.
You can use this tool 

in the recovery process when This tool can be used to support cross-site disaster recovery with storage replication.


This tool can be used for disaster recovery when the LXD database is corrupted or lost, but the storage pools remain.

LXD provides a tool for disaster recovery in case the {ref}`LXD database <database>` is corrupted or otherwise lost.

The tool scans the storage pools for instances and imports the instances, custom volumes and buckets that it finds back into the database.
You need to re-create the required entities that are missing (usually pools, profiles, projects, and networks).

```{important}
This tool should be used for disaster recovery only.
Do not rely on this tool as an alternative to proper backups; you will lose data like profiles, network definitions, or server configuration.

The tool must be run interactively and cannot be used in automated scripts.
```

The tool is available through the `lxd recover` command (note the `lxd` command rather than the normal `lxc` command).

When you run the tool, it scans all storage pools that still exist in the database, looking for missing volumes that can be recovered.
Any unknown storage pools (those that exist on disk but do not exist in the database) which are discovered whilst scanning existing and unknown volumes
are printed so they can be created manually using the `lxc storage create ... source.recover=true` command.
Concrete examples for each storage driver can be found in {ref}`howto-storage-pools-recover`.

After mounting the specified storage pools (if not already mounted), the tool scans them for unknown volumes that look like they are associated with LXD.
LXD maintains a `backup.yaml` file in each instance's storage volume, which contains all necessary information to recover a given instance (including instance configuration, attached devices, storage volume, and pool configuration).
This data can be used to rebuild the instance, storage volume, attached custom volumes, and storage pool database records.
Before recovering an instance, the tool performs some consistency checks to compare what is in the `backup.yaml` file with what is actually on disk (such as matching snapshots).
If all checks out, the database records are re-created.

The tool asks you to re-create missing entities like networks.
However, the tool does not know how the instance was configured.
That means that if some configuration was specified through the `default` profile, you must also re-add the required configuration to the profile.
For example, if the `lxdbr0` bridge is used in an instance and you are prompted to re-create it, you must add it back to the `default` profile so that the recovered instance uses it.


## Related topics

How-to guides:

* {ref}`howto-replicators-setup`
* {ref}`howto-replicators-manage`
* {ref}`howto-replicators-dr`
* {ref}`disaster-recovery-replication`

Reference:

* {ref}`ref-replicator-config`
* {ref}`exp-cluster-links`
