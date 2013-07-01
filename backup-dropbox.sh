#!/bin/bash

cd ~/Dropbox
DIRS=`find . -mindepth 1 -maxdepth 1 -type d | egrep -v "(\/Camera Uploads$|\/Photos$|\/.dropbox.cache$)"`
DATE=`date +%Y-%m-%d`
FILE="/home/krux/backup/Dropbox/dropbox-$DATE.tar.bz2"

echo "Archiving Dropbox directories ..."
tar -cjf $FILE $DIRS
echo "Done!"
