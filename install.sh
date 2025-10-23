#!/bin/bash

clear

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
WARNING="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/01-Hyprland-Install-Scripts-$(date +%d-%H%M%S).log"

# Check if running as root. If root, script will exit
if [[ $EUID -eq 0 ]]; then
    echo "${ERROR}  This script should ${WARNING}NOT${RESET} be executed as root!! Exiting......." | tee -a "$LOG"
    printf "\n%.0s" {1..2} 
    exit 1
fi

# Check if PulseAudio package is installed
if pacman -Qq | grep -qw '^pulseaudio$'; then
    echo "$ERROR PulseAudio is detected as installed. Uninstall it first or edit install.sh on line 211 (execute_script 'pipewire.sh')." | tee -a "$LOG"
    printf "\n%.0s" {1..2} 
    exit 1
fi

# Check if base-devel is installed
if pacman -Q base-devel &> /dev/null; then
    echo "base-devel is already installed."
else
    echo "$NOTE Install base-devel.........."

    if sudo pacman -S --noconfirm base-devel; then
        echo "👌 ${OK} base-devel has been installed successfully." | tee -a "$LOG"
    else
        echo "❌ $ERROR base-devel not found nor cannot be installed."  | tee -a "$LOG"
        echo "$ACTION Please install base-devel manually before running this script... Exiting" | tee -a "$LOG"
        exit 1
    fi
fi

# Não precisamos mais do whiptail, então a verificação foi removida.

clear

printf "\n%.0s" {1..2}  
printf "\n%.0s" {1..1} 

echo ":: Starting Hyprland installation..." | tee -a "$LOG"
echo "👌 ${OK} ${SKY_BLUE}Continuing with the installation...${RESET}" | tee -a "$LOG"

sleep 2
printf "\n%.0s" {1..1}

# install pciutils if detected not installed. Necessary for detecting GPU
if ! pacman -Qs pciutils > /dev/null; then
    echo "${NOTE} - pciutils is not installed. Installing..." | tee -a "$LOG"
    sudo pacman -S --noconfirm pciutils
    printf "\n%.0s" {1..1}
fi

# Path to the install-scripts directory
script_directory=install-scripts

# Function to execute a script if it exists and make it executable
execute_script() {
    local script="$1"
    local script_path="$script_directory/$script"
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        if [ -x "$script_path" ]; then
            env "$script_path"
        else
            echo "Failed to make script '$script' executable."
        fi
    else
        echo "Script '$script' not found in '$script_directory'."
    fi
}


# --- DEFINA SUAS OPÇÕES AQUI ---
# Estas são as opções que antes eram perguntadas.
# Mude para "ON" para instalar ou "OFF" para pular.

echo "${INFO} Setting hardcoded installation options..." | tee -a "$LOG"

gtk_themes="ON"     # Instalar temas GTK? (necessário para função Dark/Light)
bluetooth="ON"      # Configurar Bluetooth?
thunar="ON"         # Instalar gerenciador de arquivos Thunar?
quickshell="ON"     # Instalar quickshell (visão geral de desktop)?
sddm="ON"           # Instalar e configurar o gerenciador de login SDDM?
sddm_theme="ON"     # Baixar e Instalar tema SDDM adicional?
xdph="ON"           # Instalar XDG-DESKTOP-PORTAL-HYPRLAND (para compartilhamento de tela)?
zsh="ON"            # Instalar zsh com Oh-My-Zsh?

# As opções abaixo serão detectadas automaticamente
input_group="OFF"
nvidia="OFF"        # (Não usado no script original, mas mantido para referência)
nouveau="OFF"       # (Não usado no script original, mas mantido para referência)

# --- Fim das Opções ---


# Check if yay or paru is installed
echo "${INFO} - Checking if yay or paru is installed"
if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
    echo "${CAT} - Neither yay nor paru found. ${GREEN}Installing 'yay' automatically...${RESET}" | tee -a "$LOG"
    aur_helper="yay" # Escolha codificada
else
    echo "${NOTE} - AUR helper is already installed. Skipping AUR helper selection."
    if command -v yay &>/dev/null; then
        echo "${INFO} - 'yay' detected." | tee -a "$LOG"
        aur_helper="yay"
    elif command -v paru &>/dev/null; then
        echo "${INFO} - 'paru' detected, uninstalling..." | tee -a "$LOG"
        paru -R paru
        aur_helper="yay"
    fi
fi

# List of services to check for active login managers
services=("gdm.service" "gdm3.service" "lightdm.service" "lxdm.service")

# Function to check if any login services are active
check_services_running() {
    active_services=()  # Array to store active services
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            active_services+=("$svc")  
        fi
    done

    if [ ${#active_services[@]} -gt 0 ]; then
        return 0  
    else
        return 1  
    fi
}

if check_services_running; then
    active_list=$(printf "%s\n" "${active_services[@]}")
    echo "${WARN} Active login manager(s) detected: $active_list" | tee -a "$LOG"
    echo "${WARN} Disabling SDDM and SDDM theme installation to avoid conflicts." | tee -a "$LOG"
    echo "${WARN} Uninstall or disable the above services if you want to use SDDM." | tee -a "$LOG"
    sddm="OFF"
    sddm_theme="OFF"
fi

# Check if NVIDIA GPU is detected
if lspci | grep -i "nvidia" &> /dev/null; then
    echo "${INFO} NVIDIA GPU detected." | tee -a "$LOG"
    # O script original adicionava opções 'nvidia' e 'nouveau' mas nunca as usava.
    # nvidia="ON"
    # nouveau="ON"
fi

# Add 'input_group' option if user is not in input group
if ! groups "$(whoami)" | grep -q '\binput\b'; then
    echo "${INFO} User is not in the 'input' group. Enabling option to add them (required for waybar)." | tee -a "$LOG"
    input_group="ON"
fi


# Build the options array based on our hardcoded choices
echo "${INFO} Final selected installation options:" | tee -a "$LOG"
options=()
if [[ "$gtk_themes" == "ON" ]]; then options+=("gtk_themes"); echo " - GTK themes"; fi
if [[ "$bluetooth" == "ON" ]]; then options+=("bluetooth"); echo " - Bluetooth"; fi
if [[ "$thunar" == "ON" ]]; then options+=("thunar"); echo " - Thunar file manager"; fi
if [[ "$quickshell" == "ON" ]]; then options+=("quickshell"); echo " - Quickshell overview"; fi
if [[ "$sddm" == "ON" ]]; then options+=("sddm"); echo " - SDDM login manager"; fi
if [[ "$sddm_theme" == "ON" ]]; then options+=("sddm_theme"); echo " - SDDM theme"; fi
if [[ "$xdph" == "ON" ]]; then options+=("xdph"); echo " - XDG Desktop Portal Hyprland (screen sharing)"; fi
if [[ "$zsh" == "ON" ]]; then options+=("zsh"); echo " - Zsh shell"; fi
if [[ "$input_group" == "ON" ]]; then options+=("input_group"); echo " - Add user to input group"; fi

echo "---" | tee -a "$LOG"
sleep 2 


printf "\n%.0s" {1..1}

# Ensuring base-devel is installed
execute_script "00-base.sh"
sleep 1
execute_script "pacman.sh"
sleep 1

# Execute AUR helper script after other installations if applicable

execute_script "yay.sh"

sleep 1

# Run the Hyprland related scripts
echo "${INFO} Installing ${SKY_BLUE}additional packages...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "01-hypr-pkgs.sh"

echo "${INFO} Installing ${SKY_BLUE}pipewire and pipewire-audio...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "pipewire.sh"

echo "${INFO} Installing ${SKY_BLUE}necessary fonts...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "fonts.sh"

echo "${INFO} Installing ${SKY_BLUE}Hyprland...${RESET}"
sleep 1
execute_script "hyprland.sh"


# Loop through selected options
for option in "${options[@]}"; do
    case "$option" in
        sddm)
            # A verificação de conflito já foi feita acima.
            echo "${INFO} Installing and configuring ${SKY_BLUE}SDDM...${RESET}" | tee -a "$LOG"
            execute_script "sddm.sh"
            ;;
        gtk_themes)
            echo "${INFO} Installing ${SKY_BLUE}GTK themes...${RESET}" | tee -a "$LOG"
            execute_script "gtk_themes.sh"
            ;;
        input_group)
            echo "${INFO} Adding user into ${SKY_BLUE}input group...${RESET}" | tee -a "$LOG"
            execute_script "InputGroup.sh"
            ;;
        quickshell)
            echo "${INFO} Installing ${SKY_BLUE}quickshell for Desktop Overview...${RESET}" | tee -a "$LOG"
            execute_script "quickshell.sh"
            ;;
        xdph)
            echo "${INFO} Installing ${SKY_BLUE}xdg-desktop-portal-hyprland...${RESET}" | tee -a "$LOG"
            execute_script "xdph.sh"
            ;;
        bluetooth)
            echo "${INFO} Configuring ${SKY_BLUE}Bluetooth...${RESET}" | tee -a "$LOG"
            execute_script "bluetooth.sh"
            ;;
        thunar)
            echo "${INFO} Installing ${SKY_BLUE}Thunar file manager...${RESET}" | tee -a "$LOG"
            execute_script "thunar.sh"
            execute_script "thunar_default.sh"
            ;;
        sddm_theme)
            echo "${INFO} Downloading & Installing ${SKY_BLUE}Additional SDDM theme...${RESET}" | tee -a "$LOG"
            execute_script "sddm_theme.sh"
            ;;
        zsh)
            echo "${INFO} Installing ${SKY_BLUE}zsh with Oh-My-Zsh...${RESET}" | tee -a "$LOG"
            execute_script "zsh.sh"
            ;;
        *)
            echo "Unknown option: $option" | tee -a "$LOG"
            ;;
    esac
done

sleep 1
# copy fastfetch config if arch.png is not present
if [ ! -f "$HOME/.config/fastfetch/arch.png" ]; then
    cp -r assets/fastfetch "$HOME/.config/"
fi

clear

# final check essential packages if it is installed
echo "${INFO} Verifying ${SKY_BLUE}essential packages$...{RESET}" | tee -a "$LOG"
execute_script "02-Final-Check.sh"

execute_script "03-dotfiles.sh"

execute_script "04-adjustments.sh"

printf "\n%.0s" {1..1}

# Check if hyprland or hyprland-git is installed
if pacman -Q hyprland &> /dev/null || pacman -Q hyprland-git &> /dev/null; then
    printf "\n ${OK} 👌 Hyprland is installed. However, some essential packages may not be installed. Please see above!"
    printf "\n${CAT} Ignore this message if it states ${YELLOW}All essential packages${RESET} are installed as per above\n"
    sleep 2
    printf "\n%.0s" {1..2}


    printf "\n${NOTE} You can start Hyprland by typing ${SKY_BLUE}Hyprland${RESET} (IF SDDM is not installed) (note the capital H!).\n"
    printf "\n${NOTE} However, it is ${YELLOW}highly recommended to reboot${RESET} your system.\n\n"
    
    printf "\n${CAT} Installation complete. Please reboot your system now (e.g. 'sudo reboot').\n"

else
    # Print error message if neither package is installed
    printf "\n${WARN} Hyprland is NOT installed. Please check 00_CHECK-time_installed.log and other files in the Install-Logs/ directory..."
    printf "\n%.0s" {1..3}
    exit 1
fi


printf "\n%.0s" {1..2}