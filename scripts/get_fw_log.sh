#!/bin/sh

BASE="https://${ROUTER_IP:-192.168.1.1}"
PW=$(cat /run/secrets/router_pw)
IP_CHECK_URL="${IP_CHECK_URL:-https://ip.kyxap.pro/csv/}"

my_ip=$(wget -qO- "$IP_CHECK_URL" | cut -d, -f1)
[ "$my_ip" != "$HOME_IP" ] && echo "$(date): not home ($my_ip)" && exit 0

arc_md5() { printf '%s' "$1" | md5sum | awk '{print $1}' | tr -d '\n' | sha512sum | awk '{print $1}'; }

token=$(wget -qO- --no-check-certificate \
  --header "Host: mynetworksettings.com" \
  --header "Referer: ${BASE}/" \
  "${BASE}/loginStatus.cgi" | sed -n 's/.*"loginToken":"\([^"]*\)".*/\1/p')

[ -z "$token" ] && echo "$(date): no token" && exit 1

luci_pw=$(printf '%s' "${token}$(arc_md5 "$PW")" | sha512sum | awk '{print $1}')
wget -S --no-check-certificate \
  --header "Host: mynetworksettings.com" \
  --header "Referer: ${BASE}/" \
  --post-data "luci_username=$(arc_md5 admin)&luci_password=${luci_pw}&luci_view=Desktop&luci_token=${token}&luci_keep_login=0" \
  -O /dev/null "${BASE}/login.cgi" 2>/tmp/headers
cookie=$(sed -n 's/.*Set-Cookie: \([^;]*\).*/\1/p' /tmp/headers | head -1)
rm -f /tmp/headers

wget -qO /tmp/messages_FW.log --no-check-certificate \
  --header "Host: mynetworksettings.com" \
  --header "Referer: ${BASE}/" \
  --header "Cookie: ${cookie}" \
  "${BASE}/log/messages_FW.log"

STATE="/data/last_ts"
last=""
[ -f "$STATE" ] && last=$(cat "$STATE")

tail -1 /tmp/messages_FW.log > "$STATE"

if [ -n "$last" ] && grep -qF "$last" /tmp/messages_FW.log; then
  awk -v last="$last" 'index($0,last){found=1;next} found{print}' /tmp/messages_FW.log
else
  cat /tmp/messages_FW.log
fi | awk '{
  s=6
  if($5=="emerg")s=0;else if($5=="alert")s=1;else if($5=="crit")s=2
  else if($5=="err")s=3;else if($5=="warning")s=4;else if($5=="notice")s=5
  else if($5=="debug")s=7
  m="";for(i=6;i<=NF;i++){if(i>6)m=m" ";m=m$i}
  printf "<%d>%s %2d %s router %s\n",s,$2,$3+0,$4,m
}' > /tmp/rfc3164.log

[ -s /tmp/rfc3164.log ] && loggen -T --read-file /tmp/rfc3164.log --dont-parse --inet --dgram alloy 514

rm -f /tmp/messages_FW.log /tmp/rfc3164.log
echo "$(date): done"
