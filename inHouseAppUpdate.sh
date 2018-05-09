#!/bin/sh
####################################################################################################
#
# THIS SCRIPT IS NOT AN OFFICIAL PRODUCT OF JAMF
# AS SUCH IT IS PROVIDED WITHOUT WARRANTY OR SUPPORT
#
# BY USING THIS SCRIPT, YOU AGREE THAT JAMF 
# IS UNDER NO OBLIGATION TO SUPPORT, DEBUG, OR OTHERWISE 
# MAINTAIN THIS SCRIPT 
#
####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME:
#	inHouseApp.sh - Helps update In-House Apps based on a Device Group ID.
#
# DESCRIPTION:
#
#	This script reads in a Device Group ID, then removes the ASAM profiles for the devices in that group, 
#   ensuring it is removed it then applies the SAM profile and then removes that one and re-applies the SAM
#   the whole time making sure all the deivces in that deivce group are following suit.
#
# CAUTION: if a device is unresponsive then it will get stuck in a loop waiting to confirm the remove.
#   We can break the loop and move to the next device with the letter: b. The serial number will be listed for every device.
#
# REQUIREMENTS:
#
#   An ASAM profile for each device group being used. The scope will be wiped for each configuration profile and the 
#    device group will be the only one in the scope for the ASAM profile at the end
#
####################################################################################################
#
# HISTORY
#
#	Version: 1.2
#
#   Release Notes:
#	- Error handling for bad credentials, bad url and bad filepath
#   - Functionality to take a deivce out of single app mode, ensure app has beed updated, allow update and put back in single app mode
#   - The ablity to stop waiting if desired
#
####################################################################################################
#
# Jamf|PRO connection information entry
#
####################################################################################################

#Username Entry
echo ""
echo "Please enter the Jamf Pro API username: "
read apiUser

echo ""
#Password Entry 
echo "Please enter the username password "
read -s apiPass
echo ""

#URL of Jamf Pro server entry
echo "Please enter the Jamf Pro URL including the port ex. https://jamfit.jamfsw.com:8443 if we are locally hosted"
echo "No port needed for cloud hosted instances ex. https://jamfit.jamfsw.com" 
read url
echo ""

# Removal of trailing slash if found in url
if [ $(echo "${url: -1}") = "/" ]; then
	url=$(echo $url | sed 's/.$//')
fi

# Alowing user to break loops with a letter b keystroke 
keystrokeBreak(){
total=20  # total wait time in seconds
zero=0  # counter
while [ ${zero} -lt ${total} ] ; do
    tlimit=$(( $total - $zero ))
    read -s -n1 -t1 breakLoop
    zero=$((zero+1))
if [  "$breakLoop" = 'b' ] ; then
    echo "\nLoop aborted by user"
    break 2
else
    echo "\rTrying again in ${tlimit} second(s) \c"
fi
done
return
}

####################################################################################################
# 
# Ensuring we can connect to the Jamf|PRO API
#
####################################################################################################

test=$(/usr/bin/curl --fail -ksu "$apiUser":"$apiPass" "$url/JSSResource/mobiledeviceconfigurationprofiles" -X GET)
status=$?
if [ $status -eq 6 ]; then
	echo ""
	echo "The Jamf Pro URL is reporting an error. Please try again." 
	echo "If the error persists please check permissions and internet connection" 
	echo ""
	exit 99
elif [ $status -eq 22 ]; then
	echo ""
	echo "Username and/or password is incorrect."
	echo "If the error persists please check permissions and internet connection" 
	echo ""
	exit 99
else
    echo ""
    echo "Connection test successful"
fi

####################################################################################################
# 
# App Name, App version, Group ID, ASAM and SAM profile ID entry
#
####################################################################################################

#App Name Entry 
echo "Please enter the exact name of the APP "
echo "The name is case-sensitive:"
read appName
echo ""

#App version Entry 
echo "Please enter the full version of the APP "
echo "The short version will not work:" 
read appVersion
echo ""

#Group ID Entry 
echo "Please enter the id of the Device Group: "
read groupID
echo ""

#ASAM Entry 
echo "Please enter the id of the ASAM profile: "
read asamProfile
echo ""

# SAM Entry 
echo "Please enter the id of the SAM profile: "
read samProfile
echo ""

####################################################################################################
# 
# Making the XML's for the API puts
#
####################################################################################################

addDevicesXML="<configuration_profile><scope><mobile_device_groups><mobile_device_group><id>$groupID</id></mobile_device_group></mobile_device_groups></scope></configuration_profile>"

removeAllDevicesXML="<configuration_profile><scope><mobile_devices></mobile_devices></scope></configuration_profile>"

####################################################################################################
# 
# Defining varible temp filepaths
#
####################################################################################################

tempdir=`basename $0`
csvFile1=`mktemp -t ${tempdir}` || exit 1 # CSV file used as our counter and device serial number variable for our CURL loop
csvFile2=`mktemp -t ${tempdir}` || exit 1 # CSV file used as our counter and device id variable for our CURL loop
XMLfile1=`mktemp -t ${tempdir}` || exit 1 # XML file used to create device id and serial variables
XMLfile2=`mktemp -t ${tempdir}` || exit 1 # XML file used to create app name variables
XMLfile3=`mktemp -t ${tempdir}` || exit 1 # XML file used to check the ASAM profile
XMLfile4=`mktemp -t ${tempdir}` || exit 1 # XML file used to check the SAM profile
    if [ $? -ne 0 ]; then
    echo "$0: Can't create temp file, exiting..."
    exit 1
    fi
           
####################################################################################################
#
# Function definitions for various API calls and variable definitions
#
####################################################################################################

#Setting file delimeter

IFS=$'\n'

# Serial Number collection function

getSerialNumbers(){
/usr/bin/curl -sk -u $apiUser:$apiPass -H "Accept: application/xml" $url/JSSResource/mobiledevicegroups/id/$groupID | xmllint --format - --xpath /mobile_device_group/mobile_device/serial_number > $XMLfile1
/bin/cat $XMLfile1 | grep 'serial_number' | cut -f2 -d">" | cut -f1 -d"<" > $csvFile1
deviceCount=`cat $csvFile1 | awk -F, '{print $1}'`
return
}

# App Name Function and getting rid of any whitespace for a better comparision

appName_NO_WHITESPACE="$(echo "${appName}" | tr -d '[:space:]')" # Kill all the whitespace
appNameComparison(){
appCheck=$(/usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Accept: application/xml" "$url/JSSResource/mobiledevices/serialnumber/$i/subset/mobiledeviceapplications" -X GET | xmllint --nowarning --format - --xpath '/mobile_device/applications/application' 2>/dev/null | grep $appName | sed 's/application//g' | sed 's/_name//g' | sed 's/<>//g'| sed 's/<\/>//g' | sed 's/ //g')
return
}

# App Version Function and getting rid of any whitespace for a better comparision

appVersion_NO_WHITESPACE="$(echo "${appVersion}" | tr -d '[:space:]')" # Kill all the whitespace
appVersionComparison(){
appVersionCheck=$(/usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Accept: application/xml" "$url/JSSResource/mobiledevices/serialnumber/$i/subset/mobiledeviceapplications" -X GET | xmllint --nowarning --format - --xpath '/mobile_device/applications/application' 2>/dev/null | grep $appVersion | sed 's/application_version//g' | sed 's/<>//g'| sed 's/<\/>//g' | sed 's/ //g') 
return
}

# Getting the device ID's from a device group

deviceID=$(curl -ksu $apiUser:$apiPass -X GET -H 'accept: text/xml' $url/JSSResource/mobiledevicegroups/id/$groupID | xpath '/mobile_device_group/mobile_devices/mobile_device/id' 2>/dev/null | sed 's/<id//g' | sed 's/>//g' | sed 's/<\/id/,/g')

# Update inventory function deleting trailing comma

UpdateInventory(){
    if [ $(echo "${deviceID: -1}") = "," ]; then
	deviceID=$(echo $deviceID | sed 's/.$//')
fi
/usr/bin/curl -ksu "$apiUser":"$apiPass" "$url/JSSResource/mobiledevicecommands/command/UpdateInventory/id/$deviceID" -X POST 
return
}

# Getting the profile names from the API

asamProfileNameXML=$(/usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Accept: application/xml" "$url/JSSResource/mobiledeviceconfigurationprofiles/id/$asamProfile" -X GET | xmllint --nowarning --format - --xpath /configuration_profile/general/name > $XMLfile3)
asamProfileName=`/bin/cat $XMLfile3 | grep -s 'name' | cut -f2 -d">" | cut -f1 -d"<" | head -n 1`

samProfileNameXML=$(/usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Accept: application/xml" "$url/JSSResource/mobiledeviceconfigurationprofiles/id/$samProfile" -X GET | xmllint --nowarning --format - --xpath /configuration_profile/general/name > $XMLfile4)
samProfileName=`/bin/cat $XMLfile4 | grep -s 'name' | cut -f2 -d">" | cut -f1 -d"<" | head -n 1`

# Cheking the device inventory for the profile

profileCheck(){
profileCheckXML=$(/usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Accept: application/xml" "$url/JSSResource/mobiledevices/serialnumber/$i/subset/mobiledeviceconfigurationprofiles" -X GET | xmllint --nowarning --format - --xpath /mobile_device/configuration_profiles/configuration_profile/display_name 2>/dev/null > $XMLfile2) 
return
}

# ASAM profile breakdown searching for the profile in the file created by profileCheck()

asamProfileNameSearch(){
asamProfileNameSearch=`/bin/cat $XMLfile2 | grep -s 'display_name' | cut -f2 -d">" | cut -f1 -d"<" | grep -s $asamProfileName`
}

# SAM profile breakdown searching for the profile in the file created by profileCheck()

samProfileNameSearch(){
samProfileNameSearch=`/bin/cat $XMLfile2 | grep -s 'display_name' | cut -f2 -d">" | cut -f1 -d"<" | grep -s $samProfileName`
}

####################################################################################################
# 
# Checking that the desired app version is installed
#
####################################################################################################

getSerialNumbers
UpdateInventory
    echo ""
    echo "Updating Inventory for Device IDs: $deviceID"
    echo ""
for i in ${deviceCount}; do
tryCounter=0
appNameComparison
appVersionComparison
    echo ""
    echo "Looking for App $appName Version: $appVersion"
        until [ "$appCheck" = "$appName_NO_WHITESPACE" ] && [ "$appVersionCheck" = "$appVersion_NO_WHITESPACE" ]; do
        tryCounter=$((tryCounter+1))
        echo ""
	    echo "Waiting for app to be confirmed as updated. Trying for Device # $i"
	    echo "Try Count: $tryCounter"
appNameComparison
appVersionComparison
echo "Press b to break the loop and move on."
keystrokeBreak
        done
    echo ""
	echo "Application: $appName Version: $appVersion -- has been confirmed installed on Device # $i"
	echo ""
done 

####################################################################################################
# 
# Removing scope for the ASAM profile
#
####################################################################################################

    echo "The ASAM Profile name has been set to: "$asamProfileName""
    echo ""
    /usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Content-Type: text/xml" -d "$removeAllDevicesXML" "$url/JSSResource/mobiledeviceconfigurationprofiles/id/$asamProfile" -X PUT
	echo ""
	echo "Profile: $asamProfileName's scope has been cleared"
	echo ""

####################################################################################################
# 
#  Ensuring the ASAM profile is removed with sleep in loop to wait 20 seconds before asking again
#
#  Sending out update Inventory commands to get the profile removed
#
####################################################################################################

    echo "Updating Inventory for Device IDs: $deviceID"
    UpdateInventory
for i in ${deviceCount}
do
tryCounter=0
profileCheck
asamProfileNameSearch
    echo ""
    echo "Looking for profile: $asamProfileName"
    echo ""
        until [ "$asamProfileNameSearch" = "" ]; do
        tryCounter=$((tryCounter+1))
        echo ""
	    echo "Waiting for profile to be confirmed as removed. Trying for Device # $i"
	    echo "Try Count: $tryCounter"
profileCheck
asamProfileNameSearch
echo "Press b to break the loop and move on."
keystrokeBreak
        done
    echo ""
	echo "Profile: "$asamProfileName" -- has been confirmed removed from Device # $i"
	echo ""
    rm -f $XMLfile2
done 

####################################################################################################
# 
# Scoping the SAM profile to the device group
#
####################################################################################################

    /usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Content-Type: text/xml" -d $addDevicesXML "$url/JSSResource/mobiledeviceconfigurationprofiles/id/$samProfile" -X PUT
    echo ""
	echo "Device Group-- ID: $groupID -- has been added to the scope of SAM Profile $samProfile"
	echo ""
    echo "Press b to stop waiting and move on."
    keystrokeBreak

####################################################################################################
# 
# Ensuring the SAM profile is installed with sleep in loop to wait 20 seconds before asking again
#
# Sending out update Inventory commands to get the profile removed
#
####################################################################################################

    echo ""
    echo "The SAM Profile name has been set to: $samProfileName"
    echo ""
    echo "Updating Inventory for Device IDs: $deviceID"
    UpdateInventory
for i in ${deviceCount}
do
tryCounter=0
profileCheck
samProfileNameSearch
    echo ""
    echo "Looking for profile $samProfileName"
    echo ""
        until [ "$samProfileName" = "$samProfileNameSearch" ]; do
        tryCounter=$((tryCounter+1))
        echo "$samProfileNameSearch"
	    echo "Waiting for profile to be confirmed as added. Trying for Device # $i"
	    echo "Try Count: $tryCounter"
profileCheck
samProfileNameSearch
echo "Press b to break the loop and move on."
keystrokeBreak
        done
	echo "Profile: "$samProfileName" -- has been confirmed added to Device # $i"
	echo ""
    rm -f $XMLfile2
done

####################################################################################################
# 
# Removing scope for the SAM profile
#
####################################################################################################

    echo ""
    /usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Content-Type: text/xml" -d "$removeAllDevicesXML" "$url/JSSResource/mobiledeviceconfigurationprofiles/id/$samProfile" -X PUT
	echo ""
	echo "Profile: "$samProfileName"-- has had its scope cleared"
	echo ""
    echo "Press b to stop waiting and move on."
    keystrokeBreak

####################################################################################################
# 
# Ensuring the SAM profile is removed with sleep in loop to wait 20 seconds before asking again
#
#  Sending out update Inventory commands to get the profile removed
#
####################################################################################################

    echo ""
    echo "Updating Inventory for Device IDs: $deviceID"
    UpdateInventory
    echo ""
for i in ${deviceCount}; do
tryCounter=0
profileCheck
samProfileNameSearch
    echo ""
    echo "Looking for profile: $samProfileName"
    echo ""
        until [ "$samProfileNameSearch" = "" ]; do
        tryCounter=$((tryCounter+1))
	    echo "Waiting for profile to be confirmed as removed. Trying for Device # $i"
	    echo "Try Count: $tryCounter"
profileCheck
samProfileNameSearch
        echo "Press b to break the loop and move on."
keystrokeBreak
        done
	echo "Profile: "$samProfileName" -- has been confirmed removed from Device # $i"
	echo ""
    rm -f $XMLfile2
done

####################################################################################################
# 
# Scoping the ASAM profile to device group
#
####################################################################################################

    echo ""
    /usr/bin/curl -ksu "$apiUser":"$apiPass" -H "Content-Type: text/xml" -d "$addDevicesXML" "$url/JSSResource/mobiledeviceconfigurationprofiles/id/$asamProfile" -X PUT
    echo ""
    echo "Device Group-- ID: "$groupID" -- has been added to the scope of ASAM Profile "$asamProfile""
    echo ""
    echo "The device group is back the scope of the ASAM Profile and we are all set!"
    echo ""
    rm -fR $tempdir
exit 0
# End of inHouseAppUpdate.sh 