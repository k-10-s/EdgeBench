#!/bin/bash

#Command line args
PPS=$1
PID=$2
IFACE=$3
SAMPLE_RATE=$4
PACKETS_EXPECTED=$5
TUNING_FACTORS=$6


#TOTAL_RUNTIME=$(( $PACKETS_EXPECTED / $PPS + 5 )) #plus for cooldown buffer
#TOTAL_RUNTIME=60

if [ -z "$4" ]; then
	echo "Usage: bash $0 <test pps rate> <monitor pid> <capture interface> <sample rate in sec> optional: <packets expected> <tuning_factors>"
	echo "ex: bash $0 100000 8912 eth0 0.5 2000000 ABCD"
	echo "a negative pid will watch only the interface / softirq handler"
	echo "**sudo access required**"
	exit 1
elif [ -z "$5" ]; then
	TOTAL_RUNTIME=60 
	TUNING_FACTORS=N
elif [ -z "$6" ]; then
	TOTAL_RUNTIME=$(( $PACKETS_EXPECTED / $PPS + 5 )) #plus for cooldown buffer
	TUNING_FACTORS=N
elif [ -z "$7" ]; then
	TOTAL_RUNTIME=$(( $PACKETS_EXPECTED / $PPS + 5 )) #plus for cooldown buffer
fi


cd "$(dirname "$0")"
if [ -f gather.pid ]; then
	echo "Unclean shutdown of previous run. Ending it now.."
	sudo kill $(cat gather.pid)
	sleep 2
fi
echo $$ > gather.pid
tmp=$(mktemp -d)


if [ $PID -lt '0' ]; then
	echo "Using interface rate mode only";
	#Watching softirq daemon, that handles the last half of the interrupt from the NIC
	#Thread 0 is most likely on the ARM based boards (first thread)
	#kernel threads like this wont show memory stats
	PID=$(top -b -n1 | grep ksoftirq | head -1 | awk '{ print $1 }');
	PROCESS_NAME=ksoftirqd0;
elif [ ! -d /proc/$PID ]; then
	echo "supplied PID isn't running, exiting";
	exit 1;
else PROCESS_NAME=$(ps -p $PID -o comm=); fi

#Might be a better way to fingerprint the machine
if [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'Raspberry' ]; then DEVICE_FAM=pi;
elif [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'Jetson-TX1' ]; then DEVICE_FAM=nvidia-tx1;
elif [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'quill' ]; then DEVICE_FAM=nvidia-tx2;
elif [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'Jetson-AGX' ]; then DEVICE_FAM=nvidia-xavier;
else DEVICE_FAM=unknown; fi

#top has to be kept running to gather accurate CPU stats over time.
#See man page for how it calcs this. ps doesn't provide useful data, see man page as well
#debian buster has newer version of top that defaults to MB, we want KB
if [ $(lsb_release -c -s) == 'buster' ]; then
	top -p $PID -b -d 1 -E k > $tmp/toptmp &
	sleep 2
else
  top -p $PID -b -d 1 > $tmp/toptmp &

fi

#let top warmup..very important. rip my 3 hours troubleshooting this regression
sleep 3

sudo renice -n -15 $(pidof top) &> /dev/null #bump my top process priority
sudo renice -n -20 $$ &> /dev/null #bump my priority to max

#Initialize vars
declare -a PID_CPU_PERCENT
declare -a PID_MEM_PERCENT
declare -a PID_MEM_MB
declare -a UTILIZATION_CPU
declare -a TEMPERATURE_CPU
declare -a POWER_CPU
declare -a MEM_AVAIL_PERCENT
declare -a MEM_AVAIL_MB
declare -a RXPPS
declare -a RXBPS
declare -a IFACE_DROPS
declare -a KERN_DROPS

NIC_DRIVER=$(ethtool -i $IFACE | head -1 | awk '{ print $2 }')
TOTAL_MEM_MB=$(bc <<< 'scale=2; '$(tail -5 $tmp/toptmp | head -n 1 | awk '{ print $4 }')' / 976.562')
RX_PKTS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
RX_PKTS_FIRST=$RX_PKTS_LAST
RX_BPS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TIMEFORMAT=%R
LOOP_COUNT=0
LOOP_TIME_REAL=$SAMPLE_RATE
IFACE_DROPS_PERCENT=0
KERN_DROPS_PERCENT=0
#SUM_PACKETS=0

KERN_DROP_LAST=0
if [ "$NIC_DRIVER" == 'e1000e' ] || [ "$NIC_DRIVER" == 'igb' ] || [ "$NIC_DRIVER" == 'tg3' ] ||  [ "$NIC_DRIVER" == 'bcmgenet' ] ; then
	IFACE_DROP_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors);
elif [ "$NIC_DRIVER" == 'lan78xx' ]; then
	IFACE_DROP_LAST=$(ethtool -S $IFACE | grep "RX Dropped Frames:" | awk '{ print $4 }');
elif [ "$NIC_DRIVER" == 'eqos' ]; then
	IFACE_DROP_LAST=$(ethtool -S $IFACE | grep rx_fifo_overflow | awk '{ print $2 }');
fi

function captureLap {
	#Time dependant ("per second") samples below.
	RX_PKTS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
	RXPPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($RX_PKTS_NOW - $RX_PKTS_LAST) / ($LOOP_TIME_REAL)")
	RX_PKTS_LAST=$RX_PKTS_NOW
	RX_BPS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
	RXBPS[$LOOP_COUNT]=$(bc <<< "scale=0; (($RX_BPS_NOW - $RX_BPS_LAST) / 125000) / ($LOOP_TIME_REAL) ")
	RX_BPS_LAST=$RX_BPS_NOW

	#Handle bizzare rare case where a negative number gets calculated on super heavily loaded machine
	#Happens on Pi based boards, the interface seems to temporarily "reset" its stats counters?
	if [ ${RXBPS[$LOOP_COUNT]} -lt "0" ]; then RXBPS[$LOOP_COUNT]=0; fi
	if [ ${RXPPS[$LOOP_COUNT]} -lt "0" ]; then RXPPS[$LOOP_COUNT]=0; fi

	#Specific to suricata...
	if [ "$PROCESS_NAME" == "Suricata-Main" ]; then
		KERN_DROP_NOW=$(suricatasc /var/run/suricata-command.socket -c "iface-stat $IFACE" | awk '{ print $5 }'| egrep -o [0-9]+)
		KERN_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($KERN_DROP_NOW - $KERN_DROP_LAST) / $LOOP_TIME_REAL  ")
		KERN_DROP_LAST=$KERN_DROP_NOW
	else
		KERN_DROPS[$LOOP_COUNT]=NA
	fi

	#Driver specific stat locations
	if [ "$NIC_DRIVER" == 'lan78xx' ]; then
		IFACE_DROP_NOW=$(ethtool -S $IFACE | grep "RX Dropped Frames:" | awk '{print $4}')
		IFACE_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($IFACE_DROP_NOW-$IFACE_DROP_LAST) / $LOOP_TIME_REAL  ")
		IFACE_DROP_LAST=$IFACE_DROP_NOW
	elif [ "$NIC_DRIVER" == 'e1000e' ] || [ "$NIC_DRIVER" == 'igb' ] || [ "$NIC_DRIVER" == 'tg3' ] || [ "$NIC_DRIVER" == 'bcmgenet' ]; then
		IFACE_DROP_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors)
		IFACE_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($IFACE_DROP_NOW-$IFACE_DROP_LAST) / $LOOP_TIME_REAL  ")
		IFACE_DROP_LAST=$IFACE_DROP_NOW
	elif [ "$NIC_DRIVER" == 'eqos' ]; then
		IFACE_DROP_NOW=$(ethtool -S $IFACE | grep rx_fifo_overflow | awk '{ print $2 }');
		IFACE_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($IFACE_DROP_NOW-$IFACE_DROP_LAST) / $LOOP_TIME_REAL  ")
		IFACE_DROP_LAST=$IFACE_DROP_NOW
	fi

	#Device specific sensors, not super efficient
	if [ "$DEVICE_FAM" == 'pi' ]; then
		TEMPERATURE_CPU[$LOOP_COUNT]=$(vcgencmd measure_temp | grep -ow "[0-9][0-9].[0-9]")
		POWER_CPU[$LOOP_COUNT]=$(expr $(vcgencmd measure_clock arm | grep -oP "([0-9]+)" | tail -1) / 1000000)
	elif [ "$DEVICE_FAM" == 'nvidia-tx1' ]; then
		TEMPERATURE_CPU[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone1/temp)' / 1000')
		POWER_CPU[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/devices/7000c400.i2c/i2c-1/1-0040/iio_device/in_power0_input)' / 1000')
	elif [ "$DEVICE_FAM" == 'nvidia-tx2' ]; then
		TEMPERATURE_CPU[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone1/temp)' / 1000')
		POWER_CPU[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/bus/i2c/drivers/ina3221x/0-0041/iio_device/in_power0_input)' / 1000')
	elif [ "$DEVICE_FAM" == 'nvidia-xavier' ]; then
		TEMPERATURE_CPU[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone0/temp)' / 1000')
		POWER_CPU[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/bus/i2c/drivers/ina3221x/1-0040/iio_device/in_power1_input)' / 1000')
	else
		TEMPERATURE_CPU[$LOOP_COUNT]=NA
		POWER_CPU[$LOOP_COUNT]=NA
	fi

	#Regular sensors / reports
	PID_MEM_PERCENT[$LOOP_COUNT]=$(ps -p $PID -o pmem --no-headers)
	PID_MEM_MB[$LOOP_COUNT]=$(bc <<< 'scale=0; '$(ps -p $PID -o rss --no-headers)' / 976.562' )
	PID_CPU_PERCENT[$LOOP_COUNT]=$(tail -1 $tmp/toptmp | awk '{ print $9 }')
	MEM_AVAIL_MB[$LOOP_COUNT]=$(bc <<< 'scale=0; '$(tail -5 $tmp/toptmp | head -n 1 | awk '{ print $6 + $10 }')' / 976.562' )
	MEM_AVAIL_PERCENT[$LOOP_COUNT]=$(bc <<< "scale=1; ${MEM_AVAIL_MB[$LOOP_COUNT]} / $TOTAL_MEM_MB * 100" )
	UTILIZATION_CPU[$LOOP_COUNT]=$(tail -6 $tmp/toptmp | head -n 1 | awk '{ print $2 + $4 + $6 + $10 + $12 + $14  }')


	# uncomment for live debugging
	#	echo txPPS\: $PPS - \%CPU\: ${PID_CPU_PERCENT[$LOOP_COUNT]} - TOTAL CPU\: ${UTILIZATION_CPU[$LOOP_COUNT]} - \%MEM\: ${PID_MEM_PERCENT[$LOOP_COUNT]} - MEM MB\: ${PID_MEM_MB[$LOOP_COUNT]} - \
	#	MB FREE\: ${MEM_AVAIL_MB[$LOOP_COUNT]} - TEMPERATURE_CPU\(C\)\: ${TEMPERATURE_CPU[$LOOP_COUNT]} - CPU POWER\: ${POWER_CPU[$LOOP_COUNT]} - rxPPS\: ${RXPPS[$LOOP_COUNT]} - \
	#rxmbps\: ${RXBPS[$LOOP_COUNT]} - iface drps\: ${IFACE_DROPS[$LOOP_COUNT]}, krn drps\: ${KERN_DROPS[$LOOP_COUNT]}, loop\: $LOOP_TIME_REAL

	(( LOOP_COUNT=LOOP_COUNT+1 ))
}

function buildFinalStats {

	#Moved out of critial loop region
	IFS=$'\n'
	MAX_PID_CPU_PERCENT=$(echo "${PID_CPU_PERCENT[*]}" | sort -nr | head -n1)
	MAX_PID_MEM_PERCENT=$(echo "${PID_MEM_PERCENT[*]}" | sort -nr | head -1)
	MAX_PID_MEM_MB=$(echo "${PID_MEM_MB[*]}" | sort -nr | head -1)
	MAX_UTILIZATION_CPU=$(echo "${UTILIZATION_CPU[*]}" | sort -nr | head -1)
	MIN_MEM_AVAIL_PERCENT=$(echo "${MEM_AVAIL_PERCENT[*]}" | sort -nr | tail -1)
	MIN_MEM_AVAIL_MB=$(echo "${MEM_AVAIL_MB[*]}" | sort -nr | tail -1)
	MAX_TEMPERATURE_CPU=$(echo "${TEMPERATURE_CPU[*]}" | sort -nr | head -1)
	MAX_POWER_CPU=$(echo "${POWER_CPU[*]}" | sort -nr | head -1)
	MAX_RXBPS=$(echo "${RXBPS[*]}" | sort -nr | head -1)
	MAX_RXPPS=$(echo "${RXPPS[*]}" | sort -nr | head -1)

	#Averages. Have to count the number of zeros in the array so they dont throw off averages
	#( All items in array / (Array size - zero count) )
	IFS='+'
	(( RX_PKTS_TOTAL=RX_PKTS_LAST-RX_PKTS_FIRST ))
	
	#currently only suricata gives access to real time kernel drops
	if [ "$PROCESS_NAME" == "Suricata-Main" ]; then
  	SUM_KERN_DROPS=$(echo "${KERN_DROPS[*]}"|bc)
		AVG_KERN_DROPS=$(echo "(${KERN_DROPS[*]}) / (${#KERN_DROPS[*]} - $(echo ${KERN_DROPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
		KERN_DROPS_PERCENT=$(bc <<< "scale=2; $SUM_KERN_DROPS / $RX_PKTS_TOTAL * 100")
	elif [ "$PROCESS_NAME" == "tcpdump" ]; then
		AVG_KERN_DROPS=NA
		SUM_KERN_DROPS=$(cat counters | awk ' FNR == 4 {print $1}')
		KERN_DROPS_PERCENT=$(bc <<< "scale=3; $SUM_KERN_DROPS / $RX_PKTS_TOTAL") #Percent dropped after making it past the first round...
		rm -rf counters
		rm -rf tcpdump.pid
	else
		AVG_KERN_DROPS=NA
		SUM_KERN_DROPS=NA
		KERN_DROPS_PERCENT=NA
	fi

	

	SUM_IFACE_DROPS=$(echo "${IFACE_DROPS[*]}"|bc)
	AVG_IFACE_DROPS=$(echo "(${IFACE_DROPS[*]}) / (${#IFACE_DROPS[*]} - $(echo ${IFACE_DROPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	IFACE_DROPS_PERCENT=$(bc <<< "scale=2; $SUM_IFACE_DROPS / $PACKETS_EXPECTED * 100")
	AVG_RXPPS=$(echo "(${RXPPS[*]}) / (${#RXPPS[*]} - $(echo ${RXPPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_RXBPS=$(echo "(${RXBPS[*]}) / (${#RXBPS[*]} - $(echo ${RXBPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_PID_MEM_PERCENT=$(echo "scale=1; (${PID_MEM_PERCENT[*]}) / (${#PID_MEM_PERCENT[*]} - $(echo ${PID_MEM_PERCENT[*]} | grep -ow '0.0' | wc -l))"|bc 2> /dev/null)
	AVG_PID_CPU_PERCENT=$(echo "scale=1; (${PID_CPU_PERCENT[*]}) / (${#PID_CPU_PERCENT[*]} - $(echo ${PID_CPU_PERCENT[*]} | grep -ow '0.0' | wc -l))"|bc 2> /dev/null)
	AVG_POWER_CPU=$(echo "scale=3; (${POWER_CPU[*]}) / (${#POWER_CPU[*]} - $(echo ${POWER_CPU[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_TEMPERATURE_CPU=$(echo "scale=1; (${TEMPERATURE_CPU[*]}) / (${#TEMPERATURE_CPU[*]} - $(echo ${TEMPERATURE_CPU[*]} | grep -ow '0.0' | wc -l))"|bc 2> /dev/null)
	AVG_UTILIZATION_CPU=$(echo "scale=1; (${UTILIZATION_CPU[*]}) / (${#UTILIZATION_CPU[*]} - $(echo ${UTILIZATION_CPU[*]} | grep -ow '0.0' | wc -l))"|bc 2> /dev/null)

	unset IFS
}

function printVerboseStats {

	echo "New run -- tx PPS: $PPS -- Sample rate: $4 -- Driver: $NIC_DRIVER -- tuning factors $TUNING_FACTORS" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results-verbose.csv
	echo "txpps,%pidcpu,%totalcpu,%pidmem,pidmemMB,memavailMB,%memavail,cpu_temp(c),cpu_power(w),rxpps,rxmbps,iface_drop,kern_drop" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results-verbose.csv

	for ((i = 0; i < $LOOP_COUNT; i++ )); do
		echo $PPS,${PID_CPU_PERCENT[$i]},${UTILIZATION_CPU[$i]},${PID_MEM_PERCENT[$i]},${PID_MEM_MB[$i]},${MEM_AVAIL_MB[$i]},${MEM_AVAIL_PERCENT[$i]},${TEMPERATURE_CPU[$i]},\
		${POWER_CPU[$i]},${RXPPS[$i]},${RXBPS[$i]},${IFACE_DROPS[$i]},${KERN_DROPS[$i]}>> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results-verbose.csv
	done
}

function finish {
	rm -rf "$tmp"
	rm -rf gather.pid

	killall top 2> /dev/null
	buildFinalStats
	printVerboseStats

	if [ ! -f $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv ]; then
		echo 'tx,pidcpu,pidcpu,syscpu,syscpu,pidmem,pidmem,pidmem,sysmemfree,sysmemfree,temp,temp,power,power,rxpps,rxpps,rxmbps,rxmbps,nicdrop,nicdrop,nicdrop,kerndrop,kerndrop,factors' >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv;
		echo 'pps,%avg,%max,%avg,%max,%avg,%max,MBmax,MBmin,%min,avg(c),max(c),avg,max,avg,max,avg,max,sum,avg,%,sum,avg,code' >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv;
	fi

	#handle some empty cases before writing to file
	if [ -z "$AVG_IFACE_DROPS" ]; then AVG_IFACE_DROPS=0; fi
	if [ -z "$AVG_KERN_DROPS" ]; then AVG_KERN_DROPS=0; fi
	if [ -z "$AVG_RXBPS" ]; then AVG_RXBPS=0; fi
	if [ -z "$AVG_RXPPS" ]; then AVG_RXPPS=0; fi
	if [ -z "$AVG_PID_CPU_PERCENT" ]; then AVG_PID_CPU_PERCENT=0.0; fi
	if [ -z "$AVG_PID_MEM_PERCENT" ]; then AVG_PID_MEM_PERCENT=0.0; fi
	if [ -z "$AVG_UTILIZATION_CPU" ]; then AVG_UTILIZATION_CPU=0.0; fi
	if [ ${TEMPERATURE_CPU[0]} == 'NA' ]; then AVG_TEMPERATURE_CPU=NA; MAX_TEMPERATURE_CPU=NA; fi
	if [ ${POWER_CPU[0]} == 'NA' ]; then AVG_POWER_CPU=NA; MAX_POWER_CPU=NA; fi

	echo $PPS,$AVG_PID_CPU_PERCENT,$MAX_PID_CPU_PERCENT,$AVG_UTILIZATION_CPU,$MAX_UTILIZATION_CPU,$AVG_PID_MEM_PERCENT,$MAX_PID_MEM_PERCENT,\
	$MAX_PID_MEM_MB,$MIN_MEM_AVAIL_MB,$MIN_MEM_AVAIL_PERCENT,$AVG_TEMPERATURE_CPU,$MAX_TEMPERATURE_CPU,$AVG_POWER_CPU,$MAX_POWER_CPU,$AVG_RXPPS,$MAX_RXPPS,$AVG_RXBPS,\
	$MAX_RXBPS,$SUM_IFACE_DROPS,$AVG_IFACE_DROPS,$IFACE_DROPS_PERCENT,$SUM_KERN_DROPS,$AVG_KERN_DROPS,$TUNING_FACTORS >> "$HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv"


	echo "Total packets past kernel phase: $RX_PKTS_TOTAL"
	#echo "Iface Drops: $SUM_IFACE_DROPS $IFACE_DROPS_PERCENT%"
	#echo "kern drops: $SUM_KERN_DROPS $KERN_DROPS_PERCENT%"

	(head -n2 && tail -n1) < $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv | column -t -s ,
	#column -t -s , $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv
	exec 3>&1- 4>&2-
	exit 0
}

##"main" function below
#sleep 2 #brief warmup
trap finish EXIT  #Capture ctrl-c or kill signals so I can cleanup

echo "Watching process: $PROCESS_NAME ($PID)"
echo "I'm running on a: $DEVICE_FAM board with a $NIC_DRIVER interface "
echo "runtime will be $TOTAL_RUNTIME with factors $TUNING_FACTORS"
SECONDS=0
exec 3>&1 4>&2 #bash magic to get the output of the time command and save the functions stdout/stderr
while [[ -d /proc/$PID && $SECONDS -lt $TOTAL_RUNTIME ]]
do
	#This needs to be as close as possible to SAMPLE_RATE sec for "per second" calculations to be accurate
	#As system load nears 100% the loop will likely drift, so try to account for it.
	#Still not perfect, but close enough for now.
	{ time {
			sleep $SAMPLE_RATE & captureLap 1>&3 2>&4;
			if [ ${RXPPS[$LOOP_COUNT-1]} -lt '10' ]; then SECONDS=0; fi #Dont start the countdown till packets start arriving. 10 accounts for random broadcasts
			wait $!; } } 2>"$tmp/lastloop"
	LOOP_TIME_REAL=$(cat $tmp/lastloop)
done
