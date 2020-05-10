#!/bin/sh
echo "Usage: $0 "
i=1
while [ "$i" -lt 254 ]
do
  ping -c 1 -W 1 "$1.$i" > /dev/null
    if [ "$?" -ne 1 ]
    then
        echo "$1.$i SUCCESS !"
    else
        echo "$1.$i fail"
    fi
    i=$(( $i + 1 ))
done
