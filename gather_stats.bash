#!/bin/bash

#Command line args
PPS=$1
PID=$2
IFACE=$3
SAMPLE_RATE=$4

if [ -z "$4" ]; then
	echo "Usage: bash $0 <test pps rate> <monitor pid> <capture interface> <sample rate in seconds>"
	echo "ex: bash $0 100000 8912 eth0 0.5"
	echo "a negative pid will watch only the interface / irq handler"
	echo "sudo access required"
	exit 1
fi

if [ $PID -lt '0' ]; then 
	echo "Using interface rate mode only";
	#Watching softirq daemon, that handles the last half of the interrupt from the NIC
	#Thread 0 is most likely on the ARM based boards (first thread) 
	PID=$(top -b -n 1 | grep ksoftirqd/0 | awk 'NR == 1 { print $1}');
	PROCESS_NAME=ksoftirqd0;
elif [ ! -d /proc/$PID ]; then 
	echo "supplied PID isn't running, exiting"; 
	exit 1; 
else PROCESS_NAME=$(ps -p $PID -o comm=); fi

#Store my pid so I can be killed later
cd "$(dirname "$0")"
echo $$ > gather.pid
tmp=$(mktemp -d)

#top has to be kept running to gather accurate CPU stats over time. 
#See man page for how it calcs this. ps doesn't provide useful data, see man page as well
top -p $PID -b -d 1 > /$tmp/tmp &

echo "Bumping process priority"
sudo renice -n -15 $(pidof top) #bump my top process priority
sudo renice -n -20 $$ #bump my priority to max

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

#Might be a better way to fingerprint the machine
if [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'Raspberry' ]; then DEVICE_FAM=pi;
elif [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'Jetson-TX1' ]; then DEVICE_FAM=nvidia-tx1;
elif [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'quill' ]; then DEVICE_FAM=nvidia-tx2;
elif [ $(sudo lshw -short -c system | awk 'FNR == 3 {print $2}') == 'Jetson-AGX' ]; then DEVICE_FAM=nvidia-xavier;
else DEVICE_FAM=unknown; fi


NIC_DRIVER=$(ethtool -i $IFACE | head -1 | awk '{ print $2 }') 


echo "Temp folder at: $tmp"
echo "New run -- tx PPS: $PPS -- Sample rate: $4 -- Driver: $NIC_DRIVER" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results-verbose.csv
echo "txpps,%cpu,%totalcpu,%mem,mem_MB,memavail,cpu_temp(c),cpu_power(w),rxpps,rxmbps,iface_drop,kern_drop,loop_time" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results-verbose.csv
echo "Watching process: $PROCESS_NAME ($PID)"
echo "I'm running on a: $DEVICE_FAM board with a $NIC_DRIVER interface "

#Initialize vars
KERN_DROP_LAST=0
if [ "$NIC_DRIVER" == 'e1000e' ] || [ "$NIC_DRIVER" == 'igb' ] || [ "$NIC_DRIVER" == 'tg3' ] || [ "$NIC_DRIVER" == 'eqos' ] ; then 
	IFACE_DROP_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors);
elif [ "$NIC_DRIVER" == 'lan78xx' ] || [ "$NIC_DRIVER" == 'bcmgenet' ] ; then 
	IFACE_DROP_LAST=$(ethtool -S $IFACE | grep "RX Dropped Frames:" | awk '{print $4}'); 
fi


RX_PKTS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
RX_BPS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TIMEFORMAT=%R
LOOP_COUNT=0
LOOP_TIME_REAL=$SAMPLE_RATE
SECONDSFORMAT=%R

function captureLap {
	#Time dependant ("per second") samples below.
	RX_PKTS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
	RXPPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($RX_PKTS_NOW - $RX_PKTS_LAST) / ($LOOP_TIME_REAL)")
	RX_PKTS_LAST=$RX_PKTS_NOW
	RX_BPS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
	RXBPS[$LOOP_COUNT]=$(bc <<< "scale=0; (($RX_BPS_NOW - $RX_BPS_LAST) / 125000) / ($LOOP_TIME_REAL) ")
	RX_BPS_LAST=$RX_BPS_NOW

	#Handle bizzare rare case where a negative number gets calculated on super heavily loaded machine
	if [ ${RXBPS[$LOOP_COUNT]} -lt "0" ]; then RXBPS[$LOOP_COUNT]=0; fi
	if [ ${RXPPS[$LOOP_COUNT]} -lt "0" ]; then RXPPS[$LOOP_COUNT]=0; fi

	#Specific to suricata...
	if [ "$PROCESS_NAME" == "suricata" ]; then
		KERN_DROP_NOW=$(suricatasc /var/run/suricata-command.socket -c "iface-stat $IFACE" | awk '{ print $5 }'| egrep -o [0-9]+)
		KERN_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($KERN_DROP_NOW - $KERN_DROP_LAST) / $LOOP_TIME_REAL  ")
		KERN_DROP_LAST=$KERN_DROP_NOW
	else
		KERN_DROPS[$LOOP_COUNT]=NA
	fi

#if [ "$LOOP_COUNT" == "0" ]; then IFACE_DROPS[$LOOP_COUNT]=0; else 
	#Driver specific stat locations
	if [ "$NIC_DRIVER" == 'lan78xx' ]; then
		IFACE_DROP_NOW=$(ethtool -S $IFACE | grep "RX Dropped Frames:" | awk '{print $4}')
		IFACE_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($IFACE_DROP_NOW-$IFACE_DROP_LAST) / $LOOP_TIME_REAL  ");
		IFACE_DROP_LAST=$IFACE_DROP_NOW
	elif [ "$NIC_DRIVER" == 'e1000e' ] || [ "$NIC_DRIVER" == 'igb' ] || [ "$NIC_DRIVER" == 'tg3' ] || [ "$NIC_DRIVER" == 'eqos' ]; then
		IFACE_DROP_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors)
		IFACE_DROPS[$LOOP_COUNT]=$(bc <<< "scale=0; ($IFACE_DROP_NOW-$IFACE_DROP_LAST) / $LOOP_TIME_REAL  ")
		IFACE_DROP_LAST=$IFACE_DROP_NOW
	fi 

	#Device specific sensors
	if [ "$DEVICE_FAM" == 'pi' ]; then
		CPUTEMP[$LOOP_COUNT]=$(vcgencmd measure_temp | grep -ow "[0-9][0-9].[0-9]")
		CPUPOWER[$LOOP_COUNT]=$(expr $(vcgencmd measure_clock arm | grep -oP "([0-9]+)" | tail -1) / 1000000)
	elif [ "$DEVICE_FAM" == 'nvidia-tx1' ]; then
		CPUTEMP[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone1/temp)' / 1000')
		CPUPOWER[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/devices/7000c400.i2c/i2c-1/1-0040/iio_device/in_power0_input)' / 1000') 
	elif [ "$DEVICE_FAM" == 'nvidia-tx2' ]; then
		CPUTEMP[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone1/temp)' / 1000')
		CPUPOWER[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/bus/i2c/drivers/ina3221x/0-0041/iio_device/in_power0_input)' / 1000')
	elif [ "$DEVICE_FAM" == 'nvidia-xavier' ]; then
		CPUTEMP[$LOOP_COUNT]=$(bc <<< 'scale=1; '$(cat /sys/devices/virtual/thermal/thermal_zone0/temp)' / 1000')
		CPUPOWER[$LOOP_COUNT]=$(bc <<< 'scale=3; '$(cat /sys/bus/i2c/drivers/ina3221x/1-0040/iio_device/in_power1_input)' / 1000')
	else 
		CPUTEMP[$LOOP_COUNT]=NA
		CPUPOWER[$LOOP_COUNT]=NA
	fi

	#supress std err for now 
	exec 4>&2 2> /dev/null
	
	#Regular sensors / reports
	PMEM[$LOOP_COUNT]=$(ps -p $PID -o pmem --no-headers)
	MEM_MB[$LOOP_COUNT]=$(bc <<< 'scale=0; '$(ps -p $PID -o rss --no-headers)' / 976.562' )
	MEM_AVAIL[$LOOP_COUNT]=$(bc <<< 'scale=0; '$(tail -5 /$tmp/tmp | head -n 1 | awk '{ print $6 + $10 }')' / 976.562' )
	PCPU[$LOOP_COUNT]=$(tail -1 /$tmp/tmp | awk '{ print $9 }')
	TOTAL_CPU[$LOOP_COUNT]=$(tail -6 /$tmp/tmp | head -n 1 | awk '{ print $2 }')

	#return stderr to normal
	exec 2>&4 4>&-


#	echo txPPS\: $PPS - \%CPU\: ${PCPU[$LOOP_COUNT]} - TOTAL CPU\: ${TOTAL_CPU[$LOOP_COUNT]} - \%MEM\: ${PMEM[$LOOP_COUNT]} - MEM MB\: ${MEM_MB[$LOOP_COUNT]} - \
#	MB FREE\: ${MEM_AVAIL[$LOOP_COUNT]} - CPUTEMP\(C\)\: ${CPUTEMP[$LOOP_COUNT]} - CPU POWER\: ${CPUPOWER[$LOOP_COUNT]} - rxPPS\: ${RXPPS[$LOOP_COUNT]} - rxmbps\: ${RXBPS[$LOOP_COUNT]} - iface drps\: ${IFACE_DROPS[$LOOP_COUNT]}, krn drps\: ${KERN_DROPS[$LOOP_COUNT]}, loop\: $LOOP_TIME_REAL
	echo $PPS,${PCPU[$LOOP_COUNT]},${TOTAL_CPU[$LOOP_COUNT]},${PMEM[$LOOP_COUNT]},${MEM_MB[$LOOP_COUNT]},${MEM_AVAIL[$LOOP_COUNT]},${CPUTEMP[$LOOP_COUNT]},${CPUPOWER[$LOOP_COUNT]},${RXPPS[$LOOP_COUNT]},${RXBPS[$LOOP_COUNT]},${IFACE_DROPS[$LOOP_COUNT]},${KERN_DROPS[$LOOP_COUNT]},$LOOP_TIME_REAL>> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results-verbose.csv

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
	
	#Averages. Have to count the number of zeros in the array so they dont throw off averages
	#( All items in array / (Array size - zero count) )
	IFS='+'

	#currently only suricata gives access to real time kernel drops
	if [ "$PROCESS_NAME" == "suricata" ]; then
  	SUM_KERN_DROPS=$(echo "${KERN_DROPS[*]}"|bc)
		AVG_KERN_DROPS=$(echo "(${KERN_DROPS[*]}) / (${#KERN_DROPS[*]} - $(echo ${KERN_DROPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	elif [ "$PROCESS_NAME" == "tcpdump" ]; then
		AVG_KERN_DROPS=NA
		SUM_KERN_DROPS=$(cat /experiment/counters | awk ' FNR == 4 {print $1}')
		rm -rf counters
		rm -rf tcpdump.pid
	else
		AVG_KERN_DROPS=NA
		SUM_KERN_DROPS=NA
	fi

	#supress std err for now 
	exec 4>&2 2> /dev/null

	SUM_IFACE_DROPS=$(echo "${IFACE_DROPS[*]}"|bc)
	AVG_IFACE_DROPS=$(echo "(${IFACE_DROPS[*]}) / (${#IFACE_DROPS[*]} - $(echo ${IFACE_DROPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_RXPPS=$(echo "(${RXPPS[*]}) / (${#RXPPS[*]} - $(echo ${RXPPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)
	AVG_RXBPS=$(echo "(${RXBPS[*]}) / (${#RXBPS[*]} - $(echo ${RXBPS[*]} | grep -ow '0' | wc -l))"|bc 2> /dev/null)	
	AVG_PMEM=$(echo "scale=1; (${PMEM[*]}) / (${#PMEM[*]} - $(echo ${PMEM[*]} | grep -ow '0.0' | wc -l))"|bc)
	AVG_PCPU=$(echo "scale=1; (${PCPU[*]}) / (${#PCPU[*]} - $(echo ${PCPU[*]} | grep -ow '0.0' | wc -l))"|bc)
	AVG_CPUPOWER=$(echo "scale=3; (${CPUPOWER[*]}) / (${#CPUPOWER[*]} - $(echo ${CPUPOWER[*]} | grep -ow '0' | wc -l))"|bc)
	AVG_CPUTEMP=$(echo "scale=1; (${CPUTEMP[*]}) / (${#CPUTEMP[*]} - $(echo ${CPUTEMP[*]} | grep -ow '0.0' | wc -l))"|bc)
	AVG_TOTAL_CPU=$(echo "scale=1; (${TOTAL_CPU[*]}) / (${#TOTAL_CPU[*]} - $(echo ${TOTAL_CPU[*]} | grep -ow '0.0' | wc -l))"|bc)
	
	unset IFS

	#return stderr to normal
	exec 2>&4 4>&-
}

function finish {
	rm -rf "$tmp"
	rm -rf gather.pid

	killall top 2> /dev/null
	buildFinalStats

	if [ ! -f $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv ]; then
		#echo "txpps,%pidcpu.avg,%pidcpu.max,%syscpu.avg,%syscpu.max,%pidmem.avg,%sysmem.max,pidmemMB.max,sysmemfree.min,temp.avg,temp.max,power.avg,power.max,rxpps.avg,rxpps.max,rxmbps.avg,rxmbps.max,nicdrop.sum,nicdrop.avg,kerndrop.sum,kerndrop.avg,rate" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv
		echo "tx,%pidcpu,%pidcpu,%syscpu,%syscpu,%pidmem,%sysmem,pidmemMB,sysmemfree,temp,temp,power,power,rxpps,rxpps,rxmbps,rxmbps,nicdrop,nicdrop,kerndrop,kerndrop,rate" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv;
		echo "pps,avg,max,avg,max,avg,max,max,min,avg,max,avg,max,avg,max,avg,max,sum,avg,sum,avg,sec" >> $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv;
	fi

	#handle some empty cases before writing to file
	if [ -z "$AVG_IFACE_DROPS" ]; then AVG_IFACE_DROPS=0; fi
	if [ -z "$AVG_KERN_DROPS" ]; then AVG_KERN_DROPS=0; fi
	if [ -z "$AVG_RXBPS" ]; then AVG_RXBPS=0; fi
	if [ -z "$AVG_RXPPS" ]; then AVG_RXPPS=0; fi
	if [ -z "$AVG_PCPU" ]; then AVG_PCPU=0.0; fi
	if [ -z "$AVG_PMEM" ]; then AVG_PMEM=0.0; fi
	if [ -z "$AVG_TOTAL_CPU" ]; then AVG_TOTAL_CPU=0.0; fi
	if [ ${CPUTEMP[0]} == 'NA' ]; then AVG_CPUTEMP=NA; MAX_CPUTEMP=NA; fi 
	if [ ${CPUPOWER[0]} == 'NA' ]; then AVG_CPUPOWER=NA; MAX_CPUPOWER=NA; fi

	echo $PPS,$AVG_PCPU,$MAX_PCPU,$AVG_TOTAL_CPU,$MAX_TOTAL_CPU,$AVG_PMEM,$MAX_PMEM,$MAX_MEM_MB,$MIN_MEM_AVAIL,$AVG_CPUTEMP,$MAX_CPUTEMP,$AVG_CPUPOWER,$MAX_CPUPOWER,$AVG_RXPPS,$MAX_RXPPS,$AVG_RXBPS,$MAX_RXBPS,$SUM_IFACE_DROPS,$AVG_IFACE_DROPS,$SUM_KERN_DROPS,$AVG_KERN_DROPS,$SAMPLE_RATE >> "$HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv"
	column -t -s , $HOSTNAME-$NIC_DRIVER-$PROCESS_NAME-results.csv
	#exec 3>&1- 4>&2-
	exit 0
}

##"main" function below
sleep 2 #brief warmup
trap finish EXIT SIGTERM #Capture ctrl-c or kill signals so I can cleanup
#exec 3>&1 4>&2 #bash magic to get the output of the time command and save the functions stdout/stderr
while [ -d /proc/$PID  ]
do
		# { time { sleep $SAMPLE_RATE & captureLap 1>&3 2>&4; wait $!; } } 2> "/$tmp/lastloop"
		#LOOP_TIME_REAL=1 $(cat /$tmp/lastloop)
		
		SECONDS=0
		sleep $SAMPLE_RATE
		captureLap 
		
		#This needs to be as close as possible to SAMPLE_RATE sec for "per second" calculations to be accurate
		#As system load nears 100% the loop will likely drift, so try to account for it.
		#Still not perfect, but close enough.
		LOOP_TIME_REAL=$SECONDS
done
echo "Process I was watching died, wrapping up"
