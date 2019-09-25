#!/bin/bash

#Command line args
PPS=$1
PID=$2
IFACE=$3

echo $$ > /experiment/perfpid
tmp=$(mktemp -d)
echo "Temp folder at: $tmp"
echo "New run -- tx PPS:" $PPS >> /experiment/gather_stats.csv
echo "txpps,%cpu,%totalcpu,%mem,mem_MB,memavail,cpu_temp(c),cpu_power(w),rxpps,rxmbps,iface_drop,kern_drop,loop_drift" >> /experiment/gather_stats.csv

#top has to be kept running to gather accurate CPU stats over time. See man page for how it calcs this. ps doesnt provide usefull data, see man page as well
top -p $PID -b -d 1 > /$tmp/tmp &

#Initialize vars
MAX_PCPU=0
MAX_TOTAL_CPU=0
MAX_PMEM=0
MAX_MEM_MB=0
MIN_MEM_AVAIL=2147483647 #set to max int here so min calc works below
MAX_CPUTEMP=0
MAX_CPUPOWER=0
MAX_RXPPS=0
MAX_RXBPS=0
TOTAL_IFACE_DROPS=0
TOTAL_KERN_DROPS=0
LOOP_TIME_REAL=1
IFACE_DROP_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors) 
KERN_DROP_LAST=0
RX_PKTS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
RX_BPS_LAST=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TIMEFORMAT=%R

function capture_lap {
	#Time dependant ("per second") samples below. 0.01 slight unaccounted overhead adjustment
	RX_PKTS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_packets)
	RXPPS=$(bc <<< "scale=0; ($RX_PKTS_NOW - $RX_PKTS_LAST) / ($LOOP_TIME_REAL + 0.01)")
	RX_PKTS_LAST=$RX_PKTS_NOW
	RX_BPS_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
	RXBPS=$(bc <<< "scale=0; (($RX_BPS_NOW - $RX_BPS_LAST) / 125000) / ($LOOP_TIME_REAL + 0.01) ")
	RX_BPS_LAST=$RX_BPS_NOW
	
	#Technically "per second" but any adjustments would throw off final count. Not as important
	KERN_DROP_NOW=$(suricatasc /var/run/suricata-command.socket -c "iface-stat eth0" | awk '{ print $5 }'| egrep -o [0-9]+)
	KERN_DROPS=$(( $KERN_DROP_NOW - $KERN_DROP_LAST ))
	KERN_DROP_LAST=$KERN_DROP_NOW
	
	#Also per second. See above. Might be specific to this NIC driver. e1000e
	IFACE_DROP_NOW=$(cat /sys/class/net/$IFACE/statistics/rx_missed_errors) 
	IFACE_DROPS=$(( $IFACE_DROP_NOW-$IFACE_DROP_LAST ))
    IFACE_DROP_LAST=$IFACE_DROP_NOW
	
	#Regular sensors / reports
	PMEM=$(ps -p $PID -o pmem --no-headers)
	MEM_MB=$(bc <<< 'scale=0; '$(ps -p $PID -o rss --no-headers)' / 976.562' )
	MEM_AVAIL=$(bc <<< 'scale=0; '$(tail -5 /$tmp/tmp | head -n 1 | awk '{ print $6 + $10 }')' / 976.562' )
	PCPU=$(tail -1 /$tmp/tmp | awk '{ print $9 }')
	TOTAL_CPU=$(tail -6 /$tmp/tmp | head -n 1 | awk '{ print $2 }')
	CPUTEMP=$(bc <<< 'scale=2; '$(cat /sys/devices/virtual/thermal/thermal_zone1/temp)' / 1000') #specific to TX1...
	CPUPOWER=$(bc <<< 'scale=3; '$(cat /sys/devices/7000c400.i2c/i2c-1/1-0040/iio_device/in_power0_input)' / 1000') #specific to TX1...other sensors here as well
	
	#echo $LOOP_TIME_REAL tx PPS\: $PPS - \%CPU\: $PCPU - TOTAL CPU\: $TOTAL_CPU - \%MEM\: $PMEM - MEM MB\: $MEM_MB - \
	#MB FREE\: $MEM_AVAIL - CPUTEMP\(C\)\: $CPUTEMP - CPU POWER\(W\)\: $CPUPOWER - rx PPS\: $RXPPS - rx mbps\: $RXBPS - iface drops\: $IFACE_DROPS, $KERN_DROPS
	echo $PPS,$PCPU,$TOTAL_CPU,$PMEM,$MEM_MB,$MEM_AVAIL,$CPUTEMP,$CPUPOWER,$RXPPS,$RXBPS,$IFACE_DROPS,$KERN_DROPS,$LOOP_DRIFT>> /experiment/gather_stats.csv
	capture_limits
}

function capture_limits {
	#Performance (thus accuracy) hit for all these conditionals?? 
	#Timing tests seems low impact (0.03s idle up to .2 loaded)
	if (( $(echo $MAX_PCPU '<' $PCPU | bc -l) )); then MAX_PCPU=$PCPU; fi
	if (( $(echo $MAX_TOTAL_CPU '<' $TOTAL_CPU | bc -l) )); then MAX_TOTAL_CPU=$TOTAL_CPU; fi 
	if (( $(echo $MAX_PMEM '<' $PMEM | bc -l) )); then MAX_PMEM=$PMEM; fi 
	if (( $(echo $MAX_MEM_MB '<' $MEM_MB | bc -l) )); then MAX_MEM_MB=$MEM_MB; fi 
	if (( $(echo $MIN_MEM_AVAIL '>' $MEM_AVAIL | bc -l) )); then MIN_MEM_AVAIL=$MEM_AVAIL; fi 
	if (( $(echo $MAX_CPUTEMP '<' $CPUTEMP | bc -l) )); then MAX_CPUTEMP=$CPUTEMP; fi 
	if (( $(echo $MAX_CPUPOWER '<' $CPUPOWER | bc -l) )); then MAX_CPUPOWER=$CPUPOWER; fi 
	if [ "$MAX_RXPPS" -lt "$RXPPS" ]; then MAX_RXPPS=$RXPPS; fi 
	if [ "$MAX_RXBPS" -lt "$RXBPS" ]; then MAX_RXBPS=$RXBPS; fi
	TOTAL_IFACE_DROPS=$(( $TOTAL_IFACE_DROPS + $IFACE_DROPS ))
	TOTAL_KERN_DROPS=$(( $TOTAL_KERN_DROPS + $KERN_DROPS ))	
	
	#TODO: Store values in array and calculate averages in finish
}

function finish {
	echo "SIGTERM: Cleaing up"
	rm -rf "$tmp"
	rm -rf /experiment/perfpid
	
	if [ ! -f /experiment/gather_totals.csv ]; then
		echo "txpps,max %cpu,max %totalcpu,%mem,mem_MB,memavail,cpu_temp(c),cpu_power(w),rxpps,rxmbps,iface_drop,kern_drop" >> /experiment/gather_totals.csv
	fi
	echo $PPS,$MAX_PCPU,$MAX_TOTAL_CPU,$MAX_PMEM,$MAX_MEM_MB,$MIN_MEM_AVAIL,$MAX_CPUTEMP,$MAX_CPUPOWER,$MAX_RXPPS,$MAX_RXBPS,$TOTAL_IFACE_DROPS,$TOTAL_KERN_DROPS >> /experiment/gather_totals.csv
	column -t -s , gather_totals.csv
	exec 3>&1- 4>&2-
}


##"main" function below
#Capture ctrl-c or kill signals so I can cleanup
trap finish EXIT
#bash magic to get the output of the time command and save the functions stdout/stderr
exec 3>&1 4>&2
while : 
do	
		#This needs to be as close as possible to 1 sec for "per second" calculations to be accurate
		#As system load nears 100% adjustments may be needed and measured in real-time
		#Still not perfect, but close enough.
		{ time { sleep 1 & capture_lap 1>&3 2>&4; wait $!; }  } 2>"/$tmp/lastloop" 
		LOOP_TIME_REAL=$(cat /$tmp/lastloop)
		
		#time only the function 
		#sleep 1 &
		#	{ time capture_lap 1>&3 2>&4; } 2>"/$tmp/lastloop" 
		#	LOOP_TIME_REAL=$(cat /$tmp/lastloop)
		#wait $!
done
