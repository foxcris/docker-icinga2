FROM debian:stretch

MAINTAINER foxcris

#repositories richtig einrichten (wir brauchen non-free)
RUN echo 'deb http://deb.debian.org/debian stretch main non-free' > /etc/apt/sources.list
RUN echo 'deb http://deb.debian.org/debian stretch-updates main non-free' >> /etc/apt/sources.list
RUN echo 'deb http://security.debian.org stretch/updates main non-free' >> /etc/apt/sources.list
#backports fuer certbot
RUN echo 'deb http://ftp.debian.org/debian stretch-backports main' >> /etc/apt/sources.list


#locale richtig setzen
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y locales && apt-get clean
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen && \
    echo 'LANG="en_US.UTF-8"'>/etc/default/locale && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV LANG en_US.UTF8

#https://github.com/Icinga/icingaweb2-module-businessprocess
ENV VERSION_icingaweb2_businessprocess=2.1.0
#https://github.com/Icinga/icingaweb2-module-director
ENV VERSION_icingaweb2_director=1.6.0
#https://github.com/Mikesch-mp/icingaweb2-module-grafana
ENV VERSION_icingaweb2_grafana=1.3.4

#https://github.com/graphite-project/graphite-web/releases
ENV VERSION_graphite_graphite_web=1.1.5
#https://github.com/graphite-project/whisper
ENV VERSION_graphite_whisper=1.1.5
#https://github.com/graphite-project/carbon/releases
ENV VERSION_graphite_carbon=1.1.5

#automatische aktualiserung installieren + basic tools
RUN apt-get update && apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install -y nano less wget gnupg anacron unattended-upgrades apt-transport-https crudini htop sudo && apt-get clean

#apache
RUN apt-get update && apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 libapache2-mod-wsgi && apt-get clean

#certbot
RUN apt-get update && apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install -y python-certbot-apache -t stretch-backports && apt-get clean


#ssl zertifikat fuer apache mit lets encrypt unterstuetzen
#RUN echo "#/bin/bash" > /etc/cron.daily/certbot
#RUN echo 'certbot renew --renew-hook "apachectl -k graceful"' >> /etc/cron.daily/certbot
#RUN chmod a+x /etc/cron.daily/certbot

#wichtige/nuetzliche packete im apache aktivieren
RUN a2enmod proxy_http
RUN a2enmod proxy_wstunnel
RUN a2enmod ssl
RUN a2enmod remoteip
RUN a2enmod rewrite
RUN a2enmod wsgi
RUN a2enmod headers

#repository fuer icinga2 hinzufuegen
RUN wget -q -O - https://packages.icinga.com/icinga.key | apt-key add -
RUN echo 'deb https://packages.icinga.com/debian icinga-stretch main' >/etc/apt/sources.list.d/icinga.list
#repository fuer grafana hinzufuergen
RUN wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
RUN echo 'deb https://packages.grafana.com/oss/deb stable main' > /etc/apt/sources.list.d/grafana.list
#installation
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y icinga2 monitoring-plugins mysql-client icinga2-ido-mysql icingaweb2 grafana php-curl php-gd nagios-nrpe-plugin nagios-snmp-plugins nagios-plugins-contrib snmp libsnmp-dev snmp-mibs-downloader&& apt-get clean

#enable required icinga2 modules/features
RUN icinga2 feature enable ido-mysql
RUN icinga2 api setup
RUN icinga2 feature enable graphite

#configure icingaweb api access
RUN echo 'object ApiUser "icingaweb2" {\n  password = "changeme"\n  permissions = [ "status/query", "actions/*", "objects/modify/*", "objects/query/*" ]\n}' >> /etc/icinga2/conf.d/api-users.conf
#configure director api access
RUN echo 'object ApiUser "director" {\n  password = "changeme"\n  permissions = [ "*" ]\n}' >> /etc/icinga2/conf.d/api-users.conf

#icingaweb setup token generieren
#anschauen mit icingacli setup token show
RUN icingacli setup toke create

#install graphite
#RUN sed -i 's/CARBON_CACHE_ENABLED.*/CARBON_CACHE_ENABLED=true/' /etc/default/graphite-carbon
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python-pip libffi-dev libcairo2 && apt-get clean
RUN export PYTHONPATH="/opt/graphite/lib/:/opt/graphite/webapp/" && pip install --no-cache-dir --no-binary=:all: https://github.com/graphite-project/whisper/archive/$VERSION_graphite_whisper.tar.gz && pip install --no-cache-dir --no-binary=:all: https://github.com/graphite-project/carbon/archive/$VERSION_graphite_carbon.tar.gz && pip install --no-cache-dir --no-binary=:all: https://github.com/graphite-project/graphite-web/archive/$VERSION_graphite_graphite_web.tar.gz && pip install --no-cache-dir service_identity
RUN cd /opt/graphite/conf && for i in *.example; do cp -a $i ${i%%.example}; done
RUN cp /opt/graphite/examples/example-graphite-vhost.conf /etc/apache2/sites-available/graphite-vhost.conf
RUN sed -i 's#.*VirtualHost.*#<VirtualHost *:8000>#' /etc/apache2/sites-available/graphite-vhost.conf
RUN sed -i 's#.*WSGISocketPrefix.*#WSGISocketPrefix /var/run/wsgi#' /etc/apache2/sites-available/graphite-vhost.conf
RUN echo Listen 8000 >> /etc/apache2/ports.conf
RUN mkdir -p /var/run/wsgi
RUN PYTHONPATH=/opt/graphite/webapp django-admin.py migrate --settings=graphite.settings --run-syncdb
RUN chown www-data:www-data /opt/graphite/storage/graphite.db
RUN chown www-data:www-data /opt/graphite/storage
RUN mkdir -p /opt/graphite/storage/log/webapp
RUN chown -R www-data:www-data /opt/graphite/storage/log/webapp
RUN a2ensite graphite-vhost
#RUN cp /opt/graphite/examples/init.d/carbon-cache /etc/init.d/
RUN wget -q -O /etc/init.d/carbon-cache https://raw.githubusercontent.com/graphite-project/carbon/master/distro/debian/init.d/carbon-cache
RUN chmod a+x /etc/init.d/carbon-cache
#Storage Schema fuer carbon-cache einstellen
RUN sed -i 's#\[default_1min_for_1day\]#\n\[icinga2_default\]\npattern = ^icinga2\\.\nretentions = 1m:7d,5m:30d,30m:90d,60m:365d,120m:2y,240m:4y\n\n\[default_1min_for_1day\]#' /opt/graphite/conf/storage-schemas.conf

#basic auth fuer grafana zugriff
RUN mkdir -p /etc/apache2/auth
#RUN htpasswd -cb /etc/apache2/auth/grafana-passwd admin admin
COPY grafana.conf /etc/apache2/sites-available/
RUN a2ensite grafana

#graphite im apache aktivieren
#RUN a2ensite graphite

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y curl mawk && apt-get clean
#business process installieren
RUN install -d -m 0755 /usr/share/icingaweb2/modules/businessprocess
#RUN wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-businessprocess/archive/master.tar.gz" \ | tar xz --strip-components=1 --directory=/usr/share/icingaweb2/modules/businessprocess -f - && icingacli module enable businessprocess
RUN wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-businessprocess/archive/v$VERSION_icingaweb2_businessprocess.tar.gz" \ | tar xz --strip-components=1 --directory=/usr/share/icingaweb2/modules/businessprocess -f - && icingacli module enable businessprocess

#icinga director installieren
RUN mkdir -p /usr/share/icingaweb2/modules/director/
#RUN wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-director/archive/master.tar.gz" \ | tar xz --strip-components=1 --directory=/usr/share/icingaweb2/modules/director --exclude=.gitignore -f - && icingacli module enable director
RUN wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-director/archive/v$VERSION_icingaweb2_director.tar.gz" \ | tar xz --strip-components=1 --directory=/usr/share/icingaweb2/modules/director --exclude=.gitignore -f - && icingacli module enable director
RUN echo 'object Zone "director-global" {\n  global = true\n}' >> /etc/icinga2/zones.conf

#icingaweb2 grafana module installieren
RUN mkdir -p /usr/share/icingaweb2/modules/grafana/
#RUN wget -q --no-cookies -O - "https://github.com/Mikesch-mp/icingaweb2-module-grafana/archive/master.tar.gz" \ | tar xz --strip-components=1 --directory=/usr/share/icingaweb2/modules/grafana -f - icingaweb2-module-grafana-master/
RUN wget -q --no-cookies -O - "https://github.com/Mikesch-mp/icingaweb2-module-grafana/archive/v$VERSION_icingaweb2_grafana.tar.gz" \ | tar xz --strip-components=1 --directory=/usr/share/icingaweb2/modules/grafana -f - icingaweb2-module-grafana-$VERSION_icingaweb2_grafana/

#damit der Zugriff für den icingaweb2 wizard klappt
RUN usermod -a -G icingaweb2 www-data
RUN chmod -R g+w /etc/icingaweb2

#zusaetzliche plugins fuer icinga
RUN wget -q -O /usr/lib/nagios/plugins/check_openvpn https://raw.githubusercontent.com/liquidat/nagios-icinga-openvpn/master/bin/check_openvpn
RUN chmod a+x /usr/lib/nagios/plugins/check_openvpn

RUN wget -q -O /usr/lib/nagios/plugins/check_snmp_interface https://raw.githubusercontent.com/iamcheko/check_snmp_interface/master/libexec/check_snmp_interface
RUN chmod a+x /usr/lib/nagios/plugins/check_snmp_interface

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y sysstat && apt-get clean
RUN wget -q -O /usr/lib/nagios/plugins/check_iostat "https://exchange.nagios.org/components/com_mtree/attachment.php?link_id=5841&cf_id=24"
RUN chmod a+x /usr/lib/nagios/plugins/check_iostat

RUN apt-get update && apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install -y curl && apt-get clean
COPY telegram-host-notification.sh /etc/icinga2/scripts/telegram-host-notification.sh
COPY telegram-service-notification.sh /etc/icinga2/scripts/telegram-service-notification.sh
RUN chmod a+x /etc/icinga2/scripts/telegram-host-notification.sh
RUN chown nagios:nagios /etc/icinga2/scripts/telegram-host-notification.sh
RUN chmod a+x /etc/icinga2/scripts/telegram-service-notification.sh
RUN chown nagios:nagios /etc/icinga2/scripts/telegram-service-notification.sh

RUN wget -q -O /usr/lib/nagios/plugins/check_postgres.pl https://raw.githubusercontent.com/bucardo/check_postgres/master/check_postgres.pl
RUN chmod a+x /usr/lib/nagios/plugins/check_postgres.pl

RUN wget -q -O /usr/lib/nagios/plugins/check_cpu.py https://raw.githubusercontent.com/georgehansper/check_cpu.py/master/check_cpu.py
RUN chmod a+x /usr/lib/nagios/plugins/check_cpu.py

RUN wget -q -O /usr/lib/nagios/plugins/check_postgres.pl https://raw.githubusercontent.com/bucardo/check_postgres/master/check_postgres.pl
RUN chmod a+x /usr/lib/nagios/plugins/check_postgres.pl

RUN apt-get update && apt-get -y upgrade && DEBIAN_FRONTEND=noninteractive apt-get install -y python-pywbem && apt-get clean
RUN wget -q -O /usr/lib/nagios/plugins/check_esxi_hardware.py https://www.claudiokuenzler.com/nagios-plugins/check_esxi_hardware.py
RUN chmod a+x /usr/lib/nagios/plugins/check_esxi_hardware.py

#save default icinga2 configuration
RUN mv /etc/icinga2 /etc/icinga2_default
RUN mv /var/lib/icinga2 /var/lib/icinga2_default
RUN mv /opt/graphite/storage /opt/graphite/storage_default
RUN mv /etc/icingaweb2 /etc/icingaweb2_default
RUN mv /etc/grafana /etc/grafana_default
RUN mv /var/lib/grafana /var/lib/grafana_default
RUN mv /etc/apache2/auth /etc/apache2/auth_default
#RUN mv /etc/ssmtp /etc/ssmtp_default

#default apache configuration deaktivieren
RUN a2dissite 000-default
RUN a2dissite default-ssl

#save default apache sites
RUN mv /etc/apache2/sites-available/ /etc/apache2/sites-available_default

#zeitzone fuer php richtig einstellen
RUN sed -i 's#;date.timezone.*#date.timezone="Europe/Berlin"#' /etc/php/7.0/apache2/php.ini

#logverzeichnis fuer icingaweb2 anlegen
RUN mkdir -p /var/log/icingaweb2
RUN chown www-data:www-data /var/log/icingaweb2

#TKAlert fuer Thomas Krenn installieren
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y python-setuptools git && apt-get clean
#Das Repo verlangt plötzlich Zugangsdaten
RUN mkdir -p /usr/local/share/tkalert && cd /usr/local/share/tkalert &&  git clone https://github.com/NETWAYS/tkmon-tkalert . && python setup.py install && ln -s /usr/local/bin/tkalert /usr/bin/tkalert
#COPY tkalert.tar  /usr/local/share
#RUN cd /usr/local/share && tar xf tkalert.tar && cd tkalert && python setup.py install && ln -s /usr/local/bin/tkalert /usr/bin/tkalert
RUN echo 'nagios ALL=(ALL)NOPASSWD:/usr/bin/tkalert' > /etc/sudoers.d/tkmon && chmod 440 /etc/sudoers.d/tkmon
RUN sed -i "s#'type': 'int',#'type': 'float',#" /usr/local/lib/python2.7/dist-packages/tkalert-1.5-py2.7.egg/tkalert/options.py

EXPOSE 80 443 3000 5665 8000
COPY docker-entrypoint.sh /
RUN chmod 755 /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
