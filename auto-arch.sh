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
	local MSG="$1"
	local MSG_LEN=${#MSG}

	# Get terminal size
	local TERM_LINES=$(tput lines)
	local TERM_COLS=$(tput cols)

	local WIDTH=$(( TERM_COLS - 8 ))

	local MAX_WIDTH=80
	if [ $WIDTH -gt $MAX_WIDTH ]; then
		WIDTH=$MAX_WIDTH
	fi

	# Prevent message box from being too wide
	if [ $WIDTH -gt $(( MSG_LEN + 10 )) ]; then
		WIDTH=$(( MSG_LEN + 10 ))
	fi

	local TEXT_WIDTH=$(( WIDTH - 4 ))
	local TEXT_LINES=$(( (MSG_LEN + TEXT_WIDTH - 1) / TEXT_WIDTH ))

	local HEIGHT=$(( TEXT_LINES + 7 ))

	if [ $HEIGHT -gt $(( TERM_LINES - 2 )) ]; then
		HEIGHT=$(( TERM_LINES - 2 ))
	fi

	whiptail --title "$title" --msgbox "$MSG" $HEIGHT $WIDTH
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
	local TOSELECT=$1
	shift

	local OPTIONS=()
	local MAX_LEN=${#TOSELECT}

	for OPTION in "$@"; do
		OPTIONS+=("${OPTION}" "")

		local OPTION_LEN=${#OPTION}

		if [ $OPTION_LEN -gt $MAX_LEN ]; then
			MAX_LEN=$OPTION_LEN
		fi
	done

	local NUM_ITEMS=$#

	# Get terminal size
	local TERM_LINES=$(tput lines)
	local TERM_COLS=$(tput cols)

	local WIDTH=$(( MAX_LEN + 15 ))

	if [ $WIDTH -gt $(( TERM_COLS - 4 )) ]; then
		WIDTH=$(( TERM_COLS - 4 ))
	fi

	local LIST_HEIGHT=$NUM_ITEMS
	local HEIGHT=$(( LIST_HEIGHT + 8 ))

	if [ $HEIGHT -gt $(( TERM_LINES - 4 )) ]; then
		HEIGHT=$(( TERM_LINES - 4 ))
		LIST_HEIGHT=$(( HEIGHT - 8 ))
	fi

	whiptail --title "$title" --menu "Select $TOSELECT:" $HEIGHT $WIDTH $LIST_HEIGHT "${OPTIONS[@]}" 3>&1 1>&2 2>&3
}

select_from_checklist() {
	local TOSELECT=$1
	shift

	local ITEMS=()
	local MAX_LEN=0

	for ITEM in "$@"; do
		ITEMS+=("${ITEM}" "OFF")

		local ITEM_LEN=${#ITEM}

		if [ $ITEM_LEN -gt $MAX_LEN ]; then
			MAX_LEN=$ITEM_LEN
		fi
	done

	local NUM_ITEMS=$#

	# Get terminal size
	local TERM_LINES=$(tput lines)
	local TERM_COLS=$(tput cols)

	local WIDTH=$(( MAX_LEN + 15 ))

	local MIN_WIDTH=35

	if [ $WIDTH -lt $MIN_WIDTH ]; then
		WIDTH=$MIN_WIDTH
	fi

	if [ $WIDTH -gt $(( TERM_COLS - 4 )) ]; then
		WIDTH=$(( TERM_COLS - 4 ))
	fi

	local LIST_HEIGHT=$NUM_ITEMS
	local HEIGHT=$(( LIST_HEIGHT + 8 ))

	if [ $HEIGHT -gt $(( TERM_LINES - 4 )) ]; then
		HEIGHT=$(( TERM_LINES - 4 ))
		LIST_HEIGHT=$(( HEIGHT - 8 ))
	fi

	# whiptail --title "$title" --noitem --checklist "Select $TOSELECT" $HEIGHT $WIDTH $LIST_HEIGHT "${ITEMS[@]}" 3>&1 1>&2 2>&3
	whiptail --title "$title" --noitem --checklist "Select $TOSELECT" 0 0 0 "${ITEMS[@]}" 3>&1 1>&2 2>&3
}

# Select boot partition
BOOTDEV=$(select_partition "BOOT")
if [ $? -ne 0 ]; then exit; fi

# Select root partition
ROOTDEV=$(select_partition "ROOT")
if [ $? -ne 0 ]; then exit; fi

# Select region
REGIONS=$(awk '/^[^#]/ { split($3, a, "/"); print a[1] }' /usr/share/zoneinfo/zone.tab | sort -u)
SELECTED_REGION=$(select_from_menu "Region" $REGIONS)
if [ $? -ne 0 ]; then exit; fi

# Select city
CITIES=$(find /usr/share/zoneinfo/${SELECTED_REGION}/ -type f | sed "s|/usr/share/zoneinfo/${SELECTED_REGION}/||")
SELECTED_CITY=$(select_from_menu "City" $CITIES)
if [ $? -ne 0 ]; then exit; fi

# Select locales
LOCALES=($(sed -nE '/^#en_US\.UTF-8 /d; s/^#([a-zA-Z_]+\.UTF-8).*/\1/p' /etc/locale.gen))
SELECTED_LOCALES=$(select_from_checklist "additional locales\n(en_US.UTF-8 is always enabled)" "${LOCALES[@]}")
if [ $? -ne 0 ]; then exit; fi

readarray -t SELECTED_LOCALES < <(xargs -n1 <<< "$SELECTED_LOCALES")
printf -v JOINED_LOCALES '%s, ' "${SELECTED_LOCALES[@]}"

# Select CPU brand
CPU_BRANDS=("Intel" "AMD" "Skip CPU microcode installation")
CPU_BRAND=$(select_from_menu "CPU brand" "${CPU_BRANDS[@]}")
if [ $? -ne 0 ]; then exit; fi

case $CPU_BRAND in
	Intel) MICROCODE_PKG="intel-ucode";;
	AMD) MICROCODE_PKG="amd-ucode";;
esac

# Select GPU brand
GPU_BRANDS=("NVIDIA" "AMD" "Intel" "Skip GPU driver installation")
GPU_BRAND=$(select_from_menu "GPU brand" "${GPU_BRANDS[@]}")
if [ $? -ne 0 ]; then exit; fi

case $GPU_BRAND in
	Intel) GPU_PKGS=("xf86-video-intel");;
	NVIDIA) GPU_PKGS=("nvidia" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils");;
	AMD) GPU_PKGS=("xf86-video-amdgpu" "vulkan-radeon" "lib32-vulkan-radeon");;
esac

# Install power optimizer
if whiptail --title "$title" --yesno "Install auto-cpufreq?" 0 0; then POWER_OPTIMIZER="YES"; else POWER_OPTIMIZER="NO"; fi

# Select Wayland compositor
COMPOSITORS=("dwl" "Hyprland")
SELECTED_COMPOSITOR=$(select_from_menu "Wayland compositor" "${COMPOSITORS[@]}")
if [ $? -ne 0 ]; then exit; fi

if [ "$SELECTED_COMPOSITOR" == "dwl" ]; then
	COMPOSITOR_PKGS=(
		"wayland" # Core Wayland protocol libraries
		"wayland-protocols" # Extra Wayland protocol definitions
		"xorg-xwayland" # Compatibility layer for X11 applications
		"wlroots0.20" # Modular Wayland compositor library used by DWL
		"pkgconf" # DWL compile-time dependency
		"libinput" # Input device handling library
		"libxcb" # X11 client-side library
		"libxkbcommon" # Keymap handling library

		"waybar" # Wayland status bar
		"swaybg" # Wayland wallpaper tool
		"gtklock" # Wayland locking utility
		"foot" # Terminal Emulator
		"rofi" # Application search
		"dunst" # Notifications
		"libnotify" # Notifications
	)
elif [ "$SELECTED_COMPOSITOR" == "Hyprland" ]; then
	COMPOSITOR_PKGS=(
		"hyprland" # Wayland compositor
		"waybar" # Wayland status bar
		"hyprpaper" # Wayland wallpaper tool
		"hyprlock" # Wayland locking utility
		"kitty" # Terminal Emulator
		"rofi" # Application search
		"dunst" # Notifications
		"libnotify" # Notifications
	)
fi

# Select default Arabic font
ARABIC_FONTS=("YouTube Sans Arabic" "IBM Plex Sans Arabic" "RB" "SST Arabic" "Amiri" "Noto Naskh Arabic" "SF Arabic" "18 Khebrat Musamim" "Skip Arabic font installation")
DEFAULT_ARABIC_FONT=$(select_from_menu "default Arabic font" "${ARABIC_FONTS[@]}")
if [ $? -ne 0 ]; then exit; fi

# Select Arabic fonts to install
if [ "$DEFAULT_ARABIC_FONT" != "Skip Arabic font installation" ]; then
	readarray -t CHECKLIST_FONTS < <(printf '%s\n' "${ARABIC_FONTS[@]}" | grep -vF -e "$DEFAULT_ARABIC_FONT" -e "Skip Arabic font installation")

	SELECTED_ARABIC_FONTS=$(select_from_checklist "Arabic fonts" "${CHECKLIST_FONTS[@]}")
	if [ $? -ne 0 ]; then exit; fi
	
	readarray -t SELECTED_ARABIC_FONTS < <(xargs -n1 <<< "$SELECTED_ARABIC_FONTS")
	SELECTED_ARABIC_FONTS+=("$DEFAULT_ARABIC_FONT")

	printf -v JOINED_ARABIC_FONTS '%s, ' "${SELECTED_ARABIC_FONTS[@]}"
fi

msgbox "The following prompts will ask you to enter location information (country and city), which is needed for location-dependent scripts (prayer.sh, weather.sh). If this information is not entered, the location will be fetched automatically based on IP every time the scripts are run.\n\nTo fetch prayer times from your masjid (mawaqit.net), you can instead enter your masjid ID in prayer.sh (recommended). If neither location nor masjid ID are entered, the location will be fetched automatically based on IP."

# Enter country (REQUIRED FOR: prayer.sh, weather.sh)
SCRIPT_COUNTRY=$(input_box "Enter two-letter country code (ISO 3166-1 alpha-2):")
if [ $? -ne 0 ]; then exit; fi

if [ -z "$SCRIPT_COUNTRY" ]; then
	msgbox "Location will be fetched automatically from ipinfo.io"
fi

# Enter city (REQUIRED FOR: prayer.sh, weather.sh)
if [ -n "$SCRIPT_COUNTRY" ]; then
	SCRIPT_CITY=$(input_box "Enter city name (at least 1000 inhabitants, from GeoNames cities1000 DB):")
	if [ $? -ne 0 ]; then exit; fi
	
	if [ -z "$SCRIPT_CITY" ]; then
		msgbox "Location will be fetched automatically from ipinfo.io"
	fi
fi

# Enter method for calculating prayer times (REQUIRED FOR: prayer.sh)
PRAYER_METHODS=(
	"1 - Umm Al-Qura University, Makkah"
	"2 - Muslim World League (DEFAULT)"
	"3 - Egyptian General Authority of Survey"
	"4 - University of Islamic Studies, Karachi"
	"5 - Fiqh Council of North America, USA (aka Islamic Society of North America)"
	"6 - Fiqh Council of North America, Canada"
	"7 - Muslims of France"
	"8 - Islamic Religious Council of Singapore"
	"9 - Dubai (unofficial)"
	"10 - Qatar"
	"11 - Kuwait"
)
PRAYER_METHOD=$(select_from_menu "method for calculating prayer times" "${PRAYER_METHODS[@]}")
if [ -z "$PRAYER_METHOD" ]; then
	msgbox "Selected default method: 2 - Muslim World League"
fi

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
SELECTED ADDITIONAL LOCALES: ${JOINED_LOCALES%, }
CPU BRAND: $CPU_BRAND
GPU BRAND: $GPU_BRAND
INSTALL POWER OPTIMIZER (auto-cpufreq)?: $POWER_OPTIMIZER
WAYLAND COMPOSITOR: $SELECTED_COMPOSITOR
DEFAULT ARABIC FONT: $DEFAULT_ARABIC_FONT
SELECTED ARABIC FONTS: ${JOINED_ARABIC_FONTS%, }
COUNTRY: $SCRIPT_COUNTRY
CITY: $SCRIPT_CITY
PRAYER TIMES CALCULATION METHOD: $PRAYER_METHOD
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
	"rsync" # File transfer utility
	"wget" # Retrieve content
	"git" # Git
	"man" # Manual
	"zip" # Zip files
	"unzip" # Unzip files
	"jq" # JSON Processor
	"bc" # Basic Calculator
	"openssh" # Secure Shell
)

PYTHON_PKGS=(
	"python-pip" # Install Python modules/packages
	"imagemagick" # Pywal dependency
	"python-pywal" # Pywal
)

CUSTOM_PKGS=(
	"eza" # ls alternative
	"bat" # cat alternative
	"ripgrep" # grep alternative
	"fzf" # Fuzzy finder
	"grim" # Wayland screenshot tool
	"slurp" # Wayland region selector
	"wl-clipboard" # Wayland clipboard utilities
	"ly" # TUI display manager
	"powertop" # Power consumption monitor
	"btop" # System resources monitor
	"fastfetch" # System info
	"neovim" # Text editor
	"tree-sitter-cli" # Syntax highlighting (for nvim-treesitter)
	"zathura-pdf-mupdf" # PDF reader
	"github-cli" # Github CLI
	"firefox" # Web browser
	"nodejs" # Node.js
	"npm" # npm
)

LSP_PKGS=(
	"clang" # C-Family language server (LLVM)
	"pyright" # Python language server
	"rust-analyzer" # Rust language server
	"typescript-language-server" # TS/JS language server
	"vscode-html-languageserver" # HTML language server
	"vscode-css-languageserver" # CSS language server
	"lua-language-server" # Lua language server
	"bash-language-server" # Bash language server
)

PKGS=(${BASE_PKGS[@]} ${BOOT_PKGS[@]} ${NETWORK_PKGS[@]} ${BLUETOOTH_PKGS[@]} ${AUDIO_PKGS[@]} ${GPU_PKGS[@]} ${FONT_PKGS[@]} ${SYSTEM_PKGS[@]} ${PYTHON_PKGS[@]} ${COMPOSITOR_PKGS[@]} ${CUSTOM_PKGS[@]} ${LSP_PKGS[@]} $MICROCODE_PKG)

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

for locale in ${SELECTED_LOCALES[@]}; do
	sed -i "/^#\${locale//./\\.} /s/^#//" /etc/locale.gen
done

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
	# Add AUR packages here
)

# Tool to switch between GPU modes on Optimus systems (archived on 3 May 2026)
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
if [ "__GPU_BRAND__" == "NVIDIA" ]; then sudo envycontrol -s hybrid --rtd3 3; fi
if [ "__POWER_OPTIMIZER__" == "YES" ]; then sudo auto-cpufreq --install; fi

# Change default shell
sudo chsh -s /bin/zsh $USER

# Make config folder and prayer time history folder
mkdir -p $HOME/.config
mkdir $HOME/.config/prayerhistory

# Download dotfiles
cd $HOME
git clone https://github.com/oversys/dotfiles.git

# Configure Wayland compositor
if [ "__SELECTED_COMPOSITOR__" == "dwl" ]; then
	# Ensure directory exists so dwl can copy .desktop file (for ly display manager)
	sudo mkdir -p /usr/share/wayland-sessions

	# Clone and compile dwl
	git clone https://github.com/oversys/dwl.git $HOME/.config/dwl
	cd $HOME/.config/dwl
	sudo make clean install
	cd $HOME

	# Configure gtklock
	mv $HOME/dotfiles/gtklock $HOME/.config/

	# Configure foot
	mv $HOME/dotfiles/foot $HOME/.config/
elif [ "__SELECTED_COMPOSITOR__" == "Hyprland" ]; then
	# Configure Hyprland
	mv $HOME/dotfiles/hypr $HOME/.config/

	# Configure kitty
	mv $HOME/dotfiles/kitty $HOME/.config/
fi

# Configure scripts
mv $HOME/dotfiles/scripts $HOME/.config/
for script in $HOME/.config/scripts/*.sh; do sudo chmod 777 $script; done

if [ -n "__SCRIPT_COUNTRY__" ] && [ -n "__SCRIPT_CITY__" ]; then
	sed -i "0,/__COUNTRY__/{s/__COUNTRY__/__SCRIPT_COUNTRY__/}" $HOME/.config/scripts/prayer.sh $HOME/.config/scripts/weather.sh
	sed -i "0,/__CITY__/{s/__CITY__/__SCRIPT_CITY__/}" $HOME/.config/scripts/prayer.sh $HOME/.config/scripts/weather.sh
	sed -i "0,/__METHOD__/{s/__METHOD__/__PRAYER_METHOD__/}" $HOME/.config/scripts/prayer.sh
fi

# Configure Waybar
mv $HOME/dotfiles/waybar $HOME/.config/

# Configure ZSH
git clone https://github.com/zsh-users/zsh-autosuggestions.git $HOME/.zsh/zsh-autosuggestions
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting $HOME/.zsh/fast-syntax-highlighting
mv $HOME/dotfiles/.zshrc $HOME/

# Configure Neovim
mv $HOME/dotfiles/nvim $HOME/.config/
nvim --headless -c "qa"

# Configure dunst
mv $HOME/dotfiles/dunst $HOME/.config/

# Configure Rofi
mv $HOME/dotfiles/rofi $HOME/.config/

# Configure Fastfetch
mv $HOME/dotfiles/fastfetch $HOME/.config/

# Configure zathura
mv $HOME/dotfiles/zathura $HOME/.config/

# Configure ly
sudo mv $HOME/dotfiles/ly/config.ini /etc/ly/
sudo systemctl enable ly@tty1.service

# Configure Firefox
FIREFOX_DIR="$HOME/.config/mozilla/firefox"
PROFILE_NAME="auto-arch"

firefox --headless --CreateProfile "$PROFILE_NAME"

PROFILE_DIR=$(find "$FIREFOX_DIR" -maxdepth 1 -type d -name "*.$PROFILE_NAME" | head -n 1)

sudo mv $HOME/dotfiles/firefox/autoconfig/load-scripts-prefs.js /usr/lib/firefox/defaults/pref/
sudo mv $HOME/dotfiles/firefox/autoconfig/load-scripts.js /usr/lib/firefox/

rmdir $HOME/dotfiles/firefox/autoconfig

mv $HOME/dotfiles/firefox/* $PROFILE_DIR

# Wallpapers
git clone --depth 1 https://github.com/oversys/wallpapers.git
mv $HOME/wallpapers/wallpapers $HOME/.config/

# Install Arabic font(s)
FONTS_DIR="/usr/local/share/fonts"
sudo mkdir -p $FONTS_DIR

for font in __SELECTED_ARABIC_FONTS__; do
	case $font in
		"YouTube Sans Arabic") font_archive="YouTube-Sans-Arabic.zip";;
		"IBM Plex Sans Arabic") font_archive="IBM-Plex-Sans-Arabic.zip";;
		"RB") font_archive="RB.zip";;
		"SST Arabic") font_archive="SST-Arabic.zip";;
		"18 Khebrat Musamim") font_archive="khebrat-musamim.zip";;
		"Amiri") font_archive="Amiri.zip";;
		"Noto Naskh Arabic") font_archive="Noto-Naskh-Arabic.zip";;
		"SF Arabic") font_archive"SF-Arabic.zip";;
	esac

	wget https://github.com/oversys/auto-arch/raw/main/resources/fonts/$font_archive
	sudo mv $font_archive $FONTS_DIR
	sudo unzip -o $FONTS_DIR/$font_archive -d $FONTS_DIR
	sudo rm $FONTS_DIR/$font_archive
done

if [ "__DEFAULT_ARABIC_FONT__" != "YouTube Sans Arabic" ]; then
	sed -i "s/YouTube Sans Arabic/__DEFAULT_ARABIC_FONT__/" $HOME/dotfiles/fonts.conf
fi
sudo mv $HOME/dotfiles/fonts.conf /etc/fonts/local.conf

# Install English fonts
wget https://github.com/oversys/auto-arch/raw/main/resources/fonts/Noto-English.zip
sudo mv Noto-English.zip $FONTS_DIR
sudo unzip $FONTS_DIR/Noto-English.zip -d $FONTS_DIR
sudo rm $FONTS_DIR/Noto-English.zip

# Install custom glyph (flipped star crescent) for Waybar
wget https://github.com/oversys/auto-arch/raw/main/resources/fonts/flipped_star_crescent.ttf
sudo mv flipped_star_crescent.ttf $FONTS_DIR

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

sed -i "s|__GPU_BRAND__|$GPU_BRAND|g; s|__POWER_OPTIMIZER__|$POWER_OPTIMIZER|g; s|__SELECTED_COMPOSITOR__|$SELECTED_COMPOSITOR|g; s|__SCRIPT_COUNTRY__|$SCRIPT_COUNTRY|g; s|__SCRIPT_CITY__|$SCRIPT_CITY|g; s|__PRAYER_METHOD__|${PRAYER_METHOD%% *}|g; s|__SELECTED_ARABIC_FONTS__|$(printf '"%s" ' "${SELECTED_ARABIC_FONTS[@]}")|g; s|__DEFAULT_ARABIC_FONT__|$DEFAULT_ARABIC_FONT|g;" /mnt/home/$USERNAME/customization.sh

arch-chroot /mnt /bin/su -c "cd; bash customization.sh" $USERNAME -

# ----------------------------- Complete ----------------------------- 

msgbox "Arch Linux has been installed successfully on this machine."

