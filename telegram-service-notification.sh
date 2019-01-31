#!/usr/bin/env bash
#
# Copyright (C) 2012-2017 Icinga Development Team (https://www.icinga.com/)

PROG="`basename $0`"

## Function helpers
Usage() {
cat << EOF

Required parameters:
  -4 HOSTADDRESS (\$address\$)
  -d LONGDATETIME (\$icinga.long_date_time\$)
  -e SERVICENAME /\$service.name\$)
  -l HOSTNAME (\$host.name\$)
  -n HOSTDISPLAYNAME (\$host.display_name\$)
  -o SERVICEOUTPUT (\$service.output\$)
  -s SERVICESTATE (\$service.state\$)
  -t NOTIFICATIONTYPE (\$notification.type\$)
  -u SERVICEDISPLAYNAME (\$service.display_name\$)
  -x TELEGRAM_CHAT_ID (\$telegram_chat_id\$)
  -y TELEGRAM_BOT_TOKEN (\$telegram_bot_token\$)

Optional parameters:
  -6 HOSTADDRESS6 (\$address6\$)
  -b NOTIFICATIONAUTHORNAME (\$notification.author\$)
  -c NOTIFICATIONCOMMENT (\$notification.comment\$)
  -i ICINGAWEB2URL (\$notification_icingaweb2url\$, Default: unset)
  -v (\$notification_sendtosyslog\$, Default: false)

EOF
}

Help() {
  Usage;
  exit 0;
}

Error() {
  if [ "$1" ]; then
    echo $1
  fi
  Usage;
  exit 1;
}

## Main
while getopts 4:6::b:c:d:e:hi:l:n:o:s:t:v:u:x:y: opt
do
  case "$opt" in
    4) HOSTADDRESS=$OPTARG ;; # required
    6) HOSTADDRESS6=$OPTARG ;;
    b) NOTIFICATIONAUTHORNAME=$OPTARG ;;
    c) NOTIFICATIONCOMMENT=$OPTARG ;;
    d) LONGDATETIME=$OPTARG ;; # required
    e) SERVICENAME=$OPTARG ;;
    h) Help ;;
    i) ICINGAWEB2URL=$OPTARG ;;
    l) HOSTNAME=$OPTARG ;; # required
    n) HOSTDISPLAYNAME=$OPTARG ;; # required
    o) SERVICEOUTPUT=$OPTARG ;; # required
    s) SERVICESTATE=$OPTARG ;; # required
    t) NOTIFICATIONTYPE=$OPTARG ;; # required
    v) VERBOSE=$OPTARG ;;
    u) SERVICEDISPLAYNAME=$OPTARG ;; #required
    x) TELEGRAM_CHAT_ID=$OPTARG ;; # required
    y) TELEGRAM_BOT_TOKEN=$OPTARG ;; # required
   \?) echo "ERROR: Invalid option -$OPTARG" >&2
       Error ;;
    :) echo "Missing option argument for -$OPTARG" >&2
       Error ;;
    *) echo "Unimplemented option: -$OPTARG" >&2
       Error ;;
  esac
done

shift $((OPTIND - 1))

## Check required parameters (TODO: better error message)
## Keep formatting in sync with mail-service-notification.sh
if [ ! "$HOSTADDRESS" ] || [ ! "$LONGDATETIME" ] \
|| [ ! "$HOSTNAME" ] || [ ! "$HOSTDISPLAYNAME" ] \
|| [ ! "$SERVICENAME" ] || [ ! "$SERVICEDISPLAYNAME" ] \
|| [ ! "$SERVICEOUTPUT" ] || [ ! "$SERVICESTATE" ] \
|| [ ! "$TELEGRAM_CHAT_ID" ] || [ ! "$TELEGRAM_BOT_TOKEN" ] || [ ! "$NOTIFICATIONTYPE" ]; then
  Error "Requirement parameters are missing."
fi


## Build the message's subject
SUBJECT="[$NOTIFICATIONTYPE] $SERVICEDISPLAYNAME on $HOSTDISPLAYNAME is $SERVICESTATE!"

## Build the notification message
NOTIFICATION_MESSAGE=`cat << EOF
***** Icinga 2 Service Monitoring on $HOSTNAME *****

==> $SERVICEDISPLAYNAME on $HOSTDISPLAYNAME is $SERVICESTATE! <==

Info:    $SERVICEOUTPUT

When:    $LONGDATETIME
Service: $SERVICENAME (Display Name: "$SERVICEDISPLAYNAME")
Host:    $HOSTNAME (Display Name: "$HOSTDISPLAYNAME")
IPv4:    $HOSTADDRESS
EOF
`

## Check whether IPv6 was specified.
if [ -n "$HOSTADDRESS6" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE
IPv6:    $HOSTADDRESS6"
fi

## Check whether author and comment was specified.
if [ -n "$NOTIFICATIONCOMMENT" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE

Comment by $NOTIFICATIONAUTHORNAME:
  $NOTIFICATIONCOMMENT"
fi

## Check whether Icinga Web 2 URL was specified.
if [ -n "$ICINGAWEB2URL" ] ; then
  NOTIFICATION_MESSAGE="$NOTIFICATION_MESSAGE

URL:
  $ICINGAWEB2URL/monitoring/service/show?host=$HOSTNAME&service=$SERVICENAME"
fi

## Check whether verbose mode was enabled and log to syslog.
if [ "$VERBOSE" == "true" ] ; then
  logger "$PROG sends $SUBJECT => $TELEGRAM_CHAT_ID"
fi

/usr/bin/curl --silent --output /dev/null \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$NOTIFICATION_MESSAGE" \
    --data-urlencode "parse_mode=MARKDOWN" \
    --data-urlencode "disable_web_page_preview=true" \
    "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
