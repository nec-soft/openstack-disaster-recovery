#!/bin/bash

# This script's aim is copying instance snapshot that is disaster recovery target
# from DR destination cloud.
# It's expected that this script works by CRON.
# ex)
# 00 01 * * 4 /var/lib/dr/script/auto_copy.sh > /dev/null

# Set shell variables.
HOSTNAME=`/bin/hostname`
BASEDIR=/var/lib/dr
SHAREDIR=/opt/share
PREFIX="COPY_"
SUFFIX="_INFO"
K_SUF="_KERNEL"
R_SUF="_RAMDISK"
TIMEOUT=1800

# Copy instance snapshot every DR source cloud.
while read SOURCE_HOST; do

    while read LINE; do
        KERNEL_ID=""
        RAMDISK_ID=""

        # Pick up the information from shared files.
        INST_NAME=`echo $LINE | cut -d ":" -f 1`
        TENANT=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME$SUFFIX | grep -w TENANT_NAME | awk '{print $2}'`
        SOURCE_AMI=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME$SUFFIX | grep -w Id: | awk '{print $2}'`
        SOURCE_AKI=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME$SUFFIX | grep -w kernel_id | awk '{print $3}'`
        SOURCE_ARI=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME$SUFFIX | grep -w ramdisk_id | awk '{print $3}'`
        LOCATION_TMP=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME$SUFFIX | grep -w LOCATION_TMP | awk '{print $2}'`

        # It's case that same name tenant exists on DR destination cloud.
        if [ -f "$SHAREDIR/env/$HOSTNAME/openrc_$TENANT" ]; then

            # Load tenant administrator's openrc file.
            . $SHAREDIR/env/$HOSTNAME/openrc_$TENANT

            # Check whether image of same name exists already.
            # When that image exists, delete it at first.
            AKI_ID=`/usr/local/bin/nova image-list | awk '/'$INST_NAME$K_SUF'/{print $2}'`
            ARI_ID=`/usr/local/bin/nova image-list | awk '/'$INST_NAME$R_SUF'/{print $2}'`
            AMI_ID=`/usr/local/bin/nova image-list | awk '/'$PREFIX$INST_NAME'/{print $2}'`
            if [ "$AKI_ID" != "" ]; then
                /usr/local/bin/nova image-delete $AKI_ID
                sleep 5
            fi
            if [ "$ARI_ID" != "" ]; then
                /usr/local/bin/nova image-delete $ARI_ID
                sleep 5
            fi
            if [ "$AMI_ID" != "" ]; then
                /usr/local/bin/nova image-delete $AMI_ID
                sleep 30
            fi

            # Copy kernel from DR source cloud. Name format is '<instance_name>_KERNEL'.
            if [ "$SOURCE_AKI" != "" ]; then
                RVAL=`/usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AKI" is_public=false container_format=aki disk_format=aki name="$INST_NAME$K_SUF"`
                KERNEL_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
            fi

            # Copy ramdisk from DR source cloud. Name format is '<instance_name>_RAMDISK'.
            if [ "$SOURCE_ARI" != "" ]; then
                RVAL=`/usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_ARI" is_public=false container_format=ari disk_format=ari name="$INST_NAME$R_SUF"`
                RAMDISK_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
            fi

            # Copy image from DR source cloud. Name format is 'COPY_<instance_name>'.
            if [ "$KERNEL_ID" != "" -a "$RAMDISK_ID" != "" ]; then
                /usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AMI" is_public=false container_format=ami disk_format=ami kernel_id=$KERNEL_ID ramdisk_id=$RAMDISK_ID name="$PREFIX$INST_NAME"
            elif [ "$KERNEL_ID" != "" -a "$RAMDISK_ID" == "" ]; then
                /usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AMI" is_public=false container_format=ami disk_format=ami kernel_id=$KERNEL_ID name="$PREFIX$INST_NAME"
            elif [ "$KERNEL_ID" == "" -a "$RAMDISK_ID" == "" ]; then
                /usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AMI" is_public=false container_format=ami disk_format=ami name="$PREFIX$INST_NAME"
            fi

        # It's case that same name tenant does not exist on DR destination cloud.
        # In this case, copy image as that of 'anonymous' tenant.
        else

            # Load 'anonymous' tenant administrator's openrc file.
            . $SHAREDIR/env/$HOSTNAME/openrc_anonymous

            # Check whether image of same name exists already.
            # When that image exists, delete it at first.
            AKI_ID=`/usr/local/bin/nova image-list | awk '/'$INST_NAME$K_SUF'/{print $2}'`
            ARI_ID=`/usr/local/bin/nova image-list | awk '/'$INST_NAME$R_SUF'/{print $2}'`
            AMI_ID=`/usr/local/bin/nova image-list | awk '/'$PREFIX$INST_NAME'/{print $2}'`
            if [ "$AKI_ID" != "" ]; then
                /usr/local/bin/nova image-delete $AKI_ID
                sleep 5
            fi
            if [ "$ARI_ID" != "" ]; then
                /usr/local/bin/nova image-delete $ARI_ID
                sleep 5
            fi
            if [ "$AMI_ID" != "" ]; then
                /usr/local/bin/nova image-delete $AMI_ID
                sleep 30
            fi

            # Copy kernel from DR source cloud. Name format is '<instance_name>_KERNEL'.
            if [ "$SOURCE_AKI" != "" ]; then
                RVAL=`/usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AKI" is_public=false container_format=aki disk_format=aki name="$INST_NAME$K_SUF"`
                KERNEL_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
            fi

            # Copy ramdisk from DR source cloud. Name format is '<instance_name>_RAMDISK'.
            if [ "$SOURCE_ARI" != "" ]; then
                RVAL=`/usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_ARI" is_public=false container_format=ari disk_format=ari name="$INST_NAME$R_SUF"`
                RAMDISK_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
            fi

            # Copy image from DR source cloud. Name format is 'COPY_<instance_name>'.
            if [ "$KERNEL_ID" != "" -a "$RAMDISK_ID" != "" ]; then
                /usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AMI" is_public=false container_format=ami disk_format=ami kernel_id=$KERNEL_ID ramdisk_id=$RAMDISK_ID name="$PREFIX$INST_NAME"
            elif [ "$KERNEL_ID" != "" -a "$RAMDISK_ID" == "" ]; then
                /usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AMI" is_public=false container_format=ami disk_format=ami kernel_id=$KERNEL_ID name="$PREFIX$INST_NAME"
            elif [ "$KERNEL_ID" == "" -a "$RAMDISK_ID" == "" ]; then
                /usr/local/bin/glance add copy_from="$LOCATION_TMP/$SOURCE_AMI" is_public=false container_format=ami disk_format=ami name="$PREFIX$INST_NAME"
            fi
        fi
    done < "$SHAREDIR/target/$SOURCE_HOST/dr_target_list"
done < "$SHAREDIR/env/$HOSTNAME/source_host_list"
