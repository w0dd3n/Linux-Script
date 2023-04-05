#!/bin/bash

LOG_FILE=/var/log/tempmon.log
FROM_ADDR=contact@tanooki.fr
TO_ADDR=cedric.obejero@tanooki.fr

# Recommended values are as follow
# High Core is 81.00°C
# Crit Core is 91.00°C
CPU_WARN_TEMP=65000
CPU_HIGH_TEMP=75000

temp=$(cat /sys/class/thermal/thermal_zone0/temp)
timestamp=$(date -Iminutes)
if [[ temp -lt CPU_WARN_TEMP ]]; then 
        log_level=$(printf "[ INFOS    ] ${timestamp} CPU Core: +%2s.%sC\n" ${temp:0:-3} ${temp: -3:2})
elif [[ temp -gt CPU_HIGH_TEMP ]]; then
        log_level=$(printf "[ CRITICAl ] ${timestamp} CPU Core: +%2s.%sC\n" ${temp:0:-3} ${temp: -3:2}) 
        echo " " | mail -s "${log_level}" -r ${FROM_ADDR} ${TO_ADDR}
else
        log_level=$(printf "[ WARNING  ] ${timestamp} CPU Core: +%2s.%sC\n" ${temp:0:-3} ${temp: -3:2}) 
        echo " " | mail -s "${log_level}" -r ${FROM_ADDR} ${TO_ADDR}
fi
echo "${log_level}" >> ${LOG_FILE}
