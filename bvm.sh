#!/usr/bin/env bash

# Make copy to Borg repository
# VM must have only one disk!!!

echo "Make archive vm : $1"
BORGROOT=/mnt/ks1_backup
export BORG_PASSPHRASE="*****"
#echo "Init borg repo"
borg init --encryption=repokey-blake2 $BORGROOT/$1
export BORG_REPO=$BORGROOT/$1
DISKPATH=$(virsh domblklist $1 | grep vda | awk '{print $2}')
#echo "Create snapshot vm : $1"
virsh snapshot-create-as --domain $1 --name snapshot --no-metadata --disk-only --atomic --quiesce
SNAPSHOTPATH=$(virsh domblklist $1 | grep vda | awk '{print $2}')
#echo "Create archive vm $1 in borg repo $BORG_REPO"
borg create -v --stats $BORG_REPO::$1-{now:%Y-%m-%d_%H:%M:%S} $DISKPATH
#echo "create blockcommit vm : $1"
virsh blockcommit $1 vda --active --verbose --pivot
echo "Remove snapshot $SNAPSHOTPATH"
rm -rf $SNAPSHOTPATH


