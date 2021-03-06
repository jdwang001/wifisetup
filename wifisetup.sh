#!/bin/sh

. /usr/share/libubox/jshn.sh

bNoOp=0		# for being included in other scripts
bSetupWifi=1
bSetupAp=0
bDisableWwanCheck=0
bKillAp=0
bKillSta=0
bCheckConnection=0
bCheckWwan=0
bUsage=0
bJsonOutput=0

bScanFailed=0
bWwanUp=0


ssid=""
password=""
auth=""

apIpAddr=""

authDefault="psk2"
authDefaultAp="none"
networkType=""

intfCount=0
intfAp=-1
intfSta=-1
intfNewSta=-1
intfNewAp=-1

tmpPath="/tmp"
pingUrl="http://cloud.onion.io/api/util/ping"
timeout=500

retSetup="false"
retDeleteIface="false"
retSetNetworkIfname="false"
retChkConnect="false"
retChkWwan="false"


# function to print script usage
Usage () {
	echo "Functionality:"
	echo "	Setup WiFi on the Omega"
	echo ""
	echo "Usage:"
	echo "$0"
	echo "	Accepts user input"
	echo ""
	echo ""
	echo "Setting up a connection to a Wifi Network:"
	echo "$0 -ssid <ssid> -password <password>"
	echo "	Specify ssid and password, default auth is wpa2"
	echo "$0 -ssid <ssid> -password <password> -auth <authentication type>"
	echo "	Specify ssid, authentication type, and password"
	echo "	Possible authentication types"
	echo "		psk2"
	echo "		psk"
	echo "		wep"
	echo "		none	(note: password argument will be discarded)"
	echo ""
	echo "Option for two above use cases:"
	echo " -disablewwancheck 	do not check if wwan device is up after wifi setup"
	echo ""
	echo ""
	echo "To setup an Access Point on the Omega:"
	echo "  add the following flag to the above commands"
	echo " -accesspoint		create access-point instead of connect to network"
	echo ""
	echo "Option for AP setup:"
	echo " -ip <ip address>	Sets the Omega AP's IP address and the network subnet"
	echo ""
	echo ""
	echo "Other operations"
	echo "$0 -killap"
	echo "	Disables any existing AP networks"
	echo ""
	echo "$0 -killsta"
	echo "	Disables any existing STA networks"
	echo ""
	echo "$0 -checkwwan"
	echo "	Check wwan status"
	echo ""
	echo "$0 -checkconnection"
	echo "	Check if connected to the internet"
	echo ""
	echo "Options:"
	echo "	-ubus		Output only json"
	echo ""
}

# function to scan wifi networks
ScanWifi () {
	# run the scan command and get the response
	local RESP=$(ubus call iwinfo scan '{"device":"wlan0"}')
	
	# read the json response
	json_load "$RESP"
	
	# check that array is returned  
	json_get_type type results

	# find all possible keys
	json_select results
	json_get_keys keys
	
	
	if 	[ "$type" == "array" ] &&
		[ "$keys" != "" ];
	then
		echo ""
		echo "Select Wifi network:"
		
		# loop through the keys
		for key in $keys
		do
			# select the array element
			json_select $key
			
			# find the ssid
			json_get_var cur_ssid ssid
			if [ "$cur_ssid" == "" ]
			then
				cur_ssid="[hidden]"
			fi
			echo "$key) $cur_ssid"

			# return to array top
			json_select ..
		done

		# read the input
		echo ""
		echo -n "Selection: "
		read input;
		
		# get the selected ssid
		json_select $input
		json_get_var ssid ssid
		
		echo "Network: $ssid"

		# detect the encryption type 
		ReadNetworkAuthJson

		echo "Authentication type: $auth"
	else
		# scan returned no results
		bScanFailed=1
	fi
}

# function to read network encryption from 
ReadNetworkAuthJson () {
	# select the encryption object
	json_get_type type encryption

	# read the encryption object
	if [ "$type" == "object" ]
	then
		# select the encryption object
		json_select encryption

		# read the authentication object type
		json_get_type type authentication
		if [ "$type" != "" ]
		then
			# read the authentication type
			json_select authentication
			json_get_keys auth_arr
			
			json_get_values auth_type 
			json_select ..

			# read psk specifics
			if [ "$auth_type" == "psk" ]
			then
				ReadNetworkAuthJsonPsk
			else
				auth=$auth_type
			fi
		else
			# no encryption, open network
			auth="none"
		fi
	else
		# no encryption, open network
		auth="none"
	fi
}

# function to read wpa settings from the json
ReadNetworkAuthJsonPsk () {
	local bFoundType1=0
	local bFoundType2=0

	# check the wpa object
	json_get_type type wpa

	# read the wpa object
	if [ "$type" == "array" ]
	then
		# select the wpa object
		json_select wpa

		# find all the values
		json_get_values values

		# read all elements
		for value in $values
		do
			# parse value
			if [ $value == 1 ]
			then
				bFoundType1=1
			elif [ $value == 2 ]
			then
				bFoundType2=1
			fi
		done

		# return to encryption object
		json_select ..

		# select the authentication type based on the wpa values that were found
		if [ $bFoundType1 == 1 ]
		then
			auth="psk"
		fi
		if [ $bFoundType2 == 1 ]
		then
			# wpa2 overrides wpa
			auth="psk2"
		fi

	fi
}

# function to read network encryption from user
ReadNetworkAuthUser () {
	echo ""
	echo "Select network authentication type:"
	echo "1) WPA2"
	echo "2) WPA"
	echo "3) WEP"
	echo "4) none"
	echo ""
	echo -n "Selection: "
	read input
	

	case "$input" in
    	1)
			auth="psk2"
	    ;;
	    2)
			auth="psk"
	    ;;
	    3)
			auth="wep"
	    ;;
	    4)
			auth="none"
	    ;;
	esac

}

# function to read user input
ReadUserInput () {
	echo "Onion Omega Wifi Setup"
	echo ""
	echo "Select from the following:"
	echo "1) Scan for Wifi networks"
	echo "2) Type network info"
	echo "q) Exit"
	echo ""
	echo -n "Selection: "
	read input

	# choice between scanning 
	if [ $input == 1 ]
	then
		# perform the scan and select network
		echo "Scanning for wifi networks..."
		ScanWifi

	elif [ $input == 2 ]
	then
		# manually read the network name
		echo -n "Enter network name: "
		read ssid;

		# read the authentication type
		ReadNetworkAuthUser
	else
		echo "Bye!"
		exit
	fi

	# read the network password
	if 	[ "$auth" != "none" ] &&
		[ $bScanFailed == 0 ];
	then
		echo -n "Enter password: "
		read password
	fi

	echo ""
}

# function to check for existing wireless UCI data
# 	populates intfAp with wifi-iface number of AP network
# 	populates intfSta with wifi-iface number of STA network
#	a value of -1 incicates not found
CheckCurrentUciWifi () {
	# default values
	intfAp=-1
	intfSta=-1
	intfCount=0

	# get the current wireless setup
	local RESP=$(ubus call network.wireless status)
	
	# read the json response
	json_load "$RESP"
	
	# check radio0 type
	json_get_type type radio0
	
	if [ "$type" == "object" ]; then
		# traverse down to radio0
		json_select radio0

		# check that interfaces is an array and get the keys
		json_get_type type interfaces
		json_get_keys keys interfaces
		
		
		if 	[ "$type" == "array" ] &&
			[ "$keys" != "" ];
		then
			# traverse down to interfaces
			json_select interfaces

			# loop through the keys
			for key in $keys
			do
				# find the type and select the array element
				json_get_type type $key
				json_select $key
				
				# find out if interface is set to ap
				json_get_type type config 
				if [ "$type" == "object" ]; then
					json_select config
					json_get_var wifiMode mode

					if [ "$wifiMode" == "ap" ]; then
						intfAp=`expr $key - 1`
					elif [ "$wifiMode" == "sta" ]; then
						intfSta=`expr $key - 1`
					fi

					json_select ..
				fi

				# increment the interface count
				intfCount=`expr $intfCount + 1`

				# return to array top
				json_select ..
			done
		
		fi # interfaces is a non-empty array
	fi # radio0 == object

}

# function to perform the wifi setup
#	$1 	- interface number
#	$2 	- interface type "ap" or "sta"
UciSetupWifi () {
	local commit=1
	local intfId=$1
	local networkType=$2

	

	# setup new intf if required
	local iface=$(uci -q get wireless.\@wifi-iface[$intfId])
	if [ "$iface" != "wifi-iface" ]; then
		#echo "  Adding intf $intfId"
		uci add wireless wifi-iface > /dev/null
		uci set wireless.@wifi-iface[$intfId].device="radio0" 
	fi

	# perform the type specific setup
	if [ "$networkType" = "sta" ]; then
		if [ $bJsonOutput == 0 ]; then
			echo "> Connecting to $ssid network using intf $intfId..."
		fi

		# use UCI to set the network to client mode and wwan
		uci set wireless.@wifi-iface[$intfId].mode="sta"
		uci set wireless.@wifi-iface[$intfId].network="wwan"
	elif [ "$networkType" = "ap" ]; then
		if [ $bJsonOutput == 0 ]; then
			echo "> Setting up $ssid Access Point using intf $intfId..."
		fi

		# use UCI to set the network to access-point mode and wlan
		uci set wireless.@wifi-iface[$intfId].mode="ap"
		uci set wireless.@wifi-iface[$intfId].network="wlan"

		# use UCI to set the default IP address 
		if [ "$apIpAddr" != "" ]; then
			uci set network.wlan.ipaddr="$apIpAddr"
		fi
	fi 

	# use UCI to set the ssid and encryption
	uci set wireless.@wifi-iface[$intfId].ssid="$ssid"
	uci set wireless.@wifi-iface[$intfId].encryption="$auth"

	# set the network key based on the authentication
	case "$auth" in
		psk|psk2)
			uci set wireless.@wifi-iface[$intfId].key="$password"
	    ;;
	    wep)
			uci set wireless.@wifi-iface[$intfId].key=1
			uci set wireless.@wifi-iface[$intfId].key1="$password"
	    ;;
	    none)
			# set no keys for open networks, delete any existing ones
			local key=$(uci -q get wireless.\@wifi-iface[$intfId].key)

			if [ "$key" != "" ]; then
				uci delete wireless.@wifi-iface[$intfId].key
			fi
	    ;;
	    *)
			# invalid authorization
			commit=0
	esac


	# commit the changes
	if [ $commit == 1 ]; then
		uci commit wireless
		
		# check if network has to be committed (for AP addr change)
		if 	[ "$networkType" = "ap" ] &&
			[ "$apIpAddr" != "" ]; then
			uci commit network
		fi

		# reset the wifi adapter
		wifi

		# set the setup return value to true
		retSetup="true"
	else
		if [ $bJsonOutput == 0 ]; then
			if [ "$networkType" = "sta" ]; then
				echo "ERROR: invalid network authentication specified"
				echo "	See possible authentication types below"
				echo ""
				echo ""
				Usage
			fi
		fi

		# set the setup return value to false
		retSetup="false"
	fi
}

# function to disable the specified iface
#	$1 - iface number
#	$2 - iface mode (ap or sta)	[optional]
UciDeleteIface () {
	local commit=1

	if [ $1 -ge 0 ]; then
		# ensure that iface exists
		local iface=$(uci -q get wireless.\@wifi-iface[$1])
		if [ "$iface" != "wifi-iface" ]; then
			if [ $bJsonOutput == 0 ]; then
				echo "> No network on intf $1"
			fi
			commit=0
		fi

		# ensure that iface is in correct mode
		if [ "$2" != "" ]; then
			local mode=$(uci -q get wireless.\@wifi-iface[$1].mode)
			if [ "$mode" != "$2" ]; then
				if [ $bJsonOutput == 0 ]; then
					echo "> Network intf $1 is not set to $2 mode"
				fi
				commit=0
			fi
		fi

		# delete the network iface
		if [ $commit == 1 ]; then
			if [ $bJsonOutput == 0 ]; then
				echo "> Disabling network on iface $1 ..."
			fi

			uci delete wireless.@wifi-iface[$1]
			uci commit wireless

			# reset the network adapter
			/etc/init.d/network restart

			# set the kill network return value
			retDeleteIface="true"
		else 
			# set the kill network return value
			retDeleteIface="false"
		fi
	else
		if [ $bJsonOutput == 0 ]; then
			echo "> No $2 networks to disable!"
		fi

		# set the kill network return value
		retDeleteIface="false"
	fi
}

# function to check if wwan connection is up
#	if not, there is an issue with the network password
CheckWwanStatus () {
	# use ubus to read if wwan is up
	local resp=$(ubus call network.interface.wwan status)
	json_load "$resp"
	json_get_var bWwanStatus up 

	# set global wwan up variable
	bWwanUp=0;
	retChkWwan="false";
	if [ $bWwanStatus == 1 ]; then
		bWwanUp=1;
		retChkWwan="true"
	fi

	# stdout
	if [ $bJsonOutput == 0 ]; then
		echo "> Checking wwan device status..."
		echo -n "> wwan is "
		if [ $bWwanStatus == 1 ]; then
			echo "up"
		else
			echo "not up!!"
		fi
	fi
}

# function to check if omega is connected to the internet
CheckInternetConnection () {
	local fileName="$tmpPath/ping.json"
	local tmpFile="$tmpPath/check.txt"
	if [ -f $fileName ]; then
		# delete any local copy
		local rmCmd="rm -rf $fileName"
		eval $rmCmd
	fi

	# define the wget commands
	local wgetSpiderCmd="wget -t $timeout --spider -o $tmpFile \"$pingUrl\""
	local wgetCmd="wget -t $timeout -q -O $fileName \"$pingUrl\""

	# check the ping file exists
	if [ $bJsonOutput == 0 ]; then
		echo "> Checking internet connection..."
	fi

	local count=0
	local bLoop=1
	while 	[ $bLoop == 1 ];
	do
		eval $wgetSpiderCmd

		# read the response
		local readback=$(cat $tmpFile | grep "Remote file exists.")
		if [ "$readback" != "" ]; then
			bLoop=0
		fi

		# implement time-out
		count=`expr $count + 1`
		if [ $count -gt $timeout ]; then
			bLoop=0
			if [ $bJsonOutput == 0 ]; then
				echo "> ERROR: request timeout, internet connection not successful"
			fi

			# set the connect check return value
			retChkConnect="false"
			return
		fi
	done

	# fetch the json file
	while 	[ ! -f $fileName ]
	do
		eval $wgetCmd
	done

	# parse the json file
	local RESP=$(cat $fileName)
	json_load "$RESP"

	# check the json file contents
	json_get_var response success
	if [ "$response" == "OK" ]; then
		if [ $bJsonOutput == 0 ]; then
			echo "> Internet connection successful!!"
		fi

		# set the connect check return value
		retChkConnect="true"
	else
		if [ $bJsonOutput == 0 ]; then
			echo "> ERROR: internet connection not successful"
		fi

		# set the connect check return value
		retChkConnect="false"
	fi
}



########################
##### Main Program #####

# read the arguments
if [ $# == 0 ]
then
	## accept all info from user interactions
	bCheckConnection=1 	# check connection

	ReadUserInput
else
	## accept info from arguments
	while [ "$1" != "" ]
	do
		case "$1" in
	    	-h|-help|--help|help)
				bUsage=1
				shift
			;;
	    	-killap)
				bKillAp=1
				bSetupWifi=0
				shift
			;;
			-killsta)
				bKillSta=1
				bSetupWifi=0
				shift
			;;
			-disablewwancheck)
				bDisableWwanCheck=1
				shift
			;;
			-connectioncheck|-checkconnection)
				bCheckConnection=1
				bSetupWifi=0
				shift
			;;
			-checkwwan)
				bCheckWwan=1
				bSetupWifi=0
				shift
			;;
			-ubus|-u)
				bJsonOutput=1
				shift
			;;
		    -ssid)
				shift
				ssid="$1"
				shift
			;;
		    -password)
				shift
				password="$1"
				shift
			;;
			-ip)
				shift
				apIpAddr="$1"
				shift
			;;
		    -auth)
				shift
				auth=$1
				shift
			;;
			-accesspoint)
				bSetupAp=1
				shift
			;;
			-noop)
				bNoOp=1
				shift
			;;
		    *)
				echo "ERROR: Invalid Argument: $1"
				echo ""
				bUsage=1
				shift
			;;
		esac
	done
fi


# print the usage
if [ $bUsage == 1 ]; then
	Usage
	exit
fi


# run the main program
if [ $bNoOp == 0 ]; then

	# check the variables
	if [ $bSetupWifi == 1 ]; then
		# check for scan success
		if 	[ $bScanFailed == 1 ]
		then
			echo "ERROR: no networks detected... try again in a little while"
			exit
		fi

		# setup default auth if ssid and password are defined
		if 	[ "$ssid" != "" ] &&
			[ "$password" != "" ] &&
			[ "$auth" == "" ];
		then
			auth="$authDefault"
		fi

		# setup default auth for AP mode
		if 	[ "$ssid" != "" ] &&
			[ "$auth" == "" ] &&
			[ $bSetupAp == 1 ];
		then
			auth="$authDefaultAp"
		fi

		# check that user has input enough data
		if 	[ "$ssid" == "" ]
		then 
			echo "ERROR: network ssid not specified"
			exit
		fi
		if 	[ "$auth" == "" ]
		then
			echo "ERROR: network authentication type not specified"
			exit
		fi
	fi


	## check current wireless setup
	CheckCurrentUciWifi


	## define new intf id based on existing intfAp and intfSta
	#	case 	intfAp	intfSta		new STA intf 	new AP intf
	#	a  		0		-1			intfAp + 1 		intfAp
	#	b 		0 		1			intfSta			intfAp
	#	c 		-1		-1			0				0
	#	d 		-1		0			intfSta			intfSta + 1
	if 		[ $intfAp -ge 0 ] &&
			[ $intfSta == -1 ];
	then
		## case a
		# AP exists, overwrite it
		intfNewAp=$intfAp

		# STA on next free iface id
		intfNewSta=$intfCount

	elif 	[ $intfAp -ge 0 ] &&
			[ $intfSta -ge 0 ];
	then
		## case b
		# AP exists, overwrite it
		intfNewAp=$intfAp

		# STA exists, overwrite it
		intfNewSta=$intfSta

	elif 	[ $intfAp == -1 ] &&
			[ $intfSta == -1 ];
	then
		## case c
		# new network on iface 0 (or next free iface)
		intfNewAp=$intfCount
		intfNewSta=$intfCount

	elif 	[ $intfAp == -1 ] &&
			[ $intfSta -ge 0 ];
	then
		# AP on next free iface id
		intfNewAp=$intfCount

		# STA exists, overwrite it
		intfNewSta=$intfSta
	fi


	## setup the wifi
	if 	[ $bSetupWifi == 1 ]; then
		# print json before performing the config change
		# (only if just doing wifi setup)
		if 	[ $bJsonOutput == 1 ] && 
			[ $bCheckConnection == 0 ];
		then
			json_init
			json_add_string "connecting" "true"
			json_dump
		fi

		# differentiate between sta and ap networks
		if [ $bSetupAp == 0 ]; then
			# sta
			intfNew=$intfNewSta
			networkType="sta"
		elif [ $bSetupAp == 1 ]; then
			# ap
			intfNew=$intfNewAp
			networkType="ap"
		fi

		UciSetupWifi $intfNew "$networkType"

		# check if wwan is up
		if 	[ $bDisableWwanCheck == 0 ] &&
			[ $bSetupAp == 0 ]; 
		then
			# give the interface time to connect
			sleep 10

			# add an additional wait if there was an existing STA
			if [ $intfSta -ge 0 ]; then
				#	wwwan needs to go down, then go back up, takes longer
				sleep 8
			fi

			CheckWwanStatus

			# remove sta if not up
			if [ $bWwanUp == 0 ]; then
				bKillSta=1
				intfSta=$intfNewSta
			fi
		fi
	fi


	## give iface time to connect
	# 	if doing both setup and check
	if 	[ $bSetupWifi == 1 ] &&
		[ $bCheckConnection == 1 ] &&
		[ $bDisableWwanCheck == 1 ]; 
	then
		if [ $bJsonOutput == 0 ]; then
			echo "> Waiting so that iface connects..."
		fi

		sleep 10
	fi


	## check the connection
	if 	[ $bCheckConnection == 1 ]; 
	then
		CheckInternetConnection
	fi


	## check the wwan status
	if 	[ $bCheckWwan == 1 ]; 
	then
		CheckWwanStatus
	fi


	## kill the existing AP network 
	if 	[ $bKillAp == 1 ]; then
		UciDeleteIface $intfAp "ap"
	fi


	## kill the existing STA network
	if 	[ $bKillSta == 1 ]; then
		UciDeleteIface $intfSta "sta"
	fi


	## print json output
	if [ $bJsonOutput == 1 ]; then
		local bPrintJson=0
		json_init

		# add the wwan check result
		if 	[ $bCheckWwan == 1 ];
		then
			json_add_string "wwan" "$retChkWwan"
			bPrintJson=1
		fi

		# add the connection check result
		if 	[ $bCheckConnection == 1 ];
		then
			json_add_string "connection" "$retChkConnect"
			bPrintJson=1
		fi

		# add the disable AP result
		if [ $bKillAp == 1 ]; then
			json_add_string "disable_ap" "$retDeleteIface"
			bPrintJson=1
		fi

		# add the disable AP result
		if [ $bKillSta == 1 ]; then
			json_add_string "disable_sta" "$retDeleteIface"
			bPrintJson=1
		fi

		# print the json
		if [ $bPrintJson == 1 ]; then
			json_dump
		fi
	fi


	## done
	if [ $bJsonOutput == 0 ]; then
		echo "> Done!"
	fi

fi 	# no-op check


