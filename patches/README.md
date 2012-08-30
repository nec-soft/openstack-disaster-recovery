Patches for OpenStack Disaster Recovery
===========================

It is necessary to apply these patches to use function of OpenStack Disaster Recovery.
The behavior of the system is changed as follows by these patches.

## nova.patch

- Forbid launching the instance of the same name in own tenant.

## glance.patch

- Forbid creating the machine image of the same name in a tenant. The check range is all image in own tenant and public image in other tenants.

## horizon.patch

- Forbid launching the instance of the name to start with specific character string('MIG_') on Dashboard.

- Forbid creating the instance-snapshot of the name to start with specific character string('SNAP_' and 'COPY_') on Dashboard.

- Forbid creating the instance-snapshot of the name to end with specific character string('_KERNEL' and '_RAMDISK') on Dashboard.

- When Dashboard users launch the instance, it allows them to set metadata infomation.

- It allows Dashboard users to set auto-API execution.
