#!/bin/bash
#
# mkpibv.sh
# build a GPT partitioned SD card for Arch Linux on the Raspberyy Pi
#

if [ $UID -ne 0 ]; then
    echo "Superuser privileges are required to run this script."
    echo "e.g. \"sudo $0\""
    exit 666
fi
#
TDN=/dev/sdz			#Target Device Name (z is probably bogus)
TDP=/mnt/tgt			#Target Disk Partition
TDS=0				#Target Disk Size
TAN=rpi-2			#Target Archetecture Name
PIN=pial			#Pi Image Name base
PBT=boot.tar			#Pi boot tape archive
PBZ=$PBT.xz			#Pi boot Zip
PRT=root.tar			#Pi root tape archive
PRZ=$PRT.xz			#Pi root Zip
PSD=/aaa/data/$PIN 		#Pi Source directory
PTF=/tmp/rpi1			#Pi temporary file
DTF=/tmp/rpi2			#Dialog temporary file
SDP="Flash"			#SD Card pattern
SRL=http://co.us.mirror.archlinuxarm.org/os/	#Source Resource Locator
SRL=http://os.archlinuxarm.org/os/	#Source Resource Locator

export	DIALOG_OK=7		#overide default of 0 

#functions to remove working files

declare -a on_exit_items

function on_exit()
{
        for i in "${on_exit_items[@]}"
        do
#               echo "on_exit: $i"
                eval $i
        done
}

function add_on_exit()
{
        local n=${#on_exit_items[*]}
        on_exit_items[$n]="$*"
        if [[ $n -eq 0 ]]; then
        echo "Setting on exit cleanup trap"
        trap on_exit EXIT
        fi
}

add_on_exit cd /home/$SUDO_USER		#return to user home
add_on_exit rm -f $PTF			#delete Pi Temporary Files


mkdir -p ~/$PIN				#create Pi Image Name directory
cd ~/$PIN				#position for download

# find candidate target devices

parted --list  >$PTF 2>/dev/null		#get all the sd devices
ex -c "g/$SDP/j"  -c wq $PTF		#join the device string and the space lines
add_on_exit rm -f $DTF			#make sure Dialog Temp File is removed
grep $SDP $PTF | tr " " ":" | cut --delimiter=: -f 3- > $DTF
					#pick out the device space
TDS=`cut --delimiter=: -f 8 $DTF | cut --delimiter=. -f 1`
cp $DTF $PTF
DLC=`wc --lines $PTF | cut --bytes=1-2`	#Device List Counts
TDN=`cut --delimiter=: -f 6 $PTF`
if [ 1 -lt $DLC ];
then				#we have more than 1 target, prep/show dialog
				#tweak PTF [Pi Temp File] with list of devices
	ex -c "g/^/s//\"/" -c "g/$/s//\" off/" -c "g/[0-9]/s///g" -c wq $PTF

				#save user choice of Target Device Name
	TDN=$(dialog --noitem --colors --title \
	"\Z1\Zr\Zb Found more than 1 candidate SD/MMC device " \
	--radiolist "Choose with spacebar:" $(( 9 + $DLC )) 60 5 \
	`cat $PTF` 3>&1 1>&2 2>&3)
fi			#?-more than 1 device?
if [ 0 -eq $DLC ];
then
	echo -e "Device List Count is ($DLC)"
	echo -e " Failure to discover a candidate SD/MMC device, exiting "
	exit 11

fi
if [ -n "$TDN" ];	#?-was dialog cancelled?
then			#n-dialog returned a usable string
#	parted -s $TDN print >>$DTF
	sgdisk -p $TDN | grep dev >$DTF
	DUR=$?				#save result code

	if [ 0 -lt $DUR ]; then exit 222; fi	#bail when sgdisk fails

#		--yesno "Use $TDN as image destination?\n\n
	dialog	--trace /tmp/junk --colors --defaultno \
		--title "\Z1\Zr Only 1 candidate device found " \
		--yesno "Use $TDN as image destination?\n\n
		\Z1\ZrAll existing data will be destroyed" 8 55 
        DUR=$?                          #save result code
	if [ $DIALOG_OK -eq $? ];	#?-Use Target Device?
	then				#y-Use Target Device?
		echo "building to $TDN, this will take a while"
		echo "please be patient"
	else
		echo result:$? no go 	#n-Use Target Device?
	fi				#?-Use Target device?
else
	echo "no device selected, copy aborted!"
fi				#y-dialog cancelled?


STEP="step2"
if [ true -o -e $STEP ];			#?-do this step?
then					#y-create partitions
	TDS=`echo $TDS | sed 's/..$//'`
	let TDS="TDS/1024"
	let TSZ[1]="TDS/1"
	let TSZ[2]="TDS/2"
	let TSZ[3]="TDS/4"
	let TSZ[4]="TDS/10"
	let TSZ[5]="2"
	let TSZ[6]="1"
	let SZI=0
	declare -a DSZ
	for SZ in ${TSZ[@]}
	do
		if [ 2 -lt $SZ ];	#we have 1 & 2 GB covered manually
		then
			SZI=$(expr $SZI + 1)
			DSZ[$SZI]=$SZ
		fi
	done
	SZI=$(expr $SZI + 1)
	DSZ[$SZI]=2
	SZI=$(expr $SZI + 1)
	DSZ[$SZI]=1
	DTS="\Z1\Zb\Zr How Much of $TDS GB to use?"
	echo -e -n "--cr-wrap --no-shadow " >$DTF
	echo -n ' --radiolist "' >>$DTF
	echo    "     Select space allocation to use" >>$DTF
	echo    "     for the root partition" >>$DTF
	echo -n "(Use ARROWS to move, SPACEBAR to select)" >>$DTF
	echo -n '" 16 45' >>$DTF
	echo " $SZI" >>$DTF
	let SZI=0
	DSC="on"
	DSA=" [REMAINING SPACE]"
	for SZ in ${DSZ[@]}
	do
		SZI=$(expr $SZI + 1)
		 if [ "$SZ" = "1" ]; then DSA="  [NOT RECOMMENDED]"; fi
		echo -n -e "$SZI \"$SZ GB$DSA\" $DSC " >>$DTF
		DSC="off"
		DSA=""
	done
	echo "" >>$DTF
	dialog	--colors \
		--title \"$DTS\" \
		--file $DTF 2>$PTF	#ask the user, save in $PTF file
	DUR=$?					#save result code
	if [ $DIALOG_OK -eq $DUR ];		#?-Use Target Device?
	then					#y-Use Target Device?
		SZI=`cat $PTF`
		SZI=$(expr 0 + $SZI)
		echo PTF is `cat $PTF`
		echo SZI is $SZI
		DUR=${DSZ[$SZI]}
		echo DUR is $DUR
		echo "building 160 MB boot and $DUR GB root"
		echo " to $TDN, this will take a while, please be patient"
	else
		echo result=$DUR:no go 	#n-Use Target Device?
	fi				#?-Use Target device?
else
	echo $STEP skipped
fi					#y-step?

STEP="step3"
if [ -e $STEP -a -n "$TDN" ];		#?-do this step?
then					#y-fetch tar files
	PIZ="";
	if [ -e "$PIZ" ];
	then
		echo $PIZ compressed image exists, skipping fetch.
	else
		echo fetching $PIZ.

		wget --progress=bar $SRL/$PIN/$PIF/$PIZ
	fi	#already have an image
else
	echo $STEP skipped
fi					#step exists

STEP="step4"
if [ -e $STEP ];			#?-do this step?
then					#y-create partitions
#
# modify the target device
#
echo creating boot and root partitions on $TDP

# We assume the target disk uses a GPT partition table
# while, according to the man page. sgdisk shoud detect an MBR table
# and perform the requested operation correctly, that has not been tested
#
TVN=rpial				#Target Volume Name
TOLD=/tmp/$TVN-old			#save current partition layout
TNEW=/tmp/$TVN-new			#save revised layout
PAL="$TDN unit s print"			#parted arg list

sgdisk $TDN --zap-all
parted -s --machine $PAL >$TOLD
TVN=$PIN-boot				#Target Volume Name
sgdisk --new=0:0:+160M $TDN		#160M (128+32) boot
parted -s --machine $PAL >$TNEW
TDP=`diff -e $TOLD $TNEW | cut -s -d ":" -f 1`
sgdisk --change-name=$TDP:$TVN --typecode=$TDP:0700 -p $TDN

TVN=$PIN-root				#Target Volume Name
parted -s --machine $PAL >$TOLD
sgdisk --new=0:0:0 $TDN			#use the rest of the space
parted -s --machine $PAL >$TNEW
TDP=`diff -e $TOLD $TNEW | cut -s -d ":" -f 1`
#sgdisk --change-name=$TDP:$TVN --typecode=$TDP:8300 -p $TDN
mkfs.btrfs --force --label $TVN $TDN$TDP
btrfs fi sho grep $TVN
btrfs fi sho
TUID=`btrfs fi sho | cut -s -d " " -f 3`
					#make a MBR partition table for the PI
else
	echo $STEP skipped
fi					#y-step?
