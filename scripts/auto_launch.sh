#!/bin/bash

# This script's aim is copying instance snapshot that is disaster recovery target
# from DR destination cloud.
# It's expected that this script works by monitoring tool(Zabbix).

# Set shell variables.
HOSTNAME=`/bin/hostname`
BASEDIR=/var/run/zabbix
SHAREDIR=/opt/share
OPENRC=$SHAREDIR/env/$HOSTNAME/openrc_admin
PREFIX1="COPY_"
PREFIX2="MIG_"
SUFFIX="_INFO"
TIMEOUT=1800
ACCOUNT=`cat $SHAREDIR/env/$HOSTNAME/db_info | awk '/DB_ACCOUNT/{print $2}'`
PASSWD=`cat $SHAREDIR/env/$HOSTNAME/db_info | awk '/DB_PASSWORD/{print $2}'`

# Load the cloud administrator's openrc file.
. $OPENRC

# Get all tenants list.
/usr/local/bin/keystone tenant-list > $BASEDIR/tmp/tenant_list

# Launch DR target instance every DR source cloud.
while read SOURCE_HOST; do

    while read LINE; do
        INST_NAME1=`echo $LINE | cut -d ":" -f 1`
        TENANT=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | grep -w TENANT_NAME | awk '{print $2}'`

        # It's case that same name tenant exists on DR destination cloud.
        if [ -f "$SHAREDIR/env/$HOSTNAME/openrc_$TENANT" ]; then

            # Load tenant administrator's openrc file.
            . $SHAREDIR/env/$HOSTNAME/openrc_$TENANT

            # Check whether copy image's ID exists.
            IMG_ID=`/usr/local/bin/glance -f index | awk '/'$PREFIX1$INST_NAME1'/{print $1}'`
            if [ "$IMG_ID" != "" ]; then

                # Check whether same name instance exists. Name format is 'MIG_<instance_name>'.
                INST_NAME2=$PREFIX2$INST_NAME1
                CHECK=`/usr/local/bin/nova list | grep -w $INST_NAME2`

                # When that instance does not exist, launch instance.
                if [ "$CHECK" == "" ]; then

                    # Pick up the information from shared files.
                    TENANT_ID=`cat $BASEDIR/tmp/tenant_list | awk '/'$TENANT'/{print $2}'`
                    FIXED=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/network/{print $5}'`
                    NET_ID=`/usr/bin/mysql -N -r -B -u$ACCOUNT -p$PASSWD -e "select uuid from nova.networks where dhcp_start like '${FIXED%.*}%' and project_id = '$TENANT_ID';"`
                    F_NAME=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/flavor/{print $4}'`
                    FLAVOR=`/usr/local/bin/nova flavor-list | grep -w $F_NAME | awk '{print $2}'`

                    # When that flavor does not exist on DR destination cloud,
                    # select flavor 'm1.small'.
                    if [ "$FLAVOR" == "" ]; then
                        FLAVOR=`/usr/local/bin/nova flavor-list | grep -w m1.small | awk '{print $2}'`
                    fi

                    # Check whether same name keypair exists.
                    K_NAME=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/key_name/{print $4}'`
                    CHECK=`/usr/local/bin/nova keypair-list | grep -w $K_NAME`
                    if [ "$CHECK" == "" ]; then

                        # When that keypair does not exist on DR destination cloud,
                        # create new keypair 'default'.
                        K_NAME="default"
                        CHECK=`/usr/local/bin/nova keypair-list | grep -w $K_NAME`
                        if [ "$CHECK" == "" ]; then
                            /usr/local/bin/nova keypair-add default > $SHAREDIR/keypair/$HOSTNAME/$TENANT/$K_NAME.pem
                        fi
                    fi

                    # Recovered instance information is written shared file.
                    echo LAUNCH_USER $OS_USERNAME > $SHAREDIR/recovered/$INST_NAME2
                    echo HOST_NAME $HOSTNAME >> $SHAREDIR/recovered/$INST_NAME2
                    echo TENANT_NAME $TENANT >> $SHAREDIR/recovered/$INST_NAME2
                    echo KEY_NAME $K_NAME >> $SHAREDIR/recovered/$INST_NAME2

                    # Launch instance.
                    # Keep as possible an original local IP.
                    if [ "$NET_ID" != "" ]; then
                        RES=`/usr/local/bin/nova list | grep -w $FIXED`
                        if [ "$RES" != "" ]; then
                            /usr/local/bin/nova boot --flavor $FLAVOR --image $IMG_ID --key_name $K_NAME --nic net-id=$NET_ID $INST_NAME2
                        else
                            /usr/local/bin/nova boot --flavor $FLAVOR --image $IMG_ID --key_name $K_NAME --nic net-id=$NET_ID,v4-fixed-ip=$FIXED $INST_NAME2
                        fi
                    else
                        /usr/local/bin/nova boot --flavor $FLAVOR --image $IMG_ID --key_name $K_NAME $INST_NAME2
                    fi

                    # Wait until an instance state becomes "ACTIVE".
                    COUNT=0
                    while :; do
                        if [ $COUNT -gt $TIMEOUT ]; then
                            echo "Expired. [$TIMEOUT]"
                            break
                        fi
                        STATUS=`/usr/local/bin/nova show $INST_NAME2 | awk '/status/{print $4}'`
                        if [ "$STATUS" != "ACTIVE" ]; then
                            COUNT=`expr $COUNT + 5`
                        else
                            break
                        fi
                        sleep 5
                    done

                    # Real local IP is written shared file.
                    FIXED=`/usr/local/bin/nova show $INST_NAME2 | awk '/network/{print $5}'`
                    echo FIXED_IP $FIXED >> $SHAREDIR/recovered/$INST_NAME2

                    # When original instance is associated with floating IP,
                    # try to keep as possible an original floating IP too.
                    FLOATING=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/network/{print $6}'`
                    if [ "$FLOATING" != "|" ]; then

                        # When the floating IP is in use, complete a process without associating with it.
                        ASSOC=`/usr/local/bin/nova floating-ip-list | awk '/'$FLOATING'/{print $4}'`
                        if [ "$ASSOC" == "None" ]; then
                            /usr/local/bin/nova add-floating-ip $INST_NAME2 $FLOATING
                            echo FLOATING_IP $FLOATING >> $SHAREDIR/recovered/$INST_NAME2
                        fi
                    fi
                fi
            fi

        # It's case that same name tenant does not exist on DR destination cloud.
        # In this case, launch instance as that of 'anonymous' tenant.
        else

            # Load 'anonymous' tenant administrator's openrc file.
            TENANT="anonymous"
            . $SHAREDIR/env/$HOSTNAME/openrc_$TENANT

            # Check whether copy image's ID exists.
            IMG_ID=`/usr/local/bin/glance -f index | awk '/'$PREFIX1$INST_NAME1'/{print $1}'`
            if [ "$IMG_ID" != "" ]; then

                # Check whether same name instance exists. Name format is 'MIG_<instance_name>'.
                INST_NAME2=$PREFIX2$INST_NAME1
                CHECK=`/usr/local/bin/nova list | grep -w $INST_NAME2`

                # When that instance does not exist, launch instance.
                if [ "$CHECK" == "" ]; then

                    # Pick up the information from shared files.
                    TENANT_ID=`cat $BASEDIR/tmp/tenant_list | awk '/'$TENANT'/{print $2}'`
                    FIXED=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/network/{print $5}'`
                    NET_ID=`/usr/bin/mysql -N -r -B -u$ACCOUNT -p$PASSWD -e "select uuid from nova.networks where dhcp_start like '${FIXED%.*}%' and project_id = '$TENANT_ID';"`
                    F_NAME=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/flavor/{print $4}'`
                    FLAVOR=`/usr/local/bin/nova flavor-list | grep -w $F_NAME | awk '{print $2}'`

                    # When that flavor does not exist on DR destination cloud,
                    # select flavor 'm1.small'.
                    if [ "$FLAVOR" == "" ]; then
                        FLAVOR=`/usr/local/bin/nova flavor-list | grep -w m1.small | awk '{print $2}'`
                    fi

                    # Check whether same name keypair exists.
                    K_NAME=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/key_name/{print $4}'`
                    CHECK=`/usr/local/bin/nova keypair-list | grep -w $K_NAME`
                    if [ "$CHECK" == "" ]; then

                        # When that keypair does not exist on DR destination cloud,
                        # create new keypair 'default'.
                        K_NAME="default"
                        CHECK=`/usr/local/bin/nova keypair-list | grep -w $K_NAME`
                        if [ "$CHECK" == "" ]; then
                            /usr/local/bin/nova keypair-add default > $SHAREDIR/keypair/$HOSTNAME/$TENANT/$K_NAME.pem
                        fi
                    fi

                    # Recovered instance information is written shared file.
                    echo LAUNCH_USER $OS_USERNAME > $SHAREDIR/recovered/$INST_NAME2
                    echo HOST_NAME $HOSTNAME >> $SHAREDIR/recovered/$INST_NAME2
                    echo TENANT_NAME $TENANT >> $SHAREDIR/recovered/$INST_NAME2
                    echo KEY_NAME $K_NAME >> $SHAREDIR/recovered/$INST_NAME2

                    # Launch instance.
                    # Keep as possible an original local IP.
                    if [ "$NET_ID" != "" ]; then
                        RES=`/usr/local/bin/nova list | grep -w $FIXED`
                        if [ "$RES" != "" ]; then
                            /usr/local/bin/nova boot --flavor $FLAVOR --image $IMG_ID --key_name $K_NAME --nic net-id=$NET_ID $INST_NAME2
                        else
                            /usr/local/bin/nova boot --flavor $FLAVOR --image $IMG_ID --key_name $K_NAME --nic net-id=$NET_ID,v4-fixed-ip=$FIXED $INST_NAME2
                        fi
                    else
                        /usr/local/bin/nova boot --flavor $FLAVOR --image $IMG_ID --key_name $K_NAME $INST_NAME2
                    fi

                    # Wait until an instance state becomes "ACTIVE".
                    COUNT=0
                    while :; do
                        if [ $COUNT -gt $TIMEOUT ]; then
                            echo "Expired. [$TIMEOUT]"
                            break
                        fi
                        STATUS=`/usr/local/bin/nova show $INST_NAME2 | awk '/status/{print $4}'`
                        if [ "$STATUS" != "ACTIVE" ]; then
                            COUNT=`expr $COUNT + 5`
                        else
                            break
                        fi
                        sleep 5
                    done

                    # Real local IP is written shared file.
                    FIXED=`/usr/local/bin/nova show $INST_NAME2 | awk '/network/{print $5}'`
                    echo FIXED_IP $FIXED >> $SHAREDIR/recovered/$INST_NAME2

                    # When original instance is associated with floating IP,
                    # try to keep as possible an original floating IP too.
                    FLOATING=`cat $SHAREDIR/target/$SOURCE_HOST/$LINE/$INST_NAME1$SUFFIX | awk '/network/{print $6}'`
                    if [ "$FLOATING" != "|" ]; then

                        # When the floating IP is in use, complete a process without associating with it.
                        ASSOC=`/usr/local/bin/nova floating-ip-list | awk '/'$FLOATING'/{print $4}'`
                        if [ "$ASSOC" == "None" ]; then
                            /usr/local/bin/nova add-floating-ip $INST_NAME2 $FLOATING
                            echo FLOATING_IP $FLOATING >> $SHAREDIR/recovered/$INST_NAME2
                        fi
                    fi
                fi
            fi
        fi
    done < "$SHAREDIR/target/$SOURCE_HOST/dr_target_list"
done < "$SHAREDIR/env/$HOSTNAME/source_host_list"

rm $BASEDIR/tmp/tenant_list
