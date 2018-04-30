# GoogleCloud-autosnapshot-tool

This bash script manages disk snapshots for an instance's disks running in Google Cloud or for all of a Google Cloud project's disks. You should run this in a cron job to partially automate snapshot management.

## Usage

You can pass a few arguments to this script to set its behaviour. They are:

    -a Snapshot all disks in a project.
    -d Delete snapshots older than $SNAPSHOT_EXPIRATION_DATE.
    -m INSTANCE_NAME Snapshot a given instance.
    -z ZONE_INSTANCE The zone of the instance to snapshot.

You can't use `-a` and `-m -z` at the same time. Also, you have to specify `-z` whenever you want to use `-m`. In order to change the validity period of a snapshot, you'll have to change the value of the variable `$SNAPSHOT_EXPIRATION_DATE`. Finally, using `-d` is not mandatory.

### Snapshot all disks in a project

    ./autosnapshot.sh -a [-d]

### Snapshot an instance's disks

    ./autosnapshot.sh -m INSTANCE_NAME -z ZONE_NAME

## TODO

One big thing that this script is currently missing is the ability to terminate instances before snapshotting them. It should be easy to implement that.

Another thing that's missing is VSS snapshots on running Windows instances. This would avoid having to power them off.