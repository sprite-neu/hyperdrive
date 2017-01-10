#!/bin/bash

#Global Variables 
SSH_Password="cs8674-cloudmanager" # This is the SSH password for the management server
MQTT_Client_Directory="/home/cloudmanager/mqttclient/" # Directory where the mqttclient executable exists
Script_Directory="/home/cloudmanager/Cloud-Deployment-Utility/CS8674-Shell-Scripts/" # Directory where the script exists
IP_Address=`ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{print $1}'` # Get the IP address of this client. This will work only when the eth0 interface exists. Other interfaces? Multiple NICs?
Management_Server_IP="192.168.1.42" # Management Server IP address or domain name


XEN_HASH_ORIGINAL="ca65a79788e79166c52fff8edd26e34a4c2cd251c7810b7d43d46b9b48bcc33d"
KVM_CLOUDSTACK_HASH_ORIGINAL="3b7524125ae3c1fc8c16f310c8c685f1e025d0f6bcda93fbe79f035dedc6f9bb"


${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/OnlineStatus" -m "$IP_Address"
${MQTT_Client_Directory}mqttcli sub --conf ${MQTT_Client_Directory}server.json -t "cs8674/DeployApproved" > ${MQTT_Client_Directory}approval.txt

Approval=`tac ${MQTT_Client_Directory}approval.txt | egrep -m 1 .`


#Fuction to handle error and graceful exit 
handle_error () {   
	if [ "$?" != "0" ]
	  then
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Some error occured. Aborting installation. Please SSH into the Debian Live system to debug. Logs can be found at /var/log/"
		exit 1
	fi
}



if [ "$Approval" = 'Deploy-'${IP_Address} ]
	then
	${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Installation started...."

	# The Hypervisor variable will contain the selected cloud configuration fetched from the cloud_configuration.txt file 
	# from the management server. Device_ID variable will contain the hard drive identifier ex. /dev/sda
	# And Reboot_Status will determine whether the user wants to reboot this Debian Live OS after deployment

	Hypervisor=`sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "cat /home/cloudmanager/cloud_configuration.txt" | grep hyp_name -m 1 | grep -Po 'hyp_name=\K[^:]+'`
	Reboot_Status=`sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "cat /home/cloudmanager/cloud_configuration.txt" | grep reboot_status -m 1 | grep -Po 'reboot_status=\K[^:]+'`     
	Device_ID=`fdisk -l | grep Disk -m 1 | grep -Po 'Disk \K[^:]+'`

	${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: $Hypervisor hypervisor was selected by user"
	${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: The device id selected by user is $Device_ID"
		 
	# Partition the disk according to value of Hypervisor
	if [ "$Hypervisor" = 'XENSERVER' ]
		then
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Checking the integrity of $Hypervisor image........"

		#First,fetch the sha256 hashes of cloned images from the management server. Then ,Verify the integrity of the clone images. Abort if integrity check fails. 		
		XEN_HASH_FETCHED=`sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "sha256sum /home/cloudmanager/xen.iso" | cut -d ' ' -f1`
		handle_error
		
		if [ "$XEN_HASH_ORIGINAL" = "$XEN_HASH_FETCHED" ]
			then 
			:
		else 
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: The integrity of the installation image cloud not be verfied. Aborting installation. You can login to the Debian system using SSH to debug. Logs can be found at /var/log/"
		exit 1 
		fi
		
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!" 
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Creating partitions with fdisk... "

		# This creates a new GPT partition table and creates 3 partitions
		# 1st and 2nd partitions are 4GB and 3rd is an lvm partition which extends to the end of the disk
		fdisk $Device_ID < ${Script_Directory}fdisk_xen.input
		handle_error

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!" 
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Formatting partition with ext3..." 
		
		# Format the first partition using ext3
		mkfs.ext3 ${Device_ID}1 < ${Script_Directory}mkfs_xen.input
		handle_error

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Setting appropariate flags on partitions..."

		# Parted is used to set flags on the partitions
		# Flags for 1st partition -> legcy_boot, msftdata
		# Flags for 2nd partition -> msftdata
		# Flags for 3rd partition -> lvm
		parted $Device_ID < ${Script_Directory}parted_xen.input
		handle_error

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Fetching xenserver images and writing to disk...."	
		
		# This fetches the XenServer cloned image using ssh from the management server and restores it to the 1st partition
		# using dd
		sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "dd if=/home/cloudmanager/xen.iso" | dd of=${Device_ID}1 bs=10M
		handle_error

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Installing MBR...."

		# This installs the MBR on the device
		dd bs=440 conv=notrunc count=1 if=/usr/lib/syslinux/mbr/gptmbr.bin of=$Device_ID
		handle_error		
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"


	elif [ "$Hypervisor" = 'KVM' ] || [ "$Hypervisor" = 'KVM-CLOUDSTACK' ] 
		then
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Creating partitions with fdisk...."	

		# This creates a new DOS partition table and creates 1 partition of 6GB
		fdisk $Device_ID < ${Script_Directory}fdisk_kvm.input
		handle_error

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"	
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Formatting the parition to ext4...."	

		# This formats the 1st partition using ext4
		mkfs.ext4 ${Device_ID}1 < ${Script_Directory}mkfs_kvm.input
		handle_error

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"

		# This block of code fetches the kvm or kvm with cloudstack cloned images from the manegenment server and
		# restores them to the 1st partition using dd
		if [ "$Hypervisor" = 'KVM' ]
			then
			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Fetching KVM clone...."

			sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "dd if=/home/cloudmanager/ubuntu-kvm.iso" | dd of=${Device_ID}1 bs=10M
			handle_error
			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"

		elif [ "$Hypervisor" = 'KVM-CLOUDSTACK' ]
			then
			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Checking the integrity of $Hypervisor image........"

			#Fetch the sha256 hashes of cloned images from the management server. Then ,Verify the integrity of the clone images. Abort if integrity check fails. 
			KVM_CLOUDSTACK_HASH_FETCHED=`sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "sha256sum /home/cloudmanager/ubuntu-kvm-cloudstack.iso" | cut -d ' ' -f1`
			handle_error

			if [ "$KVM_CLOUDSTACK_HASH_ORIGINAL" = "$KVM_CLOUDSTACK_HASH_FETCHED" ]
				then 
				:		
			else 
			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: $Hypervisor The integrity of the installation image cloud not be verfied. Aborting installation. You can login to the Debian system via SSH to debug. Logs can be found at /var/log/"
			exit 1 
			fi

			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Fetching KVM-CLOUDSTACK clone...."

			sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "dd if=/home/cloudmanager/ubuntu-kvm-cloudstack.iso" | dd of=${Device_ID}1 bs=10M
			handle_error
			${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		fi

		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Paritioning disks with fdisk..."

		# This deletes the 1st partition and creates a new one of 100GB
		# It then creates a swap partition of 5GB. This can be changed in fdisk_kvm_extend.input to create partitions of 
		# different sizes as per your requirements
		fdisk $Device_ID < ${Script_Directory}fdisk_kvm_extend.input
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Setting appropariate flags on partitions.."

		# This sets the boot flag on the first partition
		parted $Device_ID < ${Script_Directory}parted_kvm.input
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Setting swap and updating fstab entries..."

		# Make partition number 5 as swap and store its UUID in the UUID variable
		UUID=`mkswap ${Device_ID}5 | grep UUID= | cut -d '=' -f2` 
		handle_error
		# Create directory to mount the first partition. We need to change the swap partition UUID in /etc/fstab
		mkdir /mnt/device
		handle_error
		# We will now mount the first partition to update the swap UUID in /etc/fstab
		mount ${Device_ID}1 /mnt/device
		handle_error
		# Update UUID of swap partition
		sed -i -e ':a;N;$!ba;s/UUID=[A-Fa-f0-9-]*/UUID=$UUID/3' /mnt/device/etc/fstab
		handle_error
		# Unmount the 1st partition
		umount ${Device_ID}1
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Checking the parition for resize operation...."	
		
		# Checks the first partition before resizing
		e2fsck -p -f ${Device_ID}1
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Resizing the partition...."	
		
		# Resizes the 1st partition to 100 GB so the dd restored clone of 6 GB can use all of the 100 GB
		resize2fs ${Device_ID}1
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Installing the MBR....."	

		
		# Install the MBR
		sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "dd if=/home/cloudmanager/mbr.bin" | dd of=$Device_ID bs=446 count=1
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Installing GRUB Bootloader....."	

		# We will now mount the first partition to install GRUB on the MBR
		mount ${Device_ID}1 /mnt/device
		handle_error
		# Install GRUB Bootloader on the MBR
		grub-install --boot-directory=/mnt/device/boot ${Device_ID}
		handle_error
		# Unmount the 1st partition
		umount ${Device_ID}1
		handle_error
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "Done!"
	fi

	${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: Congrats ! The process was completed successfully."

	# Store the syslog on the management server
	cat /var/log/syslog | sshpass -p $SSH_Password ssh -o StrictHostKeyChecking=no cloudmanager@${Management_Server_IP} "cat > /home/cloudmanager/deployment_log/syslog-$IP_Address.txt"
	handle_error
	if [ "$Reboot_Status" = 'YES' ]
		then
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/InstallStatus" -m "$IP_Address: The system will now reboot"
		${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/OfflineStatus" -m "$IP_Address"
		reboot
	fi
else
	${MQTT_Client_Directory}mqttcli pub --conf ${MQTT_Client_Directory}server.json -t "cs8674/OfflineStatus" -m "$IP_Address"
	poweroff
fi
 
