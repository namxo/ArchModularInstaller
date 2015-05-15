#!/bin/bash
set -u
set -e

doFullList_ret=""
function doFullList {
	xargs -d ' ' -n 6 echo < "$1" > "${1}_pretty"
	keylayoutsnums=$(wc -l < "${1}_pretty")
	tmpforloop=0
	while [[ $tmpforloop -lt $keylayoutsnums ]]; do
		tmpforloop=$tmpforloop+1;
		select doFullList_ret in Search Custom $(awk "NR==$tmpforloop" < "${1}_pretty") More; do
			if [[ "$doFullList_ret" == "More" ]]; then
				break
			elif [[ "$doFullList_ret" == "Custom" ]]; then
				echo -n "Manually enter value: "
				read doFullList_ret
				return
			elif [[ "$doFullList_ret" == "Search" ]]; then
				echo -n "Enter query: "
				read query
				xargs -d ' ' -n 1 echo < "$1" | grep "$query" | tr '\n' ' ' > "${1}_pretty"
				cp "${1}_pretty" "$1"
				doFullList "$1"
				return
			fi
			return
		done
	done
	if [[ "$doFullList_ret" == "More" ]]; then
		doFullList "$1"
	fi
}

echo "Arch Installer"
echo
find /usr/share/kbd/keymaps/ -type f -printf '%f ' > /var/tmp/inst_dfl
echo "---- Step 1 ---- Select Keymap ----"
doFullList "/var/tmp/inst_dfl"
loadkeys "$doFullList_ret"
keymap="$doFullList_ret"


keeplooping="Yes"
while [[ "$keeplooping" == "Yes" ]]; do
	echo
	echo "---- Step 2 ----   Partition   ----"
	echo "Step 2 and 3 repeats until you have finished all partitions."
	echo "*MAKE SURE TO SET THE BOOTABLE FLAG WITH a ON THE BOOT/ROOT PARTITION*"
	echo
	echo "Skip" > /var/tmp/inst_dfl
	for disknod in "sd" "vd" "hd"; do
		find /dev -name "${disknod}*[^0-9]" >> /var/tmp/inst_dfl
	done
	mv /var/tmp/inst_dfl /var/tmp/inst_dfl_item
	tr '\n' ' ' < /var/tmp/inst_dfl_item > /var/tmp/inst_dfl
	doFullList "/var/tmp/inst_dfl"
	disks=$(cat /var/tmp/inst_dfl)
	rm /var/tmp/inst_dfl /var/tmp/inst_dfl_item
	if [[ "$doFullList_ret" != "Skip" ]]; then
		echo "------------"
		fdisk "$doFullList_ret"
		echo "------------"
	fi

	echo
	echo "---- Step 3 ----     Format    ----"
	echo -n "" > /var/tmp/inst_dfl
	for disknod in "sd" "vd" "hd"; do
		 find /dev -name "${disknod}*[0-9]"  >> /var/tmp/inst_dfl
	done
	mv /var/tmp/inst_dfl /var/tmp/inst_dfl_item
	tr '\n' ' ' < /var/tmp/inst_dfl_item > /var/tmp/inst_dfl
	doFullList "/var/tmp/inst_dfl"
	disknod="$doFullList_ret"
	echo "LVM Swap $(find /usr/bin/ -name 'mkfs.*' -printf '%f ')" > /var/tmp/inst_dfl
	doFullList "/var/tmp/inst_dfl"
	if [[ "$doFullList_ret" == "LVM" ]]; then
		echo "------------"
		pvcreate "$disknod"
		echo "------------"
		echo -n "Create new volume group? (y/<existing group name) "
		read mkvg
		if [[ "$mkvg" == "y" ]]; then
			echo -n "Volume Group Name? "
			read vgname
			echo "------------"
			vgcreate -n "$vgname" "$disknod"
			echo "------------"
			echo -n "Logical Volume Name? "
			read lvname
			echo -n "Size (*G)? "
			read lvsize
			echo "------------"
			lvcreate -L "$lvsize" -n "$lvname" "$vgname"
			echo "------------"
		else
			echo "------------"
			vgextend "$mkvg" "$disknod"
			echo "------------"
		fi
	elif [[ "$doFullList_ret" == "Swap" ]]; then
		mkswap "$disknod"
	else
		echo "------------"
		"$doFullList_ret" "$disknod"
		echo "------------"
		echo
		echo "Mount point?"
		select mpoint in / /home /boot; do
			mkdir -p "/mnt/system$mpoint"
			mount "$disknod" "/mnt/system$mpoint"
			break;
		done
	fi
	echo
	echo "Do another partition?"
	select keeplooping in Yes No; do
		break;
	done
done


echo
echo "---- Step 4 ----   Configure   ----"

echo -n "Hostname? "
read hstnme

echo -n "Install development tools (y/n)? "
read devtools
if [[ "$devtools" == "y" ]]; then
	devtools="-devel"
else
	devtools=""
fi

echo
echo "Install bootloader on:"
echo "(You most likely want the disk that /boot resides on, or it's LVM physical volume)"
echo "$disks" | sed 's/Skip//' > /var/tmp/possibledevs
doFullList "/var/tmp/possibledevs"
bootloader_install="$doFullList_ret"

echo
echo "Select time zone"
curdir="$PWD"
cd /usr/share/zoneinfo
find ./ -type f -printf '%p ' > /var/tmp/inst_dfl
cd "$curdir"
doFullList "/var/tmp/inst_dfl"
tz="$doFullList_ret"

echo
echo "Select locale to use"
grep -E '(.+) UTF-8' /etc/locale.gen | sed 's/# *//g' | cut -d' ' -f1 | tr '\n' ' ' > /var/tmp/inst_dfl
doFullList "/var/tmp/inst_dfl"
locale="$doFullList_ret"

pacstrap /mnt/system/ base$devtools
genfstab /mnt/system/ > /mnt/system/etc/fstab
> /mnt/system/root/stage2.sh << EOF
#!/bin/bash
set -u
set -e
#CONFIG START
EOF
echo "bootloader_install=\"$bootloader_install\"" >> /mnt/system/root/stage2.sh
echo "tz=\"$tz\"" >> /mnt/system/root/stage2.sh
echo "locale=\"$locale\"" >> /mnt/system/root/stage2.sh
echo "hstnme=\"$hstnme\"" >> /mnt/system/root/stage2.sh
echo "keymap=\"$keymap\"" >> /mnt/system/root/stage2.sh
>> /mnt/system/root/stage2.sh << EOF
#CONFIG END
#--- The script below is automatically generated from stage2.sh ---
STAGE2MARKER

EOF
chmod +x /mnt/system/root/stage2.sh
arch-chroot /mnt/system/ /root/stage2.sh
echo "All done! Hit enter to reboot the system."
read whyareyoulookingatthis
shutdown -r now