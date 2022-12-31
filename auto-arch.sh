#!/bin/bash


# ----------------------------- Configuration ----------------------------- 

clear
set -e
set -o pipefail
setfont ter-v32n

PS3="❯ "


echo "Would you like to install Arch Linux using this script?"

select confirm in Yes No; do
	case $confirm in
		Yes)
			break
			;;
		No)
			echo "Cancelling Installation..."
			exit
		;;
	esac
done

clear

echo -e "Select \e[4;31mBoot\e[0m Partition:"
PARTITIONS=($(fdisk -l | awk '/^[/]/{print $1}'))

select partition in "${PARTITIONS[@]}"; do
	BOOTDEV=$partition
	break
done

clear

echo -e "Select \e[4;34mRoot\e[0m Partition:"

select partition in "${PARTITIONS[@]}"; do
	ROOTDEV=$partition
	break
done

clear

echo -e "Select \e[4;33mRegion\e[0m:"
REGIONS=("Africa" "America" "Antarctica" "Asia" "Australia" "Europe" "Pacific")

select region in "${REGIONS[@]}"; do
	SELECTED_REGION=$region
	break
done

clear

echo -e "Select \e[4;35mCity\e[0m:"
CITIES=($(ls /usr/share/zoneinfo/$SELECTED_REGION))

select city in "${CITIES[@]}"; do
	SELECTED_CITY=$city
	break
done

clear

echo -e "Select \e[4;35mCPU brand\e[0m:"

select brand in Intel AMD "Skip CPU microcode installation"; do
	if [ $brand == "Intel" ]; then
		MICROCODE_PKG="intel-ucode"
	elif [ $brand == "AMD" ]; then
		MICROCODE_PKG="amd-ucode"
	fi
	
	break
done

clear

echo -e "Select \e[4;35mGPU brand\e[0m:"

select brand in Intel NVIDIA AMD "Skip GPU driver installation"; do
	GPU_BRAND=$brand
	
	if [ $GPU_BRAND == "Intel" ]; then
		GPU_PKGS=(
			"xf86-video-intel"
		)
	elif [ $GPU_BRAND == "NVIDIA" ]; then
		GPU_PKGS=(
			"nvidia"
			"nvidia-utils"
			"nvidia-settings"
			"lib32-nvidia-utils"
		)
	elif [ $GPU_BRAND == "AMD" ]; then
		GPU_PKGS=(
			"xf86-video-amdgpu"
			"vulkan-radeon"
			"lib32-vulkan-radeon"
		)
	fi
	
	break
done

clear

printf "Enter \e[4;94mHostname\e[0m: "
read HOSTNAME

if [ -z "$HOSTNAME" ]; then 
	echo "Hostname cannot be empty."
	exit
fi

clear

printf "Enter \e[4;95mUsername\e[0m: "
read USERNAME

if [ -z "$USERNAME" ]; then 
	echo "Username cannot be empty."
	exit
fi

clear

echo "Set root password and user password to be the same?"

select confirm in Yes No; do
	case $confirm in
		Yes)
			printf "Enter \e[4;35mPassword\e[0m: "
			read -s PASSWORD
			printf "\n"
			
			if [ -z "$PASSWORD" ]; then
				echo "Password cannot be empty."
				exit
			fi
			
			printf "Confirm \e[4;35mPassword\e[0m: "
			read -s CONFIRM_PASSWORD
			printf "\n"
			
			if [ $PASSWORD != $CONFIRM_PASSWORD ]; then
				echo "Passwords do not match."
				exit
			fi
			
			USER_PASSWORD=$PASSWORD
			ROOT_PASSWORD=$PASSWORD
			break
			;;
		No)
			printf "Enter \e[4;35mRoot Password\e[0m: "
			read -s ROOT_PASSWORD
			printf "\n"
			
			if [ -z "$ROOT_PASSWORD" ]; then
				echo "Password cannot be empty."
				exit
			fi
			
			printf "Confirm \e[4;35mRoot Password\e[0m: "
			read -s CONFIRM_ROOT_PASSWORD
			printf "\n"
			
			if [ $ROOT_PASSWORD != $CONFIRM_ROOT_PASSWORD ]; then
				echo "Passwords do not match."
				exit
			fi
			
			printf "Enter \e[4;35m$USERNAME's Password\e[0m: "
			read -s USER_PASSWORD
			printf "\n"
			
			if [ -z "$USER_PASSWORD" ]; then
				echo "Password cannot be empty."
				exit
			fi
			
			printf "Confirm \e[4;35m$USERNAME's Password\e[0m: "
			read -s CONFIRM_USER_PASSWORD
			printf "\n"
			
			if [ $USER_PASSWORD != $CONFIRM_USER_PASSWORD ]; then
				echo "Passwords do not match."
				exit
			fi
			
			exit
		;;
	esac
done

clear

echo "Confirm Details:"
echo -e "\e[4;31mBOOT PARTITION:\e[0m $BOOTDEV"
echo -e "\e[4;31mROOT PARTITION:\e[0m $ROOTDEV"
echo -e "\e[4;31mREGION:\e[0m $SELECTED_REGION"
echo -e "\e[4;31mCITY:\e[0m $SELECTED_CITY"
echo -e "\e[4;31mHOSTNAME:\e[0m $HOSTNAME"
echo -e "\e[4;31mUSERNAME:\e[0m $USERNAME"
printf "\n"

select confirm in Continue Cancel; do
	case $confirm in
		Continue)
			break
			;;
		Cancel)
			echo "Cancelling Installation..."
			exit
		;;
	esac
done

clear

# ----------------------------- Installation ----------------------------- 

timedatectl set-ntp true

mkfs.fat -F32 $BOOTDEV
yes | mkfs.ext4 $ROOTDEV

mount $ROOTDEV /mnt
mount --mkdir /dev/$BOOTDEV /mnt/boot

printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/g" /etc/makepkg.conf

pacman -Syy archlinux-keyring

BASE_PKGS=(
	"base"
	"linux"
	"linux-firmware"
	"linux-headers"
	"base-devel"
)

BOOT_PKGS=(
	"grub"
	"mtools"
	"os-prober"
	"efibootmgr"
	"dosfstools"
)

NETWORK_PKGS=(
	"iwd"
	"wpa_supplicant"
	"wireless_tools"
	"networkmanager"
)

BLUETOOTH_PKGS=(
	"bluez"
	"bluez-utils"
)

AUDIO_PKGS=(
	"pulseaudio"
	"pulsemixer"
	"pulseaudio-bluetooth"
	"alsa-firmware"
	"alsa-plugins"
	"alsa-utils"
	"sof-firmware"
)

CUSTOM_PKGS=(
	"xorg" # X System
	"xorg-xinit" # X System
	"lightdm" # Display manager
	"lightdm-webkit2-greeter" # LightDM theme
	"bspwm" # Tiling Window Manager
	"sxhkd" # Hotkey Daemon
	"mesa" # Mesa
	"lib32-mesa" # 32-bit Mesa
	"mesa-demos" # Mesa Demos
	"mesa-utils" # Mesa Utils
	"vulkan-icd-loader" # Vulkan
	"lib32-vulkan-icd-loader" # Vulkan
	"light" # Manage brightness
	"zsh" # Z Shell
	"cifs-utils" # Mount Common Internet File System
	"ntfs-3g" # Mount New Technology File System
	"rofi" # Search tool
	"flameshot" # Screenshot tool
	"kitty" # Terminal Emulator
	"neovim" # Text Editor
	"nodejs" # TSServer dependency
	"npm" # TSServer dependency
	"typescript-language-server" # TS/JS Server
	"rust-analyzer" # Rust Language Server
	"clang" # C-Family Language Server
	"pyright" # Python Language Server
	"lua-language-server" # Lua Language Server
	"htop" # System monitor
	"exa" # ls alternative
	"bat" # cat alternative
	"wget" # Retrieve content
	"git" # Git
	"man" # Manual
	"github-cli" # Github CLI
	"dunst" # Notifications
	"zip" # Zip files
	"unzip" # Unzip files
	"feh" # Image tool
	"python-pip" # Install Python modules/packages
	"xclip" # Copy to clipboard
	"ttf-joypixels" # Emoji font
	"libx11" # X11 Client Library
	"libxcursor" # Cursor dependency
	"libpng" # Cursor dependency
	"xorg-xprop" # Polywins dependency
	"wmctrl" # Polywins dependency
	"slop" # Polywins dependency
)

pacstrap /mnt "${BASE_PKGS[@]} ${BOOT_PKGS[@]} ${NETWORK_PKGS[@]} ${BLUETOOTH_PKGS[@]} ${AUDIO_PKGS[@]} ${GPU_PKGS[@]} ${CUSTOM_PKGS[@]} $MICROCODE_PKG" 

genfstab -U /mnt >> /mnt/etc/fstab

cat << EOF > /mnt/installation.sh
# Pacman configuration
printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/g" /etc/makepkg.conf

pacman -Syy archlinux-keyring

# Time zone
ln -sf /usr/share/zoneinfo/$SELECTED_REGION/$SELECTED_CITY /etc/localtime
hwclock --systohc

# Localization
sed -i "s/#en_US.UTF-8/en_US.UTF-8/g" /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network Configuration
echo $HOSTNAME > /etc/hostname
echo "127.0.0.1  localhost" >> /etc/hosts
echo "::1        localhost" >> /etc/hosts
echo "127.0.1.1  $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Install GRUB
grub-install --target=x86_64-efi --bootloader-id=grub_uefi --efi-directory=/boot --recheck

# Add user
useradd -m $USERNAME
usermod -aG wheel,audio,video $USERNAME

# Set passwords
printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd
printf "$USER_PASSWORD\n$USER_PASSWORD" | passwd $USERNAME

# Configure sudo
echo "$USERNAME  ALL=(ALL:ALL) NOPASSWD: ALL" | EDITOR="tee -a" visudo

# Enable services
systemctl enable NetworkManager.service
systemctl enable bluetooth.service

exit
EOF

arch-chroot /mnt /bin/bash installation.sh

if [ $GPU_BRAND == "NVIDIA" ]; then
	cat << EOF > /mnt/etc/pacman.d/hooks/nvidia.hook
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=linux
# Change the linux part above and in the Exec line if a different kernel is used

[Action]
Description=Update NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux) exit 0; esac; done; /usr/bin/mkinitcpio -P'
	EOF
fi

# ----------------------------- Customization ----------------------------- 

cat << EOF > /mnt/home/$USERNAME/customization.sh
AUR_PKGS=(
	"nerd-fonts-jetbrains-mono" # JetBrains Mono Nerd Font
	"ttf-poppins" # Poppins font
	"picom-ibhagwan-git" # Picom compositor
	"polybar" # Polybar
	"brave-bin" # Brave Browser
)

# Install AUR packages
for aurpkg in "\${AUR_PKGS[@]}"; do
	infobox "AUR" "Installing \"\$aurpkg\" from the Arch User Repository..."
	git clone https://aur.archlinux.org/\$aurpkg.git
    sudo chmod 777 \$aurpkg
	cd \$aurpkg
	makepkg -si --noconfirm
	cd ..
	sudo rm -rf \$aurpkg
done

# Install LightDM Aether theme
git clone https://github.com/NoiSek/Aether.git
sudo mv Aether /usr/share/lightdm-webkit/themes/lightdm-webkit-theme-aether
sudo sed -i 's/^webkit_theme\s*=\s*\(.*\)/webkit_theme = lightdm-webkit-theme-aether #\1/g' /etc/lightdm/lightdm-webkit2-greeter.conf
sudo sed -i "s/#greeter-session=example-gtk-gnome/greeter-session=lightdm-webkit2-greeter/g" /etc/lightdm/lightdm.conf
sudo sed -i "s/#user-session=default/user-session=bspwm/g" /etc/lightdm/lightdm.conf
sudo systemctl enable lightdm.service

# Change default shell
sudo chsh -s /bin/zsh \$USER

# Download dotfiles
git clone https://github.com/BetaLost/dotfiles.git
mkdir -p \$HOME/.config

# Configure BSPWM and SXHKD
sudo mv \$HOME/dotfiles/bspwm \$HOME/.config/
sudo mv \$HOME/dotfiles/sxhkd \$HOME/.config/
sudo mv \$HOME/dotfiles/wallpapers \$HOME/.config/

find \$HOME/.config/bspwm -type f -exec chmod +x {} \;
find \$HOME/.config/sxhkd -type f -exec chmod +x {} \;

# Configure ZSH
git clone https://github.com/zsh-users/zsh-autosuggestions.git \$HOME/.zsh/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \$HOME/.zsh/zsh-syntax-highlighting
mv \$HOME/dotfiles/.zshrc \$HOME/

# Configure BASH
mv \$HOME/dotfiles/.bashrc \$HOME/

# Configure Neovim
curl -fLo \$HOME/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
mv \$HOME/dotfiles/nvim \$HOME/.config/
nvim -c "PlugInstall | q | q"
sed -i "s/background = '#282923'/background = '#1a1a18'/g" \$HOME/.local/share/nvim/plugged/ofirkai.nvim/lua/ofirkai/design.lua

# Configure dunst
sudo mv \$HOME/dotfiles/dunst \$HOME/.config/

# Configure Rofi
sudo mv \$HOME/dotfiles/rofi \$HOME/.config/

# Configure Kitty
sudo mv \$HOME/dotfiles/kitty \$HOME/.config/

# Configure Picom 
sudo mv \$HOME/dotfiles/picom \$HOME/.config/

# Configure Polybar
sudo mv \$HOME/dotfiles/polybar \$HOME/.config/

for script in \$HOME/.config/polybar/scripts/*; do
    sudo chmod +x \$script
done

# Install Arabic font
wget https://github.com/BetaLost/auto-arch/raw/main/khebrat-musamim.zip
unzip khebrat-musamim.zip
rm khebrat-musamim.zip
sudo mkdir -p /usr/share/fonts/TTF
sudo mv "18 Khebrat Musamim Regular.ttf" /usr/share/fonts/TTF/

sudo mv \$HOME/dotfiles/fonts.conf /etc/fonts/
sudo cp /etc/fonts/fonts.conf /etc/fonts/local.conf

# Install GRUB theme
wget https://github.com/BetaLost/auto-arch/raw/main/arch.tar
sudo mkdir -p /boot/grub/themes
sudo mkdir /boot/grub/themes/arch
sudo mv arch.tar /boot/grub/themes/arch/
sudo tar xf /boot/grub/themes/arch/arch.tar -C /boot/grub/themes/arch/
sudo rm /boot/grub/themes/arch/arch.tar
sudo sed -i "s/GRUB_GFXMODE=auto/GRUB_GFXMODE=1920x1080/g" /etc/default/grub
sudo sed -i "s/#GRUB_THEME=.*/GRUB_THEME=\"\/boot\/grub\/themes\/arch\/theme.txt\"/g" /etc/default/grub
sudo sed -i "s/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/g" /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Install cursor
wget https://github.com/BetaLost/auto-arch/raw/main/macOSBigSur.tar.gz
tar -xf macOSBigSur.tar.gz
rm macOSBigSur.tar.gz
sudo mv macOSBigSur /usr/share/icons/

sudo sed -i "s/Inherits=Adwaita/Inherits=macOSBigSur/g" /usr/share/icons/default/index.theme

exit
EOF

arch-chroot /mnt /bin/su -c "cd; bash customization.sh" $USERNAME -

# ----------------------------- Complete ----------------------------- 

echo "\e[4;34mArch Linux\e[0m has been installed \e[4;32msuccessfully\e[0m on this machine."
