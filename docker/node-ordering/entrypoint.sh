#!/bin/bash

function resolve_host() {
  host="$1"
  check="nslookup $host"
  max_retry=10
  counter=0
  backoff=0.1
  until $check > /dev/null
  do
    if [ $counter -eq $max_retry ]; then
      return
    fi
    sleep $backoff
    ((counter++))
    backoff=$(echo - | awk "{print $backoff + $backoff}")
  done
}

until [ $(cat /etc/mpi/discover_hosts.sh | wc -l) != 1 ]
do
  sleep 5
  echo "$(date) -- Waiting for all worker pods to be ready"
done

cat /etc/mpi/hostfile | while read host
  do
    resolve_host $host
  done

/etc/mpi/discover_hosts.sh > /node-ordering/hosts

/node_ordering.py --input_file /node-ordering/hosts > /dev/null

cp /ordered_hostfile /node-ordering/

echo "$(date) -- All worker pods are ready"