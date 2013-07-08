#/bin/bash

if [ "$1" == "" ] || [ ! -d $1 ]; then
	echo "Please provide source directory"
	exit 1
fi

if [ "$2" == "" ] || [ ! -d $2 ]; then
	echo "Please provide destination directory"
	exit 1
fi

SOURCE=$1
DESTINATION=$2

echo "Syncing '$SOURCE' to '$DESTINATION' ..."
rsync -vur $SOURCE/ $DESTINATION/
echo "Done!"
