#!/bin/bash
if [ `ls /etc/apache2/sites-available/ | wc -l` -eq 0 ]
then
  cp -ra /etc/apache2/sites-available_default/* /etc/apache2/sites-available/
fi

if [ `ls /etc/icinga2/ | wc -l` -eq 0 ]
then
  cp -ra /etc/icinga2_default/* /etc/icinga2/
  chown -R nagios:nagios /etc/icinga2
fi

if [ `ls /var/lib/icinga2/ | wc -l` -eq 0 ]
then
  cp -ra /var/lib/icinga2_default/* /var/lib/icinga2/
  chown -R nagios:nagios /var/lib/icinga2
fi

if [ `ls /opt/graphite/storage | wc -l` -eq 0 ]
then
  cp -ra /opt/graphite/storage_default/* /opt/graphite/storage/
fi

if [ `ls /etc/icingaweb2/ | wc -l` -eq 0 ]
then
  cp -ra /etc/icingaweb2_default/* /etc/icingaweb2/
  chown -R root:www-data /etc/icingaweb2
  chmod ug+rw /etc/icingaweb2
  chmod g+s /etc/icingaweb2
fi

if [ `ls /etc/grafana/ | wc -l` -eq 0 ]
then
  cp -ra /etc/grafana_default/* /etc/grafana/
fi

if [ `ls /var/lib/grafana/ | wc -l` -eq 0 ]
then
  cp -ra /var/lib/grafana_default/* /var/lib/grafana/
fi

if [ `ls /etc/apache2/auth/ | wc -l` -eq 0 ]
then
  cp -ra /etc/apache2/auth_default/* /etc/apache2/auth/
fi

#if [ `ls /etc/ssmtp/ | wc -l` -eq 0 ]
#then
#  cp -ra /etc/ssmtp_default/* /etc/ssmtp/
#fi

chown -R nagios:nagios /var/log/icinga2
chown -R www-data:www-data /var/log/icingaweb2
chown -R www-data:www-data /opt/graphite/storage

echo $MAILNAME > /etc/mailname
echo root:$ROOTMAIL >> /etc/aliases 

#Exim Update durchführen falls config angepasst wurde
update-exim4.conf
/etc/init.d/exim4 start

#List site and enable
ls /etc/apache2/sites-available/ -1A | a2ensite *.conf

#LETSECNRYPT
/usr/sbin/apache2ctl start
certbot --apache -n -d $LETSENCRYPTDOMAINS --agree-tos --email $LETSENCRYPTEMAIL
/usr/sbin/apache2ctl stop

#Start Cron
/etc/init.d/anacron start
/etc/init.d/cron start

#Start carbonserver
/etc/init.d/carbon-cache start

#Start grafana
/etc/init.d/grafana-server start

#Start Icinga
/etc/init.d/icinga2 start

#Launch Apache on Foreground
/usr/sbin/apache2ctl -D FOREGROUND

