#!/bin/bash

# Define the log file
LOG_FILE="net-scan-ip.log"

#IP="188.165.53.185"

# Loop through all IPv4 addresses
for i in $(seq 1 254); do
  for j in $(seq 1 254); do
    for k in $(seq 1 254); do
      for l in $(seq 1 254); do
        # Format the IP address
        IP="$i.$j.$k.$l"

        # Skip private addresses
        if [[ $IP =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ && ! $IP =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
          # Use nmap to check the ports
          RESULT=$(nmap -Pn -p 22,80,443 $IP | grep -E '/tcp' | awk '{print "("$3"="$2")"}')

          # Format the result
          LINE="$(date) - $IP - $RESULT"

          # Append the result to the log file
          echo $LINE >> $LOG_FILE
        fi
      done
    done
  done
done
