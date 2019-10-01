#!/bin/bash

#Command line args
PPS=$1
PID=$2
IFACE=$3
SAMPLE_RATE=$4
if [ -z "$4" ]; then
	echo "Usage: bash $0 <test pps rate> <suricata pid> <capture interface> <sample rate in seconds>"
	echo "ex: bash $0 100000 8912 eth0 0.5"
	exit 1
fi

cd "$(dirname "$0")"
echo $$ > perfpid
tmp=$(mktemp -d)

echo "Temp folder at: $tmp"
echo "New run -- tx PPS: $PPS -- Sample rate: $4" >> gather_results.csv
echo "txpps,%cpu,%totalcpu,%mem,mem_MB,memavail,cpu_temp(c),cpu_power(w),rxpps,rxmbps,iface_drop,kern_drop,loop_time" >> gather_results.csv

#top has to be kept running to gather accurate CPU stats over time. See man page for how it calcs this. ps doesnt provide usefull data, see man page as well
top -p $PID -b -d 1 > /$tmp/tmp &

#Initialize vars
KERN_DROP_LAST=0
IFACE_DROP_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors)
RX_PKTS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
RX_BPS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TIMEFORMAT=%R
LOOP_COUNT=0
LOOP_TIME_REAL=$SAMPLE_RATE

declare -a PCPU
declare -a TOTAL_CPU
declare -a CPUTEMP
declare -a CPUPOWER
declare -a PMEM
declare -a RXPPS
declare -a RXBPS
declare -a MEM_MB
declare -a MEM_AVAIL
declare -a IFACE_DROPS
declare -a KERN_DROPS

function captureLap {
	#Time dependant ("per second") samples below.
	RX_PKTS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
	RXPPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($RX_PKTS_NOW - $RX_PKTS_LAST) / ($LOOP_TIME_REAL)")
	RX_PKTS_LAST=$RX_PKTS_NOW
	RX_BPS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
	RXBPS[$LOOP_COUNT]=$(bc <<< "scale=0; (($RX_BPS_NOW - $RX_BPS_LAST) / 125000) / ($LOOP_TIME_REAL) ")
	RX_BPS_LAST=$RX_BPS_NOW

	#Specific to suricata...
	KERN_DROP_NOW=$(suricatasc /var/run/suricata-command.socket -c "iface-stat eth0" | awk '{ print $5 }'| egrep -o [0-9]+)
	KERN_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($KERN_DROP_NOW - $KERN_DROP_LAST) / $LOOP_TIME_REAL  ")
	KERN_DROP_LAST=$KERN_DROP_NOW

	#Might be specific to this NIC driver. e1000e
	IFACE_DROP_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors)
	IFACE_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($IFACE_DROP_NOW-$IFACE_DROP_LAST) / $LOOP_TIME_REAL  ")
  IFACE_DROP_LAST=$IFACE_DROP_NOW

	#Regular sensors / reports
	PMEM[$LOOP_COUNT]=$(ps -p $PID -o pmem --no-headers)
	MEM_MB[$LOOP_COUNT]=$(bc <<< 'scale=0; '$(ps -p $PID -o rss --no-headers)' / 976.562' )
	MEM_AVAIL[$LOOP_COUNT]=$(bc <<< 'scale=0; '$(tail -5 /$tmp/tmp | head -n 1 | awk '{ print $6 + $10 }')' / 976.562' )
	PCPU[$LOOP_COUNT]=$(tail -1 /$tmp/tmp | awk '{ print $9 }')
	TOTAL_CPU[$LOOP_COUNT]=$(tail -6 /$tmp/tmp | head -n 1 | awk '{ print $2 }')
	CPUTEMP[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone1/temp)' / 1000') #specific to TX1...
	CPUPOWER[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/devices/7000c400.i2c/i2c-1/1-0040/iio_device/in_power0_input)' / 1000') #specific to TX1...other sensors here as well

	#echo txPPS\: $PPS - \%CPU\: ${PCPU[$LOOP_COUNT]} - TOTAL CPU\: ${TOTAL_CPU[$LOOP_COUNT]} - \%MEM\: ${PMEM[$LOOP_COUNT]} - MEM MB\: ${MEM_MB[$LOOP_COUNT]} - \
	#MB FREE\: ${MEM_AVAIL[$LOOP_COUNT]} - CPUTEMP\(C\)\: ${CPUTEMP[$LOOP_COUNT]} - CPU POWER\(W\)\: ${CPUPOWER[$LOOP_COUNT]} - rxPPS\: ${RXPPS[$LOOP_COUNT]} - rxmbps\: ${RXBPS[$LOOP_COUNT]} - iface drps\: ${IFACE_DROPS[$LOOP_COUNT]}, krn drps\: ${KERN_DROPS[$LOOP_COUNT]}, loop\: $LOOP_TIME_REAL
	echo $PPS,${PCPU[$LOOP_COUNT]},${TOTAL_CPU[$LOOP_COUNT]},${PMEM[$LOOP_COUNT]},${MEM_MB[$LOOP_COUNT]},${MEM_AVAIL[$LOOP_COUNT]},${CPUTEMP[$LOOP_COUNT]},${CPUPOWER[$LOOP_COUNT]},${RXPPS[$LOOP_COUNT]},${RXBPS[$LOOP_COUNT]},${IFACE_DROPS[$LOOP_COUNT]},${KERN_DROPS[$LOOP_COUNT]},$LOOP_TIME_REAL>> gather_results.csv

	(( LOOP_COUNT=LOOP_COUNT+1 ))
}

function buildFinalStats {

	#Moved out of critial loop region
	IFS=$'\n'
	MAX_PCPU=$(echo "${PCPU[*]}" | sort -nr | head -n1)
	MAX_TOTAL_CPU=$(echo "${TOTAL_CPU[*]}" | sort -nr | head -1)
	MAX_PMEM=$(echo "${PMEM[*]}" | sort -nr | head -1)
	MAX_MEM_MB=$(echo "${MEM_MB[*]}" | sort -nr | head -1)
	MIN_MEM_AVAIL=$(echo "${MEM_AVAIL[*]}" | sort -nr | tail -1)
	MAX_CPUTEMP=$(echo "${CPUTEMP[*]}" | sort -nr | head -1)
	MAX_CPUPOWER=$(echo "${CPUPOWER[*]}" | sort -nr | head -1)
	MAX_RXBPS=$(echo "${RXBPS[*]}" | sort -nr | head -1)
	MAX_RXPPS=$(echo "${RXPPS[*]}" | sort -nr | head -1)

	#Averages. Have to count the number of zeros in the array so they dont get counted
	#( All items in array / (Array size - zero count) )
	IFS='+'
	SUM_IFACE_DROPS=$(echo "${IFACE_DROPS[*]}"|bc)
	SUM_KERN_DROPS=$(echo "${KERN_DROPS[*]}"|bc)
	AVG_IFACE_DROPS=$(echo "(${IFACE_DROPS[*]}) / (${#IFACE_DROPS[*]} - $(echo ${IFACE_DROPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_KERN_DROPS=$(echo "(${KERN_DROPS[*]}) / (${#KERN_DROPS[*]} - $(echo ${KERN_DROPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_RXPPS=$(echo "(${RXPPS[*]}) / (${#RXPPS[*]} - $(echo ${RXPPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_RXBPS=$(echo "(${RXBPS[*]}) / (${#RXBPS[*]} - $(echo ${RXBPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_PMEM=$(echo "scale=1; (${PMEM[*]}) / (${#PMEM[*]} - $(echo ${PMEM[*]} | grep -ow '0.0' | wc -l))"|bc)
	AVG_PCPU=$(echo "scale=1; (${PCPU[*]}) / (${#PCPU[*]} - $(echo ${PCPU[*]} | grep -ow '0.0' | wc -l))"|bc)
	AVG_CPUPOWER=$(echo "scale=3; (${CPUPOWER[*]}) / (${#CPUPOWER[*]} - $(echo ${CPUPOWER[*]} | grep -ow '0' | wc -l))"|bc)
	AVG_CPUTEMP=$(echo "scale=1; (${CPUTEMP[*]}) / (${#CPUTEMP[*]} - $(echo ${CPUTEMP[*]} | grep -ow '0.0' | wc -l))"|bc)
	AVG_TOTAL_CPU=$(echo "scale=1; (${TOTAL_CPU[*]}) / (${#TOTAL_CPU[*]} - $(echo ${TOTAL_CPU[*]} | grep -ow '0.0' | wc -l))"|bc)
	unset IFS

}

function finish {
	echo "Music is playing, wrap it up"
	rm -rf "$tmp"
	rm -rf perfpid
	killall top 2> /dev/null
	buildFinalStats

	if [ ! -f gather_totals.csv ]; then
		echo "txpps,%pcpu.µ,%pcpu.max,%tcpu.µ,%tcpu.max,%mem.µ,%mem.max,memMB.max,memfree.min,temp.µ,temp.max,power.µ,power.max,rxpps.µ,rxpps.max,rxmbps.µ,rxmbps.max,nicdrop.sum,nicdrop.µ,kerndrop.sum,kerndrop.µ,samprate" >> gather_totals.csv
	fi

	#handle some zero cases
	if [ -z "$AVG_IFACE_DROPS" ]; then AVG_IFACE_DROPS=0; fi
	if [ -z "$AVG_KERN_DROPS" ]; then AVG_KERN_DROPS=0; fi
	if [ -z "$AVG_RXBPS" ]; then AVG_RXBPS=0; fi
	if [ -z "$AVG_RXPPS" ]; then AVG_RXPPS=0; fi

	echo $PPS,$AVG_PCPU,$MAX_PCPU,$AVG_TOTAL_CPU,$MAX_TOTAL_CPU,$AVG_PMEM,$MAX_PMEM,$MAX_MEM_MB,$MIN_MEM_AVAIL,$AVG_CPUTEMP,$MAX_CPUTEMP,$AVG_CPUPOWER,$MAX_CPUPOWER,$AVG_RXPPS,$MAX_RXPPS,$AVG_RXBPS,$MAX_RXBPS,$SUM_IFACE_DROPS,$AVG_IFACE_DROPS,$SUM_KERN_DROPS,$AVG_KERN_DROPS,$SAMPLE_RATE >> gather_totals.csv
	column -t -s , gather_totals.csv
	exec 3>&1- 4>&2-
	exit 0
}

sleep 2 #brief warmup
##"main" function below
trap finish EXIT #Capture ctrl-c or kill signals so I can cleanup
exec 3>&1 4>&2 #bash magic to get the output of the time command and save the functions stdout/stderr
while :
do
		#This needs to be as close as possible to SAMPLE_RATE sec for "per second" calculations to be accurate
		#As system load nears 100% the loop will likely drift, so try to account for it.
		#Still not perfect, but close enough.
		{ time { sleep $SAMPLE_RATE & captureLap 1>&3 2>&4; wait $!; }  } 2>"/$tmp/lastloop"
		LOOP_TIME_REAL=$(cat /$tmp/lastloop)

done
