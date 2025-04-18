#!/bin/bash


# ----------------------------- Configuration ----------------------------- 

clear
set -eo pipefail
setfont ter-v32n

title="Auto Arch"

input_box() {
	whiptail --title "$title" --inputbox "$1" 0 0 3>&1 1>&2 2>&3
}

password_box() {
	whiptail --title "$title" --passwordbox "$1" 7 35 3>&1 1>&2 2>&3
}

msgbox() {
	whiptail --title "$title" --msgbox "$1" 0 0
}

select_partition() {
	PARTITIONS=$(lsblk -lpno NAME,TYPE | awk '$2=="part" {print $1}')
	OPTIONS=()
	
	for PARTITION in $PARTITIONS; do
		OPTIONS+=("$PARTITION" " $(lsblk -no SIZE,FSTYPE $PARTITION | awk '{printf "%s (%s)", $1, ($2 == "" ? "UNKNOWN" : $2)}')")
	done

	whiptail --title "$title" --menu "Select $1 partition:" 0 0 0 "${OPTIONS[@]}" 3>&1 1>&2 2>&3
}

select_from_menu() {
	TOSELECT=$1
	shift
	LIMIT_SIZE=$1
	shift
	OPTIONS=()
	for OPTION in "$@"; do
		OPTIONS+=("${OPTION}" "")
	done

	if [ $LIMIT_SIZE -eq 1 ]; then
		whiptail --title "$title" --menu "Select $TOSELECT:" 20 30 12 "${OPTIONS[@]}" 3>&1 1>&2 2>&3
	else
		whiptail --title "$title" --menu "Select $TOSELECT:" 0 0 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3
	fi
}

# Select boot partition
BOOTDEV=$(select_partition "BOOT")
if [ $? -ne 0 ]; then exit; fi

# Select root partition
ROOTDEV=$(select_partition "ROOT")
if [ $? -ne 0 ]; then exit; fi

# Select region
REGIONS=$(ls -l /usr/share/zoneinfo/ | grep '^d' | gawk -F':[0-9]* ' '/:/{print $2}')
SELECTED_REGION=$(select_from_menu "Region" 1 $REGIONS)
if [ $? -ne 0 ]; then exit; fi

# Select city
CITIES=$(ls /usr/share/zoneinfo/${SELECTED_REGION}/)
SELECTED_CITY=$(select_from_menu "City" 1 $CITIES)
if [ $? -ne 0 ]; then exit; fi

# Select CPU brand
CPU_BRANDS=("Intel" "AMD" "Skip CPU microcode installation")
CPU_BRAND=$(select_from_menu "CPU brand" 0 "${CPU_BRANDS[@]}")
if [ $? -ne 0 ]; then exit; fi

case $CPU_BRAND in
	Intel) MICROCODE_PKG="intel-ucode";;
	AMD) MICROCODE_PKG="amd-ucode";;
esac

# Select GPU brand
GPU_BRANDS=("NVIDIA" "AMD" "Intel" "Skip GPU driver installation")
GPU_BRAND=$(select_from_menu "GPU brand" 0 "${GPU_BRANDS[@]}")
if [ $? -ne 0 ]; then exit; fi

case $GPU_BRAND in
	Intel) GPU_PKGS=("xf86-video-intel");;
	NVIDIA) GPU_PKGS=("nvidia" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils");;
	AMD) GPU_PKGS=("xf86-video-amdgpu" "vulkan-radeon" "lib32-vulkan-radeon");;
esac

# Install power optimizer
if whiptail --title "$title" --yesno "Install auto-cpufreq?" 0 0; then POWER_OPTIMIZER="YES"; else POWER_OPTIMIZER="NO"; fi

# Select default Arabic font
ARABIC_FONTS=("SST Arabic" "RB" "Amiri" "Noto Naskh Arabic" "SF Arabic" "18 Khebrat Musamim" "Skip Arabic font installation")
DEFAULT_ARABIC_FONT=$(select_from_menu "default Arabic font" 0 "${ARABIC_FONTS[@]}")
if [ $? -ne 0 ]; then exit; fi

# Select Arabic fonts to install
if [ "$DEFAULT_ARABIC_FONT" != "Skip Arabic font installation" ]; then
	CHECKLIST_ITEMS=()
	for font in "${ARABIC_FONTS[@]}"; do
	    if [ "$font" != "$DEFAULT_ARABIC_FONT" ] && [ "$font" != "Skip Arabic font installation" ]; then
	        CHECKLIST_ITEMS+=("$font" "OFF")
	    fi
	done
	
	SELECTED_ARABIC_FONTS=$(whiptail --title "$title" --noitem --checklist "Select Arabic fonts" 0 0 0 "${CHECKLIST_ITEMS[@]}" 3>&1 1>&2 2>&3)
	if [ $? -ne 0 ]; then exit; fi
	
	eval "SELECTED_ARABIC_FONTS=($SELECTED_ARABIC_FONTS)"
	SELECTED_ARABIC_FONTS+=("$DEFAULT_ARABIC_FONT")

	printf -v JOINED_ARABIC_FONTS '%s, ' "${SELECTED_ARABIC_FONTS[@]}"
fi

msgbox "The following prompt(s) will ask you to enter Country and City. To fetch prayer times from your masjid (mawaqit.net), you can instead enter your masjid ID in prayer.sh (recommended). If neither location nor masjid ID are entered, the location will be fetched automatically based on IP."

# Enter country (REQUIRED FOR: prayer.sh)
PRAYER_COUNTRY=$(input_box "prayer.sh: Enter Country name or ISO 3166 code (ex: Netherlands or NL):")
if [ $? -ne 0 ]; then exit; fi

if [ -z "$PRAYER_COUNTRY" ]; then 
	msgbox "Location will be fetched automatically from ipinfo.io"
fi

# Enter city (REQUIRED FOR: prayer.sh)
if [ -n "$PRAYER_COUNTRY" ]; then
	PRAYER_CITY=$(input_box "(prayer.sh) Enter City name (ex: Makkah):")
	if [ $? -ne 0 ]; then exit; fi
	
	if [ -z "$PRAYER_CITY" ]; then 
		msgbox "Location will be fetched automatically from ipinfo.io"
	fi
fi

PRAYER_METHODS=("3 - Muslim World League (DEFAULT)" "4 - Umm Al-Qura University, Makkah" "8 - Gulf Region" "16 - Dubai (unofficial)")
PRAYER_METHOD=$(select_from_menu "method for calculating prayer times" 0 "${PRAYER_METHODS[@]}")
if [ $? -ne 0 ]; then exit; fi

# Enter hostname
HOSTNAME=$(input_box "Enter Hostname:")
if [ $? -ne 0 ]; then exit; fi

if [ -z "$HOSTNAME" ]; then msgbox "Hostname cannot be empty." && exit; fi

# Enter username
USERNAME=$(input_box "Enter Username:")
if [ $? -ne 0 ]; then exit; fi
if [ -z "$USERNAME" ]; then msgbox "Username cannot be empty." && exit; fi

# Enter password(s)
if whiptail --title "$title" --yesno "Set root password and user password to be the same?" 0 0; then
	PASSWORD=$(password_box "Enter Password:")
	if [ $? -ne 0 ]; then exit; fi
	if [ -z "$PASSWORD" ]; then msgbox "Password cannot be empty." && exit; fi

	CONFIRM_PASSWORD=$(password_box "Confirm Password:")
	if [ $? -ne 0 ]; then exit; fi
	if [ "$PASSWORD" != "$CONFIRM_PASSWORD" ]; then msgbox "Passwords do not match." && exit; fi

	USER_PASSWORD=$PASSWORD
	ROOT_PASSWORD=$PASSWORD
	SAME_PASSWORD="YES"
else
	ROOT_PASSWORD=$(password_box "Enter ROOT Password:")
	if [ $? -ne 0 ]; then exit; fi
	if [ -z "$ROOT_PASSWORD" ]; then msgbox "Password cannot be empty." && exit; fi

	CONFIRM_ROOT_PASSWORD=$(password_box "Confirm ROOT Password:")
	if [ $? -ne 0 ]; then exit; fi
	if [ "$ROOT_PASSWORD" != "$CONFIRM_ROOT_PASSWORD" ]; then msgbox "Passwords do not match." && exit; fi

	USER_PASSWORD=$(password_box "Enter $USERNAME's Password:")
	if [ $? -ne 0 ]; then exit; fi
	if [ -z "$USER_PASSWORD" ]; then msgbox "Password cannot be empty." && exit; fi

	CONFIRM_USER_PASSWORD=$(password_box "Confirm $USERNAME's Password:")
	if [ $? -ne 0 ]; then exit; fi
	if [ "$USER_PASSWORD" != "$CONFIRM_USER_PASSWORD" ]; then msgbox "Passwords do not match." && exit; fi

	SAME_PASSWORD="NO"
fi

# Confirm inputted data
whiptail --title "$title" --yesno "BOOT PARTITION: $BOOTDEV
ROOT PARTITION: $ROOTDEV
REGION (TIMEZONE): $SELECTED_REGION
CITY (TIMEZONE): $SELECTED_CITY
CPU BRAND: $CPU_BRAND
GPU BRAND: $GPU_BRAND
INSTALL POWER OPTIMIZER (auto-cpufreq)?: $POWER_OPTIMIZER
DEFAULT ARABIC FONT: $DEFAULT_ARABIC_FONT
SELECTED ARABIC FONTS: ${JOINED_ARABIC_FONTS%, }
COUNTRY (PRAYER): $PRAYER_COUNTRY
CITY (PRAYER): $PRAYER_CITY
METHOD (PRAYER): $PRAYER_METHOD
HOSTNAME: $HOSTNAME
USERNAME: $USERNAME
ROOT AND USER SAME PASSWORD?: $SAME_PASSWORD

Proceed with installation?" 0 0

if [ $? -ne 0 ]; then msgbox "Cancelling installation..." && exit; fi

# ----------------------------- Installation ----------------------------- 

timedatectl set-ntp true

mount $ROOTDEV /mnt
mount --mkdir $BOOTDEV /mnt/boot

sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
sed -i "s/#Color/Color/g" /etc/pacman.conf
sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/g" /etc/makepkg.conf

pacman -Syy --noconfirm archlinux-keyring

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
	"pipewire-pulse"
	"wireplumber"
	"sof-firmware"
)

FONT_PKGS=(
	"freetype2"
	"fontconfig"
	"ttf-jetbrains-mono-nerd"
	"noto-fonts-emoji"
)

SYSTEM_PKGS=(
	"brightnessctl" # Manage brightness
	"zsh" # Z Shell
	"cifs-utils" # Mount Common Internet File System
	"ntfs-3g" # Mount New Technology File System
	"eza" # ls alternative
	"bat" # cat alternative
	"ripgrep" # grep alternative
	"wget" # Retrieve content
	"git" # Git
	"man" # Manual
	"zip" # Zip files
	"unzip" # Unzip files
	"jq" # JSON Processor
	"bc" # Basic Calculator
)

PYTHON_PKGS=(
	"python-pip" # Install Python modules/packages
	"imagemagick" # Pywal dependency
	"python-pywal" # Pywal
)

CUSTOM_PKGS=(
	"hyprland" # Wayland compositor
	"waybar" # Wayland status bar
	"hyprpaper" # Wayland wallpaper tool
	"hyprlock" # Wayland locking utility
	"grim" # Wayland screenshot tool
	"slurp" # Wayland region selector
	"wl-clipboard" # Wayland clipboard utilities
	"rofi-wayland" # Wayland fork of rofi
	"ly" # TUI Display Manager
	"dunst" # Notifications
	"kitty" # Terminal Emulator
	"neovim" # Text Editor
	"zathura-pdf-mupdf" # PDF Reader
	"github-cli" # Github CLI
	"fastfetch" # System info
	"powertop" # Power consumption monitor
	"btop" # System resources monitor
	"firefox" # Web Browser
)

LSP_PKGS=(
	"nodejs" # TSServer dependency
	"npm" # TSServer dependency
	"typescript-language-server" # TS/JS Server
	"rust-analyzer" # Rust Language Server
	"clang" # C-Family Language Server
	"pyright" # Python Language Server
	"lua-language-server" # Lua Language Server
)

PKGS=(${BASE_PKGS[@]} ${BOOT_PKGS[@]} ${NETWORK_PKGS[@]} ${BLUETOOTH_PKGS[@]} ${AUDIO_PKGS[@]} ${GPU_PKGS[@]} ${FONT_PKGS[@]} ${SYSTEM_PKGS[@]} ${PYTHON_PKGS[@]} ${CUSTOM_PKGS[@]} ${LSP_PKGS[@]} $MICROCODE_PKG)

until pacstrap /mnt "${PKGS[@]}"; do
	echo -e "\e[4;95mRetry?\e[0m"
	
	select retry in Yes No; do
		case $retry in
			Yes) break;;
			No) break 2;;
		esac
	done
done

genfstab -U /mnt >> /mnt/etc/fstab

cat << EOF > /mnt/installation.sh
# Pacman configuration
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
sed -i "s/#Color/Color/g" /etc/pacman.conf
sed -i "s/#ParallelDownloads/ParallelDownloads/g" /etc/pacman.conf
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/g" /etc/makepkg.conf

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

rm \$0

exit
EOF

arch-chroot /mnt /bin/bash installation.sh

# ----------------------------- Customization ----------------------------- 

cat << 'EOF' > /mnt/home/$USERNAME/customization.sh
AUR_PKGS=(
	"vscode-langservers-extracted" # HTML/CSS/JSON/ESLint language servers extracted from vscode
)

# Tool to switch between GPU modes on Optimus systems
if [ "__GPU_BRAND__" == "NVIDIA" ]; then AUR_PKGS+=("envycontrol"); fi

# Automatic CPU speed & power optimizer for Linux
if [ "__POWER_OPTIMIZER__" == "YES" ]; then AUR_PKGS+=("auto-cpufreq"); fi

# Install AUR packages
for aurpkg in "${AUR_PKGS[@]}"; do
	git clone https://aur.archlinux.org/$aurpkg.git
    sudo chmod 777 $aurpkg
	cd $aurpkg
	makepkg -si --noconfirm
	cd ..
	sudo rm -rf $aurpkg
done

# Configure power management tools
if [ "__POWER_OPTIMIZER__" == "YES" ]; then sudo auto-cpufreq --install; fi
if [ "__GPU_BRAND__" == "NVIDIA" ]; then sudo envycontrol -s hybrid --rtd3 3; fi

# Change default shell
sudo chsh -s /bin/zsh $USER

# Make config folder and prayer time history folder
mkdir -p $HOME/.config
mkdir $HOME/.config/prayerhistory

# Download dotfiles
cd $HOME
git clone https://github.com/oversys/dotfiles.git

# Configure Hyprland
mv $HOME/dotfiles/hypr $HOME/.config/
for script in $HOME/.config/hypr/scripts/*.sh; do sudo chmod 777 $script; done

if [ -n "__PRAYER_COUNTRY__" ] && [ -n "__PRAYER_CITY__" ]; then
	sed -i "s/__COUNTRY__/__PRAYER_COUNTRY__/" $HOME/.config/hypr/scripts/prayer.sh
	sed -i "s/__CITY__/__PRAYER_CITY__/" $HOME/.config/hypr/scripts/prayer.sh
	sed -i "s/__METHOD__/__PRAYER_METHOD__/" $HOME/.config/hypr/scripts/prayer.sh
fi

# Configure Waybar
mv $HOME/dotfiles/waybar $HOME/.config/

# Configure kitty
mv $HOME/dotfiles/kitty $HOME/.config/

# Configure ZSH
git clone https://github.com/zsh-users/zsh-autosuggestions.git $HOME/.zsh/zsh-autosuggestions
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting $HOME/.zsh/fast-syntax-highlighting
mv $HOME/dotfiles/.zshrc $HOME/

# Configure neovim
mv $HOME/dotfiles/nvim $HOME/.config/

# Configure dunst
mv $HOME/dotfiles/dunst $HOME/.config/

# Configure rofi
mv $HOME/dotfiles/rofi $HOME/.config/

# Configure fastfetch 
mv $HOME/dotfiles/fastfetch $HOME/.config/

# Configure zathura
mv $HOME/dotfiles/zathura $HOME/.config/

# Configure ly
sudo mv $HOME/dotfiles/ly /etc/
sudo systemctl enable ly.service

# Configure Firefox
firefox --headless --first-startup &
FIREFOX_PID=$!

MOZILLA_DIR="$HOME/.mozilla/firefox"
PROFILE_PATTERN="*.default-release"

while [ -z "$(find $MOZILLA_DIR -maxdepth 1 -type d -name $PROFILE_PATTERN 2>/dev/null)" ]; do
    sleep 1
done

PROFILE_DIR=$(ls -d $MOZILLA_DIR/*.default-release)
mv $HOME/dotfiles/firefox/* $PROFILE_DIR
kill $FIREFOX_PID

# Wallpapers
git clone https://github.com/oversys/wallpapers.git
mv $HOME/wallpapers/wallpapers $HOME/.config/

# Pywal templates
mv $HOME/dotfiles/wal $HOME/.config/

# Install Arabic font(s)
FONTS_DIR="/usr/local/share/fonts"
sudo mkdir -p $FONTS_DIR

for font in "__SELECTED_ARABIC_FONTS__"; do
	case $font in
		"SST Arabic") font_archive="SST-Arabic.zip";;
		"RB") font_archive="RB.zip";;
		"18 Khebrat Musamim") font_archive="khebrat-musamim.zip";;
		"Amiri") font_archive="Amiri.zip";;
		"Noto Naskh Arabic") font_archive="Noto-Naskh-Arabic.zip";;
		"SF Arabic") font_archive"SF-Arabic.zip";;
	esac

	wget https://github.com/oversys/auto-arch/raw/main/resources/fonts/$font_archive
	sudo mv $font_archive $FONTS_DIR
	sudo unzip $FONTS_DIR/$font_archive -d $FONTS_DIR
	sudo rm $FONTS_DIR/$font_archive
done

if [ "__DEFAULT_ARABIC_FONT__" != "SST Arabic" ]; then
	sed -i "s/SST Arabic/__DEFAULT_ARABIC_FONT__/" $HOME/dotfiles/fonts.conf
fi
sudo mv $HOME/dotfiles/fonts.conf /etc/fonts/local.conf

# Install English fonts
wget https://github.com/oversys/auto-arch/raw/main/resources/fonts/Noto-English.zip
sudo mv Noto-English.zip $FONTS_DIR
sudo unzip $FONTS_DIR/Noto-English.zip -d $FONTS_DIR
sudo rm $FONTS_DIR/Noto-English.zip

# Install GRUB theme
wget https://github.com/oversys/auto-arch/raw/main/resources/arch.tar
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
wget https://github.com/oversys/auto-arch/raw/main/resources/macOSBigSur.tar.gz
tar -xf macOSBigSur.tar.gz
rm macOSBigSur.tar.gz
sudo mv macOSBigSur /usr/share/icons/

sudo sed -i "s/Inherits=Adwaita/Inherits=macOSBigSur/g" /usr/share/icons/default/index.theme

rm -rf $HOME/dotfiles $HOME/wallpapers $0

exit
EOF

sed -i "s|__GPU_BRAND__|$GPU_BRAND|g; s|__POWER_OPTIMIZER__|$POWER_OPTIMIZER|g; s|__PRAYER_COUNTRY__|$PRAYER_COUNTRY|g; s|__PRAYER_CITY__|$PRAYER_CITY|g; s|__PRAYER_METHOD__|${PRAYER_METHOD%% *}|g; s|__SELECTED_ARABIC_FONTS__|$(printf '"%s" ' "${SELECTED_ARABIC_FONTS[@]}")|g; s|__DEFAULT_ARABIC_FONT__|$DEFAULT_ARABIC_FONT|g;" /mnt/home/$USERNAME/customization.sh

arch-chroot /mnt /bin/su -c "cd; bash customization.sh" $USERNAME -

# ----------------------------- Complete ----------------------------- 

msgbox "Arch Linux has been installed successfully on this machine."
