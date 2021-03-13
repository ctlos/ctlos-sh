#!/bin/bash

curl -sO https://raw.githubusercontent.com/ctlos/ctlos-sh/master/strap.sh
sh strap.sh
rm strap.sh

echo "==== Done settings.sh ===="

rm /usr/local/bin/settings.sh
