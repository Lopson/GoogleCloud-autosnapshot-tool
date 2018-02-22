#! /bin/bash
# Create the snapshots

gcloud compute disks list --format='value(name,zone)'| while read DISK_NAME ZONE; do
gcloud compute disks snapshot $DISK_NAME --snapshot-names autosnapshot-${DISK_NAME:0:15}-$(date "+%Y-%m-%d-%s") --zone $ZONE
done

# Set the expiration date so snapshots older than a week will be deleted

EXPIRED=$(date -d "-7 days" +%Y-%-m-%d)
echo "##################################"
echo " \n"
echo "Expiration date is set to $EXPIRED"
echo "##################################"
echo " \n"

#Beware! Without further filtering it's deleting ALL the snapshots present, not only the ones created by the script. In case
#you want to limit the snapshot cleanup to only the ones created by it swap the "--filter="creationTimesTamp<$EXPIRED" below
#with this one: --filter="creationTimestamp<$EXPIRED AND name~"autosnapshot*"

# Delete the snapshots

gcloud compute snapshots list --filter="creationTimestamp<$EXPIRED" --uri | while read SNAPSHOT_URI; do
        echo "Deleting snapshot: $SNAPSHOT_URI"
gcloud compute snapshots delete $SNAPSHOT_URI --quiet

done
