#!/bin/bash

b[1]=buildroot-2021.02.8
b[2]=2021

package_list=( "bc" "bison" "build-essential" "curl"
"device-tree-compiler" "dosfstools" "flex" "gcc-aarch64-linux-gnu"
"gcc-arm-linux-gnueabihf" "gdisk" "git" "gnupg" "gperf" "libc6-dev"
"libncurses5-dev" "libssl-dev"
"lzop" "mtools" "parted" "swig" "tar" "zip" "qtbase5-dev" "qemu-user-static" "binfmt-support"
"libglade2-dev" "libglib2.0-dev" "libgtk2.0-dev" "libpython2-dev")

package_list_ubuntu20=("repo" "mkbootimg")
package_list_ubuntu14=("qt4-default" "libc6:i386" "libssl1.0.0" "libpython-dev" "nautilus-open-terminal")

CURRENT_PATH=$(pwd)
UBUNTU_VERSION=$(lsb_release -rs)
CONFIG_GUI=gconfig

sudo adduser $USER vboxsf
sudo adduser $USER dialout

ros_tool() {

	# if [ $(dpkg-query -W -f='${Status}' qtbase5-dev 2>/dev/null | grep -c "ok installed") -eq 0 ];
	# then
	# 	sudo apt-get install qtbase5-dev;
	# fi

	BUILD_KERNEL=$1 # -build-kernel
	MAKE_BUILDROOT=$2 # radxa or rasp3
	PACK_ROOTFS=$3 # -pack or -pack-radxa
	FLASH=$4 # -flash

	if [ "$BUILD_KERNEL" == "-build-kernel" ]; then
		compile_kernel
	fi

	echo $'\n\n\n\n'
	echo $'\n\n\n\n'

	ans=$(zenity  --list  --text "Choose a buildroot option" --radiolist  --column "Pick" --column "version" TRUE ${b[1]});
	echo $ans
	if [ $ans == ${b[1]} ]; then
		b[1]=${b[1]}
		b[2]=${b[2]}
	fi
	echo $'\n\n\n\n'

	if [ "$MAKE_BUILDROOT" == "radxa" ] || [ "$MAKE_BUILDROOT" == "rasp3" ]; then
		if [ ! -d ../$MAKE_BUILDROOT ]; then
			mkdir ../$MAKE_BUILDROOT
		fi
		cd ../$MAKE_BUILDROOT

		if [ -d ${b[1]} ]; then
			zenity --question --title=" " --text="Say Yes If you want to return default buildroot config? / Say No continue with previous?" --no-wrap
			case $? in
				[0]* ) 
					cp ../ros_tool/conf/$MAKE_BUILDROOT-${b[1]}_default_defconfig ./${b[1]}/.config
					;;
				[1]* ) echo $'\n\n'; echo 'Keeping previous .config'; echo $'\n\n'
					;;
				* ) echo $'\n\n'; echo "Please answer yes or no."; echo $'\n\n'
					;;
			esac
			make --directory=./${b[1]}/ xconfig
			make --directory=./${b[1]}/
			while true; do

				echo $'\n\n\n'

				zenity --question --title=" " --text="Click Yes If you want to return make buildroot again? / Click No continue?" --no-wrap
				case $? in
					[0]* )
						zenity --question --title=" " --text="Click Yes If you want to return default buildroot config? / Click No continue with previous?" --no-wrap
						case $? in
							[0]* ) 
								cp ../ros_tool/conf/$MAKE_BUILDROOT-${b[1]}_default_defconfig ./${b[1]}/.config
								;;
							[1]* ) echo $'\n\n'; echo 'Keeping previous .config'; echo $'\n\n'
								;;
							* ) echo $'\n\n'; echo "Please answer yes or no."; echo $'\n\n'
								;;
						esac 
						make --directory=./${b[1]}/ xconfig
						make --directory=./${b[1]}/
						;;
						[1]* )
						echo $'\n\n'; echo 'continue--------'; echo $'\n\n'
						break
						;;
						* ) echo $'\n\n'; echo "Please answer yes or no."; echo $'\n\n'
						;;
				esac
			done
		elif [ ! -d ${b[1]} ]; then
			wget https://buildroot.org/downloads/${b[1]}.tar.gz
			tar zxvf ${b[1]}.tar.gz > /dev/null
			cp ../ros_tool/conf/$MAKE_BUILDROOT-${b[1]}_default_defconfig ${b[1]}/.config
			make --directory=./${b[1]}/ xconfig
			make --directory=./${b[1]}/
		fi
		cd ../ros_tool
	fi

	echo $'\n\n'

	if [ "$PACK_ROOTFS" == "-pack" ]; then
		rootfs_image_generate ${b[2]} ../$MAKE_BUILDROOT/${b[1]}
		cd rockchip-tools/
		./mkupdate.sh
		cd ..
	elif [ "$PACK_ROOTFS" == "-pack-radxa" ]; then
		rootfs_image_generate ${b[2]} ../radxa/${b[1]}
		cd rockchip-tools/
		./mkupdate.sh
		cd ..
	fi

	echo $'\n\n'

	if [ "$FLASH" == "-flash" ]; then
		read -p "Put radxa rock pro in maskrom mode, then enter : " yn
		cd rockchip-tools/
		sudo ./upgrade_tool lf
		sudo ./upgrade_tool uf update.img
		cd ..
	fi
}



compile_kernel() {

	if [ $UBUNTU_VERSION == "16.04" ] || [ $UBUNTU_VERSION == "14.04" ]; then
		CONFIG_GUI="xconfig"
	elif [ $UBUNTU_VERSION == "20.04" ]; then
		CONFIG_GUI="gconfig"
	else
		CONFIG_GUI="gconfig"
	fi

	ans=$(zenity  --list  --text "Choose a cross compiler" --radiolist  --column "Pick" --column "Compiler" TRUE "arm-eabi-4.6" FALSE "default" FALSE "gcc-4.8" FALSE "gcc-4.9" ); 
	echo $ans
	if [ $ans == "default" ]; then
		COMPILER_PATH=arm-linux-gnueabihf-
		
	elif [ $ans == "gcc-4.8" ]; then
		if [ ! -f gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux.tar.xz ]; then
			wget https://releases.linaro.org/archive/13.08/components/toolchain/binaries/gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux.tar.xz
		fi

		if [ ! -d gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux ]; then
			tar -xaf gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux.tar.xz
		fi

		COMPILER_PATH=$CURRENT_PATH/gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux/bin/arm-linux-gnueabihf-

	elif [ $ans == "gcc-4.9" ]; then
		if [ ! -f gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz ]; then
			wget https://releases.linaro.org/components/toolchain/binaries/latest-4/arm-linux-gnueabihf/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz
		fi

		if [ ! -d gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf ]; then
			tar -xaf gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf.tar.xz
		fi

		COMPILER_PATH=$CURRENT_PATH/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-

	elif [ $ans == "arm-eabi-4.6" ]; then
		if [ ! -d arm-eabi-4.6 ]; then
			git clone -b kitkat-release --depth 1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6
		fi

		COMPILER_PATH=$CURRENT_PATH/arm-eabi-4.6/bin/arm-eabi-

	else
	zenity --error --text "Unknown compiler "
	fi

	if [ ! -d sys ]; then
		mkdir sys
	fi
	cd sys
	if [ ! -d linux-radxa-stable-3.0 ]; then
		git clone -b radxa-stable-3.0 https://www.github.com/ferhatsencer/linux-rockchip.git
		mv linux-rockchip linux-radxa-stable-3.0
	fi

	if [ ! -f initrd.img ]; then
		git clone https://github.com/radxa/initrd.git
		make -C initrd
	fi

	if [ ! -f initrd.img ]; then
		make -C initrd ARCH=arm CROSS_COMPILE=$COMPILER_PATH
	else
		echo "initrd.img exist!"
	fi

	cd ..
	if [ ! -f config_copied ]; then
		rm sys/linux-radxa-stable-3.0/.config
		cp conf/rockchip-default_defconfig sys/linux-radxa-stable-3.0/.config
		touch config_copied
	fi


	if zenity --question --title="Return Default Config" --text="Would you like to return default configurations?" --no-wrap
	then
		cp conf/rockchip-default_defconfig sys/linux-radxa-stable-3.0/.config;
	else
		echo $'\n\n'; echo 'Keeping previous .configG'; echo $'\n\n\n';
	fi

	cd ./sys/linux-radxa-stable-3.0
	make clean
	make $CONFIG_GUI
	make -j2 ARCH=arm CROSS_COMPILE=$COMPILER_PATH kernel.img

	while true; do
		zenity --question --title=" " --text="Click Yes If you want to return kernel.img make again / Click No continue?" --no-wrap
		case $? in
			[0]* ) 
				ans=$(zenity  --list  --text "Choose a cross compiler" --radiolist  --column "Pick" --column "Compiler" TRUE "arm-eabi-4.6" FALSE "default" FALSE "gcc-4.8" FALSE "gcc-4.9"); 
				echo $ans
				
				if [ $ans == "default" ]; then
					COMPILER_PATH=arm-linux-gnueabihf-
					
				elif [ $ans == "gcc-4.8" ]; then
					COMPILER_PATH=$CURRENT_PATH/gcc-linaro-arm-linux-gnueabihf-4.8-2013.08_linux/bin/arm-linux-gnueabihf-
					
				elif [ $ans == "gcc-4.9" ]; then
					COMPILER_PATH=$CURRENT_PATH/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-

				elif [ $ans == "arm-eabi-4.6" ]; then
                                if [ ! -d arm-eabi-4.6 ]; then
                                        git clone -b kitkat-release --depth 1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6
                                fi
                                        COMPILER_PATH=$CURRENT_PATH/arm-eabi-4.6/bin/arm-eabi-
                                else
				zenity --error --text "Unknown compiler "
				fi
				
				make clean
				make $CONFIG_GUI
				make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- kernel.img
				;;
			[1]* ) echo $'\n\n'; echo 'continue--------'; echo $'\n\n'; break
				;;
			* ) echo $'\n\n'; echo "Please answer yes or no."; echo $'\n\n'
				;;
		esac
	done

	if [ ! -d modules ]; then
		mkdir modules
	fi

	make ARCH=arm CROSS_COMPILE=$COMPILER_PATH INSTALL_MOD_PATH=./modules modules modules_install

	cd ..
	cd ..

	if [ ! -d rockchip-tools/Linux ]; then
		mkdir -p rockchip-tools/Linux
	fi

	mkbootimg --kernel sys/linux-radxa-stable-3.0/arch/arm/boot/Image --ramdisk sys/initrd.img -o rockchip-tools/Linux/boot-linux.img

	cp sys/linux-radxa-stable-3.0/.config last_config_backup

}

rootfs_image_generate() {

	BUILDROOT_YEAR=$1
	BUILDROOT_PATH=$2

	sudo umount mnt-rootfs/
	sudo rm -r mnt-rootfs/

	sudo rm rootfs-$BUILDROOT_YEAR.img
	sudo rm rootfs.tar

	if [ ! -d mnt-rootfs ]; then
		mkdir mnt-rootfs
	fi

	cp $BUILDROOT_PATH/output/images/rootfs.tar .

	#250mb
	if [ ! -f rootfs-$BUILDROOT_YEAR.img ]; then
		dd if=/dev/zero of=rootfs-$BUILDROOT_YEAR.img bs=1M count=250
		mkfs.ext4 -F -L linuxroot rootfs-$BUILDROOT_YEAR.img
	fi

	sudo mount -o loop rootfs-$BUILDROOT_YEAR.img mnt-rootfs/

	sudo tar -xvf rootfs.tar -C mnt-rootfs/ > /dev/null

	sudo rm -r mnt-rootfs/lib/modules
	sudo rm -r mnt-rootfs/lib/firmware

	sudo mkdir -p mnt-rootfs/lib/firmware
	sudo mkdir -p mnt-rootfs/lib/modules

	sudo cp -r ./sys/linux-radxa-stable-3.0/modules/lib/modules/3.0.36+/ ./mnt-rootfs/lib/modules
	sudo cp -r ./sys/linux-radxa-stable-3.0/firmware/* ./mnt-rootfs/lib/firmware/

	sudo mv mnt-rootfs/lib/modules/3.0.36 mnt-rootfs/lib/modules/3.0.36+

	sync

	read -p "Enter to unmount and clean folders : " yn

	sudo umount mnt-rootfs/
	sudo rm -r mnt-rootfs/

	if [ ! -d rockchip-tools/Linux ]; then
		mkdir rockchip-tools/Linux
	fi

	mv rootfs-$BUILDROOT_YEAR.img rockchip-tools/Linux/rootfs.img
	rm rootfs.tar

}

kill_process() {

	proc_name=$1
	ps -fe | awk 'NR==1{for (i=1; i<=NF; i++) {if ($i=="COMMAND") Ncmd=i; else if ($i=="PID") Npid=i} if (!Ncmd || !Npid) {print "wrong or no header" > "/dev/stderr"; exit} }$Ncmd~"/"name"$"{print "killing "$Ncmd" with PID " $Npid; system("kill -9 "$Npid)}' name=.*$proc_name.*
}

run_exec() {
	
	exec_name=$1

	cd /opt
	chmod +x *.sh
	chmod +x $exec_name
	./$exec_name &
}

scan_lan() {
	
	IPs=$(sudo arp-scan --localnet --numeric --quiet --ignoredups | grep -E '([a-f0-9]{2}:){5}[a-f0-9]{2}' | awk '{print $1}')
	echo $IPs

	myIpAddr=$(sudo nm-tool | grep -i 'address' | grep -Po '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sed -n "$myip"p)
	echo $myIpAddr
}

install_package() {
	if [ $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed") -eq 0 ];
	then
		sudo apt-get install $1;
	fi
}

install_func1() {
    for i in ${package_list[@]}
    do
        echo $i
        install_package $i
    done

	if [ $UBUNTU_VERSION == "16.04" ] || [ $UBUNTU_VERSION == "14.04" ]; then
		for i in ${package_list_ubuntu14[@]}
		do
			echo $i
			install_package $i
			if which mkbootimg >/dev/null; then
                echo exists
            else
                echo does not exist
                cd rockchip-tools
                git clone https://github.com/neo-technologies/rockchip-mkbootimg.git
                cd rockchip-mkbootimg
                make
                sudo make install
                cd ..
                cd ..
            fi
		done
	elif [ $UBUNTU_VERSION == "20.04" ] || [ $UBUNTU_VERSION == "22.04" ]; then

		for i in ${package_list_ubuntu20[@]}
		do
			echo $i
			install_package $i
		done
	else
		echo "---"
	fi
	
	# if [ $(dpkg-query -W -f='${Status}' mkbootimg 2>/dev/null | grep -c "ok installed") -eq 0 ];
	
}

if [ $UBUNTU_VERSION == "14.04" ]; then
	install_func1
fi
yes | install_func1
ros_tool $1 $2 $3 $4

