#!/bin/bash
# httpd-analyze.sh

# help usage
usage()
{
	cat << EOF
	usage: $0 [OPTIONS] APACHE_ACCESS_LOG

	This script analyzes Apache access log.

	OPTIONS:
	  -h		Show help/usage
	  -a		Print all found HTTP status codes
	  -c		Count by request and sort (Default)
	  -f	REGEX	Filter input by given REGEX
	  -n		Count by hostname (nodes)
	  -o		Filter only in request part
	  -r		Reverse sorting
	  -s	STATUS	Filter by HTTP status code
	  -t		Sort by time
	  -v		Verbose
EOF
}

VERBOSE=0
COUNT=1
REQUESTTIME=0
REVERSE=" "
FILTER=""
FILTER_ONLY_REQUEST=0
HTTPSTATUS=""
HTTPSTATUS_PARAMS=""
ALL_HTTPSTATUS=0
HOSTNAMECOUNT=0

# parse option arguments
while getopts "achnortf:s:v" OPTION
do
	case $OPTION in
	a)
		ALL_HTTPSTATUS=1
		COUNT=0
		;;
	f)
		FILTER="$OPTARG"
		;;
	c)
		COUNT=1
		;;
	n)
		COUNT=0
		HOSTNAMECOUNT=1
		;;
	o)
		FILTER_ONLY_REQUEST=1
		;;
	r)
		REVERSE=" -r "
		;;
	s)
		HTTPSTATUS=$OPTARG
		;;
	t)
		REQUESTTIME=1
		COUNT=0
		;;
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

if [ "$FILE" = "" ]; then
	echo "No Apache log specified! Please provide Apache access log first."
	usage
	exit 1
fi

if [ ! -f $FILE ]; then
	echo "Specified Apache log '$FILE' not found!"
	exit 1
fi

if [ $VERBOSE -eq 1 ]; then echo -n "(i) Detecting request column ... "; fi
LINE=`head -n1 $FILE`
COLUMN_INDEX=0
for COLUMN in $LINE; do
	if [ `echo $COLUMN | grep "HTTP\/1"` ]; then break; fi
	COLUMN_INDEX=$((COLUMN_INDEX + 1))
done
if [ $VERBOSE -eq 1 ]; then echo "$COLUMN_INDEX"; fi

if [ $VERBOSE -eq 1 ]; then echo -n "(i) Detecting time column ... "; fi
COLUMN=`head -n1 $FILE | awk '{print $NF}'`
if [ "$COLUMN" = "hit" ] || [ "$COLUMN" = "miss" ]; then
	TIME_COLUMN=-1
else
	TIME_COLUMN=0
fi
if [ $VERBOSE -eq 1 ]; then echo "$TIME_COLUMN"; fi

if [ "$HTTPSTATUS" != "" ]; then
	HTTPSTATUS_PARAMS="HTTP/1\..\" $HTTPSTATUS"
fi

if [ "$FILTER" = "" ]; then
	FILTER_BIN="cat $FILE"
else
	if [ $FILTER_ONLY_REQUEST -eq 1 ]; then
		FILTER_BIN="awk '{print \$$COLUMN_INDEX,\$0}' $FILE | grep \"^[^ ]*$FILTER[^ ]*\" | awk '{first = \"\$1 \"; \$1 = \"\"; print \$0}' | cut -c 1 --complement"
	else
		FILTER_BIN="grep \"$FILTER\" $FILE"
	fi
fi

if [ "$HTTPSTATUS_PARAMS" != "" ]; then
	FILTER_BIN="$FILTER_BIN | grep \"HTTP/1\....$HTTPSTATUS \""
fi

# output by request count
if [ $COUNT -eq 1 ]; then
	if [ $VERBOSE -eq 1 ]; then echo "(i) Output by request count ..."; fi
	eval $FILTER_BIN | awk -v i=$COLUMN_INDEX '{print $i}' | sort | uniq -c | sort -n $REVERSE
	exit 0
fi

# output by request time
if [ $REQUESTTIME -eq 1 ]; then
	if [ $VERBOSE -eq 1 ]; then echo "(i) Output by request time ..."; fi

	if [ $TIME_COLUMN -eq 0 ]; then
		FILTER_BIN="$FILTER_BIN | awk '{print \$NF,\$$COLUMN_INDEX}' | awk -F/ '{print \$2,\$0}' | awk '{print \$1,\$3}'"
	else
		FILTER_BIN="$FILTER_BIN | awk '{print \$(NF-1),\$$COLUMN_INDEX}'"
	fi

	eval $FILTER_BIN | sort -n $REVERSE
	exit 0
fi

# output all http status codes
if [ $ALL_HTTPSTATUS -eq 1 ]; then
	if [ $VERBOSE -eq 1 ]; then echo "(i) Output by HTTP status codes ..."; fi
	MY_INDEX=$((COLUMN_INDEX + 2))
	eval $FILTER_BIN | awk -v i=$MY_INDEX '{print $i}' | egrep "^[0-9]{3}$" | sort -n | uniq -c
	exit 0
fi

if [ $HOSTNAMECOUNT -eq 1 ]; then
	if [ $VERBOSE -eq 1 ]; then echo "(i) Output by hostname count ..."; fi
	eval $FILTER_BIN | awk '{print $1}' | sort | uniq -c | sort -n $REVERSE
	exit 0
fi

