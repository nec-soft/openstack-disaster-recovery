#!/bin/bash

# This script's aim is gathering information for disaster recovery targets.
# Gathered information is recorded in shared file.
# It's expected that this script works by CRON.
# ex)
# 00 */3 * * * /var/lib/dr/script/get_dr_target.sh > /dev/null

# Set shell variables.
HOSTNAME=`/bin/hostname`
BASEDIR=/var/lib/dr
SHAREDIR=/opt/share
OPENRC=$SHAREDIR/env/$HOSTNAME/openrc_admin
SUFFIX="_INFO"
ACCOUNT=`cat $SHAREDIR/env/$HOSTNAME/db_info | awk '/DB_ACCOUNT/{print $2}'`
PASSWD=`cat $SHAREDIR/env/$HOSTNAME/db_info | awk '/DB_PASSWORD/{print $2}'`

# Load the cloud administrator's openrc file.
. $OPENRC

# Get IDs of launched instances in all tenants.
# And these are written down a temporary file.
/usr/local/bin/nova list --all_tenants | awk 'NR>=4{print $2}' | grep -v '^$' > $BASEDIR/tmp/inst_list

# Search for the disaster recovery targets.
while read LINE1; do

    # Get metadata of an instance.
    KEY=`/usr/local/bin/nova show $LINE1 | awk '/metadata/{print $4$5}'`

    # Is this metadata equal to "{u'dr':u'yes'}"?
    # Yes ==> It's target of disaster recovery.
    #         This instance name is written shared file 'dr_target_list'.
    # No  ==> Not target.
    if [ "$KEY" == "{u'dr':u'yes'}" ]; then
        INST_NAME=`/usr/local/bin/nova list --all_tenants | awk '/'$LINE1'/{print $4}'`
        TENANT_ID=`/usr/local/bin/nova show $LINE1 | awk '/tenant_id/{print $4}'`
        TENANT_NAME=`/usr/local/bin/keystone tenant-list | awk '/'$TENANT_ID'/{print $4}'`

        # Check whether written already.
        CHECK=`cat $SHAREDIR/target/$HOSTNAME/dr_target_list | grep -w $INST_NAME:$TENANT_NAME`
        if [ "$CHECK" == "" ]; then

            # Format is "<instance_name>:<tenant_name>".
            echo $INST_NAME:$TENANT_NAME >> $SHAREDIR/target/$HOSTNAME/dr_target_list
        fi
    fi
done < "$BASEDIR/tmp/inst_list"

# Gather details for the disaster recovery targets.
while read LINE2; do

    # Check whether directory exists already.
    CHECK=`ls $SHAREDIR/target/$HOSTNAME | grep -w $LINE2`
    if [ "$CHECK" == "" ]; then
        mkdir -p $SHAREDIR/target/$HOSTNAME/$LINE2
    fi

    INST_NAME=`echo $LINE2 | cut -d ":" -f 1`
    TENANT_NAME=`echo $LINE2 | cut -d ":" -f 2`

    # Get ID of relevant instance in all tenants.
    /usr/local/bin/nova list --all_tenants | awk '/'$INST_NAME'/{print $2}' > $BASEDIR/tmp/inst_list
    CNT=`wc $BASEDIR/tmp/inst_list | awk '{print $1}'`

    # When result count is larger than 1, narrow it down a thing in consistent with tenant name.
    if [ $CNT > 1 ]; then
        while read INST; do
            TENANT_ID=`/usr/local/bin/nova show $INST | awk '/tenant_id/{print $4}'`
            TENANT=`/usr/local/bin/keystone tenant-list | awk '/'$TENANT_ID'/{print $4}'`
            if [ "$TENANT" == "$TENANT_NAME" ]; then
                INST_ID=$INST
                break
            fi
        done < "$BASEDIR/tmp/inst_list"
    else
        INST_ID=`cat $BASEDIR/tmp/inst_list`
    fi

    # Get ID of relevant snapshot image.
    IMG_ID=`/usr/local/bin/nova image-list | awk '/'$INST_ID'/{print $2}'`
    # Get image's location.
    LOCATION_TMP=`/usr/bin/mysql -N -r -B -u$ACCOUNT -p$PASSWD -e "select location from glance.images where id = '$IMG_ID';"`
    # Detail informations are written shared file.
    /usr/local/bin/nova show $INST_ID > $SHAREDIR/target/$HOSTNAME/$LINE2/$INST_NAME$SUFFIX
    /usr/local/bin/glance show $IMG_ID >> $SHAREDIR/target/$HOSTNAME/$LINE2/$INST_NAME$SUFFIX
    echo "LOCATION_TMP ${LOCATION_TMP%/*}" >> $SHAREDIR/target/$HOSTNAME/$LINE2/$INST_NAME$SUFFIX
    echo "TENANT_NAME $TENANT_NAME" >> $SHAREDIR/target/$HOSTNAME/$LINE2/$INST_NAME$SUFFIX
done < "$SHAREDIR/target/$HOSTNAME/dr_target_list"

rm $BASEDIR/tmp/inst_list
