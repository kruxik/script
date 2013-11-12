#!/bin/bash
# push-log-verify.sh

# help usage
usage()
{
	cat << EOF
	usage: $0 [OPTIONS] PUSH_AGENT_LOG PUSH_CLIENTJS_LOG

	This script analyzes Apache access log.

	OPTIONS:
	  -h		Show help/usage
	  -d		Date analysis (time difference)
	  -m	MASK	Mask to compare (default 'fs3_u_1_1')
	  -v		Verbose
EOF
}

VERBOSE=0
PID=$$
MASK='fs3_u_1_1'
DATE_ANALYSIS=0

# parse option arguments
while getopts "dm:v" OPTION
do
	case $OPTION in
	d)
		DATE_ANALYSIS=1
		;;
	m)
		MASK="$OPTARG"
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

AGENT_LOG=$1
TMP_AGENT_LOG="/tmp/tmp_agent.log-$PID"
CLIENT_LOG=$2
TMP_CLIENT_LOG="/tmp/tmp_client.log-$PID"
CLIENT_LOG_FIRST_DATE=""
CLIENT_LOG_FIRST_STRING=""
CLIENT_LOG_LAST_DATE=""
CLIENT_LOG_LAST_STRING=""
AGENT_LOG_FIRST_LINE=""
AGENT_LOG_LAST_LINE=""
AGENT_POSITION=1
CLIENT_POSITION=1
CLIENT_HOST=""
CLIENT_HOST_CHANGE=0
STR_AGENT=0
STR_CLIENT=0
STR_CLIENT_HOST=""

if [ "$AGENT_LOG" = "" ]; then
	echo "No Push Agent log specified! Please provide Agent log first."
	usage
	exit 1
fi

if [ "$CLIENT_LOG" = "" ]; then
	echo "No Client log specified! Please provide Client log first."
	usage
	exit 1
fi

if [ ! -f $AGENT_LOG ]; then
	echo "Provided Push Agent log '$AGENT_LOG' doesn't exist!"
	exit 1
fi

if [ ! -f $CLIENT_LOG ]; then
	echo "Provided Client log '$CLIENT_LOG' doesn't exist!"
	exit 1
fi

CLIENT_LOG_FIRST_STRING=`grep -m1 $MASK $CLIENT_LOG`
CLIENT_LOG_FIRST_DATE=`echo $CLIENT_LOG_FIRST_STRING | cut -c -10`
CLIENT_LOG_FIRST_DATE=`date -d @$CLIENT_LOG_FIRST_DATE +"%Y-%m-%d, %H:%M"`
CLIENT_LOG_FIRST_STRING=`echo $CLIENT_LOG_FIRST_STRING | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`
CLIENT_LOG_FIRST_STRING="$CLIENT_LOG_FIRST_DATE.*$CLIENT_LOG_FIRST_STRING"

#CLIENT_LOG_LAST_STRING=`tac $CLIENT_LOG | grep -m1 $MASK | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`
CLIENT_LOG_LAST_STRING=`tac $CLIENT_LOG | grep -m1 $MASK`
CLIENT_LOG_LAST_DATE=`echo $CLIENT_LOG_LAST_STRING | cut -c -10`
CLIENT_LOG_LAST_DATE=`date -d @$CLIENT_LOG_LAST_DATE +"%Y-%m-%d, %H:%M"`
CLIENT_LOG_LAST_STRING=`echo $CLIENT_LOG_LAST_STRING | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`
CLIENT_LOG_LAST_STRING="$CLIENT_LOG_LAST_DATE.*$CLIENT_LOG_LAST_STRING"

if [ $VERBOSE -eq 1 ]; then
	echo "Mask:                 '$MASK'"
	echo "Agent log:            '$AGENT_LOG'"
	echo "Client log:           '$CLIENT_LOG'"
	echo "Client first string:  '$CLIENT_LOG_FIRST_STRING'"
	echo "Client last string:   '$CLIENT_LOG_LAST_STRING'"
fi

if [ "$CLIENT_LOG_FIRST_STRING" = "" ]; then
	echo "No data found according to mask '$MASK'"
	exit 1
fi

grep $MASK $AGENT_LOG > $TMP_AGENT_LOG

AGENT_LOG_FIRST_LINE=`grep -m1 -n "$CLIENT_LOG_FIRST_STRING" $TMP_AGENT_LOG | cut -d':' -f1`
AGENT_LOG_LAST_LINE=`grep -m1 -n "$CLIENT_LOG_LAST_STRING" $TMP_AGENT_LOG | cut -d':' -f1`

if [ $VERBOSE -eq 1 ]; then
	echo "Tmp Agent first line: '$AGENT_LOG_FIRST_LINE'"
	echo "Tmp Agent last line:  '$AGENT_LOG_LAST_LINE'"
fi

if [ "$AGENT_LOG_FIRST_LINE" = "" ] || [ "$AGENT_LOG_LAST_LINE" = "" ] || [ $AGENT_LOG_FIRST_LINE -gt $AGENT_LOG_LAST_LINE ]; then
	echo "Interval strings not found in agent log. Please enable verbose mode to see more info."
	exit 1
fi

if [ $VERBOSE -eq 1 ]; then echo "Creating temporary agent log file '$TMP_AGENT_LOG' ..."; fi
awk "NR>=$AGENT_LOG_FIRST_LINE&&NR<=$AGENT_LOG_LAST_LINE" $TMP_AGENT_LOG > $TMP_AGENT_LOG.2
mv $TMP_AGENT_LOG.2 $TMP_AGENT_LOG

if [ ! -f $TMP_AGENT_LOG ]; then
	echo "Temporary agent log was not created."
	exit 1
fi

if [ $VERBOSE -eq 1 ]; then echo "Creating temporary client log file '$TMP_CLIENT_LOG' ..."; fi
grep $MASK $CLIENT_LOG > $TMP_CLIENT_LOG

if [ $VERBOSE -eq 1 ]; then echo "Analyzing logs ..."; fi

while [ 1 ]; do
	CLIENT_HOST_CHANGE=0
	STR_AGENT_BAK=`tail -n +$AGENT_POSITION $TMP_AGENT_LOG | head -n1`
	if [ "$STR_AGENT_BAK" = "" ]; then break; fi

	STR_AGENT=`echo $STR_AGENT_BAK | awk -F"DATA=" '{print $2}' | awk -F", " '{print $1}' | awk -F"}]" '{print $1}'`

	if [ $DATE_ANALYSIS -eq 1 ]; then
		STR_CLIENT=`tail -n +$CLIENT_POSITION $TMP_CLIENT_LOG | head -n1`
		STR_CLIENT_HOST=`echo $STR_CLIENT | awk '{print $NF}' | cut -d'[' -f2 | cut -d']' -f1`

		DATE_CLIENT=`echo $STR_CLIENT | cut -d ' ' -f1 | cut -c -10`
		STR_CLIENT=`echo $STR_CLIENT | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`

		DATE_AGENT=`echo $STR_AGENT_BAK | cut -c -21 | cut -c 2- | awk -F', ' '{print $1,$2}'`
		DATE_AGENT=`date -d"$DATE_AGENT" +%s`

		echo "$((DATE_CLIENT-DATE_AGENT)): $STR_AGENT"
	else
		STR_CLIENT=`tail -n +$CLIENT_POSITION $TMP_CLIENT_LOG | head -n1`
		STR_CLIENT_HOST=`echo $STR_CLIENT | awk '{print $NF}' | cut -d'[' -f2 | cut -d']' -f1`
		STR_CLIENT=`echo $STR_CLIENT | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`
	fi

	if [ "$CLIENT_HOST" = "" ]; then
		CLIENT_HOST=$STR_CLIENT_HOST
	fi

	if [ "$CLIENT_HOST" != "$STR_CLIENT_HOST" ]; then
		echo "Hostname change from $CLIENT_HOST to $STR_CLIENT_HOST"
		CLIENT_HOST=$STR_CLIENT_HOST
		CLIENT_HOST_CHANGE=1
	fi

	if [ $VERBOSE -eq 1 ]; then echo -ne "Position $AGENT_POSITION-$CLIENT_POSITION: '$STR_AGENT'-'$STR_CLIENT', status: "; fi

	if [ "$STR_AGENT" != "$STR_CLIENT" ]; then
		# agent switch - check
		if [ $CLIENT_HOST_CHANGE -eq 1 ]; then
			CLIENT_POSITION=$((CLIENT_POSITION+1))
			if [ $DATE_ANALYSIS -eq 1 ]; then
				STR_CLIENT=`tail -n +$CLIENT_POSITION $TMP_CLIENT_LOG | head -n1`

				DATE_CLIENT=`echo $STR_CLIENT | cut -d ' ' -f1 | cut -c -10`
				STR_CLIENT=`echo $STR_CLIENT | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`
			else
				STR_CLIENT=`tail -n +$CLIENT_POSITION $TMP_CLIENT_LOG | head -n1 | cut -d' ' -f3 | cut -d'[' -f2 | cut -d']' -f1`
			fi
		fi

		if [ "$STR_AGENT" != "$STR_CLIENT" ]; then
			echo "Missing: '$STR_AGENT_BAK' at agent position: $AGENT_POSITION"
			if [ $VERBOSE -eq 1 ]; then echo -ne "MISS\n"; fi
		else
			CLIENT_POSITION=$((CLIENT_POSITION+1))
			if [ $VERBOSE -eq 1 ]; then echo -ne "HIT\n"; fi
		fi
	else
		CLIENT_POSITION=$((CLIENT_POSITION+1))
		if [ $VERBOSE -eq 1 ]; then echo -ne "HIT\n"; fi
	fi

	AGENT_POSITION=$((AGENT_POSITION+1))
done

rm -f $TMP_AGENT_LOG
rm -f $TMP_CLIENT_LOG

if [ $VERBOSE -eq 1 ]; then echo "Done!"; fi
