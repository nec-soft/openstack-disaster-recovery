#!/bin/bash

# This script's aim is deleting information that hadn't been disaster recovery target.
# These information is deleted from shared directory.
# It's expected that this script works by CRON.
# ex)
# 05 */3 * * * /var/lib/dr/script/obsolete.sh > /dev/null

# Set shell variables.
HOSTNAME=`/bin/hostname`
BASEDIR=/var/lib/dr
SHAREDIR=/opt/share
OPENRC=$SHAREDIR/env/$HOSTNAME/openrc_admin

# Load the cloud administrator's openrc file.
. $OPENRC

# Get IDs of launched instances in all tenants.
# And these are written down a temporary file.
/usr/local/bin/nova list --all_tenants | awk 'NR>=4{print $2}' | grep -v '^$' > $BASEDIR/tmp/new_inst_list

# Create a base file to exclude it from disaster recovery target.
cp $SHAREDIR/target/$HOSTNAME/dr_target_list $BASEDIR/tmp/ob_list

while read LINE1; do
    INST_NAME=`/usr/local/bin/nova list --all_tenants | awk '/'$LINE1'/{print $4}'`
    TENANT_ID=`/usr/local/bin/nova show $LINE1 | awk '/tenant_id/{print $4}'`
    TENANT_NAME=`/usr/local/bin/keystone tenant-list | awk '/'$TENANT_ID'/{print $4}'`
    sed -i '/'$INST_NAME:$TENANT_NAME'/d' $BASEDIR/tmp/ob_list

    # Get metadata of an instance.
    KEY=`/usr/local/bin/nova show $LINE1 | awk '/metadata/{print $4$5}'`

    # Isn't this metadata equal to "{u'dr':u'yes'}"?
    # Yes ==> It's not target of disaster recovery.
    #         Delete this instance's information from shared directory.
    # No  ==> It's target.
    if [ "$KEY" != "{u'dr':u'yes'}" ]; then
        sed -i '/'$INST_NAME:$TENANT_NAME'/d' $SHAREDIR/target/$HOSTNAME/dr_target_list
        rm -r $SHAREDIR/target/$HOSTNAME/$INST_NAME:$TENANT_NAME
    fi
done < "$BASEDIR/tmp/new_inst_list"

# Tarminated instances are not target of disaster recovery naturally.
# So, delete these instance's information from shared directory.
while read LINE2; do
    sed -i '/'$LINE2'/d' $SHAREDIR/target/$HOSTNAME/dr_target_list
    rm -r $SHAREDIR/target/$HOSTNAME/$LINE2
done < "$BASEDIR/tmp/ob_list"

rm $BASEDIR/tmp/*
