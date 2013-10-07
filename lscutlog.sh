#!/bin/bash
# lscutlog.sh

# help usage
usage()
{
	cat << EOF
	usage: $0 [OPTIONS] LOG_FILE [FROM] [TO]

	This script cuts a log fragment from a log file according to FROM .. TO times
	IF FROM and/or TO is not specified the starting and ending time of the log is printed instead.

	Input format of the FROM/TO attribute is as follows:

		YYYY-MM-DD HH:MM:SS

	OPTIONS:
	  -h		Show help/usage
	  -v		Verbose
EOF
}

LOG_TYPE=""
VERBOSE=0
START_POS=""
END_POS=""

# parse option arguments
while getopts "v" OPTION
do
	case $OPTION in
	v)
		VERBOSE=1
		;;
	?)
		usage
		exit 1
		;;
	esac

done

# decrease argument pointer so it points to first non-option argument
shift $(($OPTIND - 1))

FILE=$1
FROM=$2
TO=$3

if [ "$FILE" = "" ]; then
	echo "No log specified! Please provide a log file first." >&2
	usage
	exit 1
fi

if [ ! -f $FILE ]; then
	echo "Specified log '$FILE' not found!" >&2
	exit 1
fi

if [ `egrep -m1 -oh "[0-9]{2}/[a-zA-Z]{3}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2}" $FILE` ]; then
	LOG_TYPE="apache"
	FROM_INDEX=`date -d "$FROM" "+%d/%b/%Y:%H:%M:%S"`
	TO_INDEX=`date -d "$TO" "+%d/%b/%Y:%H:%M:%S"`
elif [ `grep -m1 -oh "SET timestamp=" $FILE | cut -d ' ' -f1` ]; then
	LOG_TYPE="mysql"
	FROM_INDEX=`date -d "$FROM" "+%s"`
	TO_INDEX=`date -d "$TO" "+%s"`
fi

if [ "$LOG_TYPE" = "" ]; then
	echo "Sorry, unknown type of a log file - not supported." >&2
	exit 1
fi

if [ "$FROM" = "" ] || [ "$TO" = "" ]; then
	FROM=0
	TO=0

	if [ "$LOG_TYPE" = "apache" ]; then
		FROM=`egrep -m1 -oh "[0-9]{2}/[a-zA-Z]{3}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2}" $FILE`
		TO=`tac $FILE | egrep -m1 -oh "[0-9]{2}/[a-zA-Z]{3}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2}"`
	elif [ "$LOG_TYPE" = "mysql" ]; then
		FROM=`grep -m1 "SET timestamp=" $FILE | cut -d'=' -f2 | cut -d';' -f1`
		TO=`tac $FILE | grep -m1 "SET timestamp=" | cut -d'=' -f2 | cut -d';' -f1`
		FROM=`date -d @$FROM "+%Y-%m-%d %H:%M:%S"`
		TO=`date -d @$TO "+%Y-%m-%d %H:%M:%S"`
	fi

	echo "Start time of the log: $FROM"
	echo "End time of the log: $TO"

	exit 0
fi

if [ $VERBOSE -eq 1 ]; then
	echo " * Log file:    $FILE"
	echo " * Log type:    $LOG_TYPE"
	echo " * Start time:  $FROM"
	echo " * End time:    $TO"
fi

START_POS=`grep -m1 -n "$FROM_INDEX" $FILE | cut -d ':' -f1`
if [ "$START_POS" = "" ]; then
	echo "Start position '$FROM_INDEX' not found." >&2
	exit 1
fi

END_POS=`grep -m1 -n "$TO_INDEX" $FILE | cut -d ':' -f1`
if [ "$END_POS" = "" ]; then
	echo "END position '$TO_INDEX' not found." >&2
	exit 1
fi

if [ $VERBOSE -eq 1 ]; then
	echo " * Start pos:   $START_POS"
	echo " * End pos:     $END_POS"
fi

awk "NR>=$START_POS&&NR<=$END_POS" $FILE
