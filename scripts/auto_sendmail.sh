#!/bin/bash

# This script's aim is sending mail to tenant administrator when instance launch on DR destination cloud.
# It's expected that this script works by CRON.
# ex)
# 00 */1 * * * /var/lib/dr/script/auto_sendmail.sh > /dev/null

# Set shell variables.
BASEDIR=/var/lib/dr
SHAREDIR=/opt/share

# Get recovered instance names.
# And these are written down a temporary file.
ls -l /opt/share/recovered/ | awk 'NR>=2{print $9}' > $BASEDIR/tmp/recovered_list

while read LIST; do

    # Pick up the information from shared files.
    cp $SHAREDIR/utils/mail_template $BASEDIR/tmp/mail_template
    HOSTNAME=`cat $SHAREDIR/recovered/$LIST | awk '/HOST_NAME/{print $2}'`
    . $SHAREDIR/env/$HOSTNAME/openrc_admin
    TENANTNAME=`cat $SHAREDIR/recovered/$LIST | awk '/TENANT_NAME/{print $2}'`
    KEYNAME=`cat $SHAREDIR/recovered/$LIST | awk '/KEY_NAME/{print $2}'`
    FIXED=`cat $SHAREDIR/recovered/$LIST | awk '/FIXED_IP/{print $2}'`
    FLOATING=`cat $SHAREDIR/recovered/$LIST | awk '/FLOATING_IP/{print $2}'`
    USERNAME=`cat $SHAREDIR/recovered/$LIST | awk '/LAUNCH_USER/{print $2}'`

    # Get tenant administrator's address.
    EMAIL=`/usr/local/bin/keystone user-list | awk '/'$USERNAME'/{print $6}'`

    # Create a mail content.
    sed -e "
       s,%TENANT_NAME%,$TENANTNAME,g;s,%USER_NAME%,$USERNAME,g;
       s,%KEY_NAME%,$KEYNAME,g;s,%FIXED_IP%,$FIXED,g;
    " -i $BASEDIR/tmp/mail_template
    ADMIN_EMAIL=`cat $SHAREDIR/utils/settings | awk '/EMAIL/{print $2}'`
    SUBJECT=`cat $SHAREDIR/utils/settings | awk '/SUBJECT/{print $2}'`

    # Add a line about floating IP.
    if [ "$FLOATING" != "" ]; then
        echo Global IP:$FLOATING >> $BASEDIR/tmp/mail_template
    else
        echo Global IP:Not associated >> $BASEDIR/tmp/mail_template
    fi

    # When keypair is created newly, attach it to mail.
    if [ "$KEYNAME" == "default" ]; then
        (cat $BASEDIR/tmp/mail_template ; uuencode $SHAREDIR/keypair/$HOSTNAME/$TENANTNAME/default.pem default.pem) | /usr/bin/nkf -j | /usr/bin/mail -a From:$ADMIN_EMAIL -a 'MIME-Version: 1.0' -a 'Content-Type: text/plain; charset="UTF-8"' -a 'Content-Transfer-Encoding: 7bit' -s $SUBJECT -t $EMAIL
    else
        cat $BASEDIR/tmp/mail_template | /usr/bin/mail -a From:$ADMIN_EMAIL -a 'MIME-Version: 1.0' -a 'Content-Type: text/plain; charset="UTF-8"' -a 'Content-Transfer-Encoding: 7bit' -s $SUBJECT -t $EMAIL
    fi

    rm $SHAREDIR/recovered/$LIST
done < "$BASEDIR/tmp/recovered_list"

rm $BASEDIR/tmp/*
