#!/bin/bash

cd ~/Dropbox
DIRS=`find . -mindepth 1 -maxdepth 1 -type d | egrep -v "(\/Camera Uploads$|\/Photos$|\/.dropbox.cache$)"`
DATE=`date +%Y-%m-%d`
BACKUPDIR="/home/krux/backup/Dropbox"
FILE="$BACKUPDIR/dropbox-$DATE.tar.bz2"

if [ ! -d $BACKUPDIR ]; then
	echo "Creating backup dir ..."
	mkdir -p $BACKUPDIR
fi

echo "Archiving Dropbox directories ..."
tar -cjf $FILE $DIRS
echo "Done!"
