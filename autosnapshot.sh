

#! /bin/bash
# Create the snapshots

gcloud compute disks list --format='value(name,zone)'| while read DISK_NAME ZONE; do
    gcloud compute disks snapshot $DISK_NAME --snapshot-names autosnapshot-${DISK_NAME:0:31}-$(date "+%Y-%m-%d-%s") --zone $ZONE
done

# The expiration date is one month. Snapshots on month old or more will be deleted.

EXPIRED=`date -d "-29 days"  +%Y-%m-%d `
echo "Expiration date is set to $EXPIRED"

#Beware! Without further filtering it's deleting ALL the snapshots present, not only the ones created by the script. In case
#you want to limit the snapshot cleanup to only the ones created by it swap the "--filter="creationTimesTamp>$EXPIRED" below 
#with this one:   --filter="creationTimesTamp>$EXPIRED AND name~"autosnapshot*"


gcloud compute snapshots list --filter="creationTimesTamp>$EXPIRED" --uri | while read SNAPSHOT_URI; do
    echo "Deleting snapshot: $SNAPSHOT_URI"
    gcloud compute snapshots delete $SNAPSHOT_URI --quiet

done
