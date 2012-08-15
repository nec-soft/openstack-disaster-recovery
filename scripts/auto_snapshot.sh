#!/bin/bash

# This script's aim is creating instance snapshot that is disaster recovery target.
# It's expected that this script works by CRON.
# ex)
# 00 01 * * 1 /var/lib/dr/script/auto_snapshot.sh > /dev/null

# Set shell variables.
HOSTNAME=`/bin/hostname`
BASEDIR=/var/lib/dr
SHAREDIR=/opt/share
OPENRC=$SHAREDIR/env/$HOSTNAME/openrc_admin
PREFIX="SNAP_"
TIMEOUT=1800

# Load the cloud administrator's openrc file.
. $OPENRC

# Get name of all tenants.
/usr/local/bin/keystone tenant-list | awk 'NR>=4{print $4}' | grep -v '^$' > $BASEDIR/tmp/tenant_list

# Instance snapshot is private image.
# So these snapshots is created every tenant.
while read TENANT; do

    if [ -f "$SHAREDIR/env/$HOSTNAME/openrc_$TENANT" ]; then

        # Load tenant administrator's openrc file.
        . $SHAREDIR/env/$HOSTNAME/openrc_$TENANT

        while read LINE; do
            TENANT_NAME=`echo $LINE | cut -d ":" -f 2`

            # Create instance snapshots for only own tenant.
            if [ "$TENANT" == "$TENANT_NAME" ]; then
                INST_NAME=`echo $LINE | cut -d ":" -f 1`
                INST_ID=`/usr/local/bin/nova list | awk '/'$INST_NAME'/{print $2}'`

                if [ "$INST_ID" != "" ]; then

                    # Check whether snapshot of same instance exists already.
                    # When that snapshot exists, delete it at first.
                    IMG_ID=`/usr/local/bin/nova image-list | awk '/'$INST_ID'/{print $2}'`
                    if [ "$IMG_ID" != "" ]; then
                        /usr/local/bin/nova image-delete $IMG_ID
                        sleep 30
                    fi

                    # Snapshot name format is 'SNAP_<instance_name>'.
                    IMG_NAME=$PREFIX$INST_NAME
                    /usr/local/bin/nova image-create $INST_ID $IMG_NAME

                    # Wait until a snapshot state becomes "ACTIVE".
                    COUNT=0
                    while :; do
                        if [ $COUNT -gt $TIMEOUT ]; then
                            echo "Expired. [$TIMEOUT]"
                            break
                        fi
                        STATUS=`/usr/local/bin/nova image-show $IMG_NAME | awk '/status/{print $4}'`
                        if [ "$STATUS" != "ACTIVE" ]; then
                            COUNT=`expr $COUNT + 10`
                        else
                            break
                        fi
                        sleep 10
                    done
                fi
            fi
        done < "$SHAREDIR/target/$HOSTNAME/dr_target_list"
    fi
done < "$BASEDIR/tmp/tenant_list"

rm $BASEDIR/tmp/tenant_list
