#!/bin/bash
#
# Create snapshots of all disks in a project or of all disks in a specific instance.

# Declare read-only global variables.
SNAPSHOT_EXPIRATION_DATE=$(date -d "-7 days" +%Y-%-m-%d); readonly SNAPSHOT_EXPIRATION_DATE;
SNAPSHOT_NAME_PREFIX="autosnapshot"; readonly SNAPSHOT_NAME_PREFIX;
GCLOUD_NO_SNAPSHOTS="Listed 0 items."; readonly GCLOUD_NO_SNAPSHOTS;
GCLOUD_TERMINATED_STRING="TERMINATED"; readonly GCLOUD_TERMINATED_STRING;
GCLOUD_READ_WRITE_STRING="READ_WRITE"; readonly GCLOUD_READ_WRITE_STRING;
GCLOUD_NOT_TERMINATED_STRING="NOT-TERMINATED"; readonly GCLOUD_NOT_TERMINATED_STRING;

# Declare error codes.
ERROR_INVALID_ARGS=65; readonly ERROR_INVALID_ARGS;
ERROR_INSTANCE_ONLINE_DISK_IN_RW=66; readonly ERROR_INSTANCE_ONLINE_DISK_IN_RW;
ERROR_SNAPSHOT_CREATION_FAIL=67; readonly ERROR_SNAPSHOT_CREATION_FAIL;
ERROR_GET_LIST_DISKS_FAIL=68; readonly ERROR_GET_LIST_DISKS_FAIL;
ERROR_GET_LIST_SNAPSHOTS_FAIL=69; readonly ERROR_GET_LIST_SNAPSHOTS_FAIL;
ERROR_DELETING_SNAPSHOT=70; readonly ERROR_DELETING_SNAPSHOT;
ERROR_ZONE_INVALID=71; readonly ERROR_ZONE_INVALID;
ERROR_INSTANCE_INVALID=72; readonly ERROR_INSTANCE_INVALID;

# Declare warning codes.
WARNING_UNSOLICITED_ARGUMENT=100; readonly WARNING_UNSOLICITED_ARGUMENT;

#######################################
# Validate that we won't snapshot a disk of an instance while it's not terminated.
#
# Globals:
#   $GCLOUD_READ_WRITE_STRING String used by gcloud to denote that a disk is in RW mode;
#   $GCLOUD_TERMINATED_STRING String used by gcloud to denote that an instance is terminated.
# Arguments:
#   $1 CSV string containing disks of instance and their mode of operation (RO/RW);
#   $2 Name of the instance;
#   $3 Status of the instance;
# Returns:
#   0 if successful;
#   $ERROR_INSTANCE_ONLINE_DISK_IN_RW if one of the disks is in RW and instance is not terminated.
#######################################
function validate_disk_rw {
    local instance_disks_opmode; local instance_name; local i;
    local list_instance_disks; local list_instance_opmode;
    local total_disks; local disk_name; local disk_opmode;
    local instance_status;

    # Initialize variables.
    instance_disks_opmode=$1;
    instance_name=$2;
    instance_status=$3;

    # Get list of disks and disk operation mode from argument.
    # Expected format: disk1;disk2,disk1_opmode;disk2_opmode
    list_instance_disks=($(echo "$instance_disks_opmode" | cut -d ',' -f 1 | tr ';' ' '));
    list_instance_opmode=($(echo "$instance_disks_opmode" | cut -d ',' -f 2 | tr ';' ' '));
    total_disks=${#list_instance_disks[*]};

    # Making sure no disk is in read/write mode. If it is, bail out.
    # If an instance has a disk in read/write mode, then only that instance will have access to the disk at the same time.
    # If an instance has a disk in read-only mode, then multiples instances can access the disk at the same time.
    for (( i=0 ; i < total_disks; i++ )); do
        disk_name=${list_instance_disks[i]};
        disk_opmode=${list_instance_opmode[i]};

        if [[ "$disk_opmode" == "$GCLOUD_READ_WRITE_STRING" ]] && [[ "$instance_status" != "$GCLOUD_TERMINATED_STRING" ]]; then
            echo "ERROR: Disk $disk_name is set to read/write, can't snapshot disk while machine $instance_name is not powered off.";
            echo "Please power off the machine before snapshotting this disk.";
            return $ERROR_INSTANCE_ONLINE_DISK_IN_RW;
        fi;
    done;

    return 0;
}

#######################################
# Snapshot a disk.
#
# Globals:
#   $SNAPSHOT_NAME_PREFIX Defines the prefix of snapshots to create.
# Arguments:
#   $1 Name of the disk to snapshot;
#   $2 Zone of the disk to snapshot;
# Returns:
#   0 if successful;
#   $ERROR_SNAPSHOT_CREATION_FAIL if the gcloud command to create a snapshot has failed.
#######################################
function snapshot_disk {
    local disk_name; local disk_zone;
    local snapshot_name;

    # Initialize variables.
    disk_name=$1;
    disk_zone=$2;
    snapshot_name="$SNAPSHOT_NAME_PREFIX-${disk_name:0:15}-$(date +%Y-%m-%d-%s)";

    # Create a snapshot for a given disk.
    if ! gcloud compute disks snapshot "$disk_name" --zone "$disk_zone" --snapshot-names "$snapshot_name"; then
        echo "ERROR: Failed to create a snapshot for the disk $disk_name";
        return $ERROR_SNAPSHOT_CREATION_FAIL;
    fi;

    echo "Snapshot $snapshot_name created for disk $disk_name";
    return 0;
}

#######################################
# Delete the expired snapshots of a disk.
#
# Globals:
#   $SNAPSHOT_EXPIRATION_DATE Defines the expiration date for the snapshots.
#   $GCLOUD_NO_SNAPSHOTS String used by gcloud to indicate that no snapshots exist.
# Arguments:
#   $1 Name of the disk to have expired snapshots deleted;
#   $2 Zone of the disk to have expired snapshots deleted;
# Returns:
#   0 if successful;
#   $ERROR_GET_LIST_SNAPSHOTS_FAIL if the gcloud command to get a list of snapshots of a disk failed;
#   $ERROR_DELETING_SNAPSHOT if the gcloud command to delete an expired snapshot failed.
#######################################
function delete_disk_expired_snapshots {
    local disk_name; local disk_zone;
    local output_cmd; local snapshots_list;
    local current_snapshot;
    
    # Initialize variables.
    disk_name=$1;
    disk_zone=$2;

    echo "Checking if there are expired snapshots for disk $disk_name.";

    # Get list of snapshots to delete.
    if ! output_cmd=$(gcloud compute snapshots list --format "csv(selfLink)[no-heading]" \
    --filter "sourceDisk:$disk_zone/disks/$disk_name AND creationTimestamp<$SNAPSHOT_EXPIRATION_DATE AND name~^$SNAPSHOT_NAME_PREFIX.*"); then
        echo "ERROR: Couldn't get list of snapshots of disk $disk_name, aborting.";
        return $ERROR_GET_LIST_SNAPSHOTS_FAIL;
    fi

    # If there aren't any snapshots to delete, exit.
    if [[ -z "$output_cmd" ]]; then
        echo "There are no snapshots of disk $disk_name to delete.";
        return 0;
    fi;

    snapshots_list=($output_cmd);

    # Cycle through all snapshots to delete and delete them.
    echo "Deleting old snapshots of disk $disk_name.";
    for current_snapshot in "${snapshots_list[@]}"; do
        if ! gcloud compute snapshots delete "$current_snapshot" --quiet; then
            echo "ERROR: Couldn't delete snapshot $current_snapshot belonging to disk $disk_name.";
            return $ERROR_DELETING_SNAPSHOT;
        fi;

        echo "Snapshot $current_snapshot belonging to disk $disk_name deleted.";
    done;

    return 0;
}

#######################################
# Creates snapshots of all disks of a machine.
# Refuses to snapshot disk if it's disk in in read/write and instance using it is not terminated.
# Can also delete old snapshots.
#
# Globals:
#   None
# Arguments:
#   $1 Name of machine with disks to snapshot;
#   $2 Zone of the machine;
#   $3 Old snapshot deletion flag. If non-empty, they're deleted.
# Returns:
#   0 if successful;
#   $ERROR_INVALID_ARGS if the gcloud command to get the details of the instance fails;
#   Return values of validate_disk_rw if function fails;
#   Return values of snapshot_disk if function fails;
#   Return values of delete_disk_expired_snapshots if function fails.
#######################################
function snapshot_disks_machine {
    # Declare variables local to function.
    local instance_name; local machine_zone; local retval;
    local list_instance_disks; local current_instance_disks_opmode;
    local current_machine_status; local output_cmd; local i;
    local total_disks; local disk_name; local disk_opmode;
    local delete_old_snapshots_flag;
    
    # Initialize variables.
    instance_name=$1;
    machine_zone=$2;
    delete_old_snapshots_flag=$3;

    # Try to get list of disks of given instance.
    if ! output_cmd=$(gcloud compute instances list --format "csv(status, disks.deviceName, disks.mode)[no-heading]" \
    --filter "name=$instance_name"); then
        echo "ERROR: Machine $instance_name not found or zone $machine_zone doesn't exist.";
        return $ERROR_INVALID_ARGS;
    fi;

    # Parse list of disks of given instance.
    current_machine_status=$(echo "$output_cmd" | cut -d ',' -f 1);
    current_instance_disks_opmode=$(echo "$output_cmd" | cut -d ',' -f 2,3);
    list_instance_disks=($(echo "$output_cmd" | cut -d ',' -f 2 | tr ';' ' '));

    # Make sure no disks are in read/write mode while the machine is online.
    validate_disk_rw "$current_instance_disks_opmode" "$instance_name" "$current_machine_status";
    retval=$?;
    if (( retval != 0 )); then
        return $retval;
    fi;
    
    # Snapshot the disks; delete old snapshots if asked to.
    for disk_name in "${list_instance_disks[@]}"; do
        snapshot_disk "$disk_name" "$machine_zone";
        retval=$?;
        if (( retval != 0 )); then
            return $retval;
        fi;

        if [[ -z "$delete_old_snapshots_flag" ]]; then
            continue;
        fi;
            
        delete_disk_expired_snapshots "$disk_name" "$machine_zone";
        retval=$?;
        if (( retval != 0 )); then
            return $retval;
        fi;
    done;

    return 0;
}

#######################################
# Creates snapshots of all disks in the project.
# Refuses to snapshot disk if it's disk in in read/write and instance using it is not terminated.
# Can also delete old snapshots.
#
# Globals:
#   None
# Arguments:
#   $1 Old snapshot deletion flag. If non-empty, they're deleted.
# Returns:
#   0 if successful;
#   $ERROR_GET_LIST_DISKS_FAIL if the gcloud command to get all disks in a project has failed;
#   $ERROR_INVALID_ARGS if the gcloud command to get a list of non-terminated instances failed;
#   Return values of validate_disk_rw if function fails;
#   Return values of snapshot_disk if function fails;
#   Return values of delete_disk_expired_snapshots if function fails.
#######################################
function snapshot_all_disks {
    # Declare variables local to function.
    local list_disks; local list_disks_entry;
    local output_cmd; local delete_old_snapshots_flag;
    local list_machine_name; local list_machine_disks_opmode;
    local total_disks; local i; local retval;

    # Initialize variables.
    delete_old_snapshots_flag=$1;

    # Try to get list of disks in the project.
    if ! output_cmd=$(gcloud compute disks list --format="csv(name, zone)[no-heading]"); then
        echo "Couldn't retrieve list of snapshots in project, aborting.";
        return $ERROR_GET_LIST_DISKS_FAIL;
    fi;

    list_disks=($output_cmd);

    # Try to get a list of non-terminated instances.
    if ! output_cmd=$(gcloud compute instances list --format "csv(name, disks.deviceName, disks.mode)[no-heading]" \
    --filter "status!=$GCLOUD_TERMINATED_STRING"); then
        echo "ERROR: Couldn't get a list of non-terminated instances for the project, aborting.";
        return $ERROR_INVALID_ARGS;
    fi;

    # If there are running instances, make sure that their disks are in read-only mode.
    if ! [[ -z "$output_cmd" ]]; then
        output_cmd=($output_cmd);

        for output_entry in "${output_cmd[@]}"; do
            list_machine_name=$(echo "$output_entry" | cut -d ',' -f 1);
            list_machine_disks_opmode=$(echo "$output_entry" | cut -d ',' -f 2,3);

            # Make sure no disks are in read/write mode while the machine is online.
            # The machines we're iterating over are not terminated, so just pass a constant to function.
            validate_disk_rw "$list_machine_disks_opmode" "$list_machine_name" "$GCLOUD_NOT_TERMINATED_STRING";
            retval=$?;
            if (( retval != 0 )); then
                return $retval;
            fi;
        done;
    fi;
    
    # Snapshot the disks; delete old snapshots if asked to.
    for list_disks_entry in "${list_disks[@]}"; do
        disk_name=${list_disks_entry[i]%,*};
        disk_zone=${list_disks_entry[i]#*,};

        snapshot_disk "$disk_name" "$disk_zone";
        retval=$?;
        if (( retval != 0 )); then
            return $retval;
        fi;

        if [[ -z "$delete_old_snapshots_flag" ]]; then
            continue;
        fi;
        
        delete_disk_expired_snapshots "$disk_name" "$machine_zone";
        retval=$?;
        if (( retval != 0 )); then
            return $retval;
        fi;
    done;
}

#######################################
# Checks if zone given as argument exists.
#
# Globals:
#   None
# Arguments:
#   $1 Zone to check for existance.
# Returns:
#   0 if successful;
#   $ERROR_ZONE_INVALID if zone isn't valid.
#######################################
function check_zone {
    local zone_to_check; local zone_list; local zone_name;

    zone_to_check=$1;
    zone_list=($(gcloud compute zones list --format "value(name)"));

    for zone_name in "${zone_list[@]}"; do
        if [[ "$zone_to_check" == "$zone_name" ]]; then
            return 0;
        fi;
    done;

    echo "ERROR: Given zone doesn't exist, aborting.";
    return $ERROR_ZONE_INVALID;
}

#######################################
# Checks if instance given as argument exists.
#
# Globals:
#   None
# Arguments:
#   $1 Instance to check for existance.
# Returns:
#   0 if successful;
#   $ERROR_INSTANCE_INVALID if instance isn't valid.
#######################################
function check_instance {
    local instance_to_check; local instance_zone;
    
    instance_to_check=$1;
    instance_zone=$2;

    if ! gcloud compute instances describe "$instance_to_check" --zone "$instance_zone" --no-user-output-enabled; then
        echo "ERROR: Given machine doesn't exist, aborting.";
        return $ERROR_INSTANCE_INVALID;
    fi;

    return 0;
}

all_disks_flag="";
delete_old_snapshots_flag="";
machine_name_arg="";
zone_arg="";

# Parse arguments given.
while getopts 'adm:z:' flag; do
    case "${flag}" in
        a)
            all_disks_flag="true";
            ;;
        d)
            delete_old_snapshots_flag="true";
            echo "Expiration date of autosnapshots is currently set to $SNAPSHOT_EXPIRATION_DATE.";
            ;;
        m)
            machine_name_arg="${OPTARG}";
            ;;
        z)
            zone_arg="${OPTARG}";
            ;;
        *)
            echo "ERROR: Invalid argument supplied.";
            exit $ERROR_INVALID_ARGS;
            ;;
    esac;
done;

# Basic error checking in arguments given.
if ! [[ -z "$all_disks_flag" ]] && ! [[ -z "$machine_name_arg" ]]; then
    echo "ERROR: You can't use the -a and the -m flags at the same time.";
    exit $ERROR_INVALID_ARGS;
fi;

if [[ -z "$all_disks_flag" ]] && [[ -z "$machine_name_arg" ]]; then
    echo "ERROR: Neither -a nor -m flag given, aborting.";
    exit $ERROR_INVALID_ARGS;
fi;

if ! [[ -z "$machine_name_arg" ]] && [[ -z "$zone_arg" ]]; then
    echo "ERROR: Instance given without its zone. Please supply the zone with -z.";
    exit $ERROR_INVALID_ARGS;
fi;

if ! [[ -z "$all_disks_flag" ]] && ! [[ -z "$zone_arg" ]]; then
    echo "WARNING: Snapshotting all disks; ignoring zone argument given via -z.";
    exit $WARNING_UNSOLICITED_ARGUMENT;
fi;

# Perform the snapshotting asked from us via the arguments.
if ! [[ -z "$all_disks_flag" ]]; then
    snapshot_all_disks "$delete_old_snapshots_flag";
    retval_global=$?;
    if (( retval_global != 0 )); then
        exit $retval_global;
    fi;
elif ! [[ -z "$machine_name_arg" ]]; then
    # Check if given zone is valid.
    check_zone "$zone_arg";
    retval_global=$?;
    if (( retval_global != 0 )); then
        exit $retval_global;
    fi;

    # Check if given instance is valid.
    check_instance "$machine_name_arg" "$zone_arg";
    retval_global=$?;
    if (( retval_global != 0 )); then
        exit $retval_global;
    fi;

    snapshot_disks_machine "$machine_name_arg" "$zone_arg" "$delete_old_snapshots_flag";
    retval_global=$?;
    if (( retval_global != 0 )); then
        exit $retval_global;
    fi;
fi;

echo "Script ran successfully; exiting script.";