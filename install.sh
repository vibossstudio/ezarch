#!/bin/bash

# ═══════════════════════════════════════════════════════════
#  ARCH LINUX AUTO INSTALLER
#  Cài đặt Arch Linux hoàn toàn tự động qua TTY ArchISO
#  Author: TYNO
# ═══════════════════════════════════════════════════════════

set -euo pipefail
set -E

# Cleanup mounts on exit to avoid leaving /mnt mounted
trap 'umount -R /mnt 2>/dev/null || true' EXIT

# Error handler: print failing command and exit
on_error() {
    local exit_code=$?
    local cmd="${BASH_COMMAND:-unknown}"
    print_error "Lỗi: lệnh '$cmd' trả về mã $exit_code (dòng ${BASH_LINENO[0]})"
    exit $exit_code
}
trap on_error ERR

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Biến toàn cục
LOCALE=""
KEYMAP=""
TIMEZONE=""
ENABLE_NTP=""
HOSTNAME=""
NETWORK_MANAGER=""
DISK=""
BOOT_MODE=""
FILESYSTEM=""
SEPARATE_HOME=""
CREATE_SWAP=""
SWAP_SIZE=""
PARTITION_MODE=""
ROOT_PARTITION=""
EFI_PARTITION=""
SWAP_PARTITION=""
HOME_PARTITION=""
BOOTLOADER=""
CPU_VENDOR=""
GPU_DRIVER=""
USERNAME=""
USER_PASSWORD=""
ENABLE_SUDO=""
SET_ROOT_PASSWORD=""
ROOT_PASSWORD=""
AUTO_MIRROR=""
INSTALL_BASE_DEVEL=""
INSTALL_EDITOR=""
INSTALL_GIT=""
INSTALL_WGET=""
INSTALL_BASH_COMPLETION=""
INSTALL_AUR_HELPER=""
AUR_HELPER=""
INSTALL_DE=""
DESKTOP_ENV=""
DISPLAY_MANAGER=""
ENABLE_LVM=""
ENABLE_LUKS=""
ENABLE_FIREWALL=""
ENABLE_SSH=""
OPTIMIZE_SSD=""

# ═══════════════════════════════════════════════════════════
#  HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════

print_header() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

ask_question() {
    local question="$1"
    local default="$2"
    local answer
    
    if [[ -n "$default" ]]; then
        read -r -p "$(echo -e "${CYAN}❯${NC} ${question} [${BOLD}${default}${NC}]: ")" answer
        echo "${answer:-$default}"
    else
        read -r -p "$(echo -e "${CYAN}❯${NC} ${question}: ")" answer
        echo "$answer"
    fi
}

ask_password() {
    local prompt="$1"
    local password
    local password_confirm
    
    while true; do
        read -r -s -p "$(echo -e "${CYAN}❯${NC} ${prompt}: ")" password
        echo
        read -r -s -p "$(echo -e "${CYAN}❯${NC} Xác nhận mật khẩu: ")" password_confirm
        echo
        
        if [[ "$password" == "$password_confirm" ]]; then
            echo "$password"
            return 0
        else
            print_error "Mật khẩu không khớp. Vui lòng thử lại."
        fi
    done
}

ask_yes_no() {
    local question="$1"
    local default="$2"
    local answer
    
    if [[ "$default" == "yes" ]]; then
        read -r -p "$(echo -e "${CYAN}❯${NC} ${question} [${BOLD}Y/n${NC}]: ")" answer
        answer="${answer:-y}"
    else
        read -r -p "$(echo -e "${CYAN}❯${NC} ${question} [${BOLD}y/N${NC}]: ")" answer
        answer="${answer:-n}"
    fi
    
    [[ "$answer" =~ ^[Yy]$ ]] && echo "yes" || echo "no"
}

# ═══════════════════════════════════════════════════════════
#  KIỂM TRA MÔI TRƯỜNG
# ═══════════════════════════════════════════════════════════

check_environment() {
    print_header "KIỂM TRA MÔI TRƯỜNG"
    # Kiểm tra chạy với quyền root
    if [[ $EUID -ne 0 ]]; then
        print_error "Script này cần chạy với quyền root!"
        exit 1
    fi

    # Thông báo và refresh partition table (nếu đã biết DISK)
    if [[ -n "${DISK:-}" ]]; then
        sleep 1
        partprobe "${DISK}"
    fi
    
    # Xác định tên phân vùng
    if [[ "$DISK" == *nvme* ]]; then
        local prefix="${DISK}p"
    else
        local prefix="${DISK}"
    fi
    
    # Set defaults based on naming convention; after partitioning we'll probe actual names
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        EFI_PARTITION="${prefix}1"
        if [[ "$CREATE_SWAP" == "yes" ]]; then
            SWAP_PARTITION="${prefix}2"
            ROOT_PARTITION="${prefix}3"
            [[ "$SEPARATE_HOME" == "yes" ]] && HOME_PARTITION="${prefix}4"
        else
            ROOT_PARTITION="${prefix}2"
            [[ "$SEPARATE_HOME" == "yes" ]] && HOME_PARTITION="${prefix}3"
        fi
    else
        if [[ "$CREATE_SWAP" == "yes" ]]; then
            SWAP_PARTITION="${prefix}1"
            ROOT_PARTITION="${prefix}2"
            [[ "$SEPARATE_HOME" == "yes" ]] && HOME_PARTITION="${prefix}3"
        else
            ROOT_PARTITION="${prefix}1"
            [[ "$SEPARATE_HOME" == "yes" ]] && HOME_PARTITION="${prefix}2"
        fi
    fi

    # Refresh and verify partition names — handle NVMe p# vs non-p#
    partprobe "${DISK}"
    sleep 1
    # If NVMe, prefer p-suffixed partitions; verify actual devices exist
    if [[ "${DISK}" == *nvme* ]]; then
        if [[ -b "${DISK}p1" ]]; then
            EFI_PARTITION="${DISK}p1"
        fi
        if [[ -b "${DISK}p2" ]]; then
            SWAP_PARTITION="${DISK}p2"
        fi
        if [[ -b "${DISK}p3" ]]; then
            ROOT_PARTITION="${DISK}p3"
        fi
        if [[ -b "${DISK}p4" ]]; then
            HOME_PARTITION="${DISK}p4"
        fi
    else
        if [[ -b "${DISK}1" ]]; then
            EFI_PARTITION="${DISK}1"
        fi
        if [[ -b "${DISK}2" ]]; then
            SWAP_PARTITION="${DISK}2"
        fi
        if [[ -b "${DISK}3" ]]; then
            ROOT_PARTITION="${DISK}3"
        fi
        if [[ -b "${DISK}4" ]]; then
            HOME_PARTITION="${DISK}4"
        fi
    fi
}

# Kiểm tra môi trường trước khi thu thập thông tin
preflight_checks() {
    print_header "KIỂM TRA MÔI TRƯỜNG CƠ BẢN"

    if [[ $EUID -ne 0 ]]; then
        print_error "Script này cần chạy với quyền root!"
        exit 1
    fi

    # Chạy trên ArchISO?
    if [[ ! -f /etc/arch-release ]]; then
        print_error "Script này chỉ chạy trên ArchISO!"
        exit 1
    fi
    print_success "Đang chạy trên ArchISO"

    # Kiểm tra kết nối internet
    print_info "Kiểm tra kết nối internet..."
    if ping -c 1 archlinux.org &> /dev/null; then
        print_success "Kết nối internet OK"
    else
        print_error "Không có kết nối internet!"
        print_info "Vui lòng kết nối internet (dùng iwctl cho WiFi) và thử lại."
        exit 1
    fi

    # Đồng bộ thời gian
    print_info "Đồng bộ thời gian hệ thống..."
    timedatectl set-ntp true
    print_success "Đã đồng bộ thời gian"

    echo
    read -r -p "Nhấn Enter để tiếp tục..."

    # Kiểm tra các công cụ cơ bản (cảnh báo nếu thiếu)
    local cmds=(pacstrap genfstab arch-chroot parted sgdisk grub-install bootctl pacman reflector mkfs.fat mkfs.ext4 mkfs.btrfs mkfs.xfs mkfs.f2fs)
    for c in "${cmds[@]}"; do
        if ! command -v "$c" &> /dev/null; then
            print_warning "$c không tìm thấy; một số bước có thể thất bại nếu thiếu"
        fi
    done
}

# Ensure required commands exist and optionally exit
ensure_required_commands() {
    local required=(pacstrap genfstab arch-chroot parted sgdisk timedatectl pacman wipefs lsblk git makepkg)
    local miss=()
    for c in "${required[@]}"; do
        if ! command -v "$c" &> /dev/null; then
            miss+=("$c")
        fi
    done
    if [[ ${#miss[@]} -gt 0 ]]; then
        print_error "Thiếu công cụ bắt buộc: ${miss[*]}. Cài trước khi chạy script."
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════
#  FORMAT & MOUNT
# ═══════════════════════════════════════════════════════════

format_partitions() {
    print_header "FORMAT PHÂN VÙNG"
    
    if [[ -n "$EFI_PARTITION" ]]; then
        print_info "Format EFI partition..."
        mkfs.fat -F32 "$EFI_PARTITION"
    fi
    
    if [[ -n "$SWAP_PARTITION" ]]; then
        print_info "Setup swap..."
        mkswap "$SWAP_PARTITION"
        swapon "$SWAP_PARTITION"
    fi
    
    print_info "Format root partition ($FILESYSTEM)..."
    case $FILESYSTEM in
        ext4)
            mkfs.ext4 -F "$ROOT_PARTITION"
            ;;
        btrfs)
            mkfs.btrfs -f "$ROOT_PARTITION"
            ;;
        xfs)
            mkfs.xfs -f "$ROOT_PARTITION"
            ;;
        f2fs)
            mkfs.f2fs -f "$ROOT_PARTITION"
            ;;
        *)
            mkfs.ext4 -F "$ROOT_PARTITION"
            ;;
    esac
    
    if [[ -n "$HOME_PARTITION" ]]; then
        print_info "Format home partition..."
        mkfs.ext4 -F "$HOME_PARTITION"
    fi
    
    print_success "Hoàn thành format"
}

mount_partitions() {
    print_header "MOUNT PHÂN VÙNG"
    
    print_info "Mount root..."
    local -a mount_cmd=(mount)
    if [[ "$OPTIMIZE_SSD" == "yes" ]]; then
        mount_cmd+=( -o "noatime,nodiratime" )
    fi
    mount_cmd+=("$ROOT_PARTITION" /mnt)
    "${mount_cmd[@]}"
    
    if [[ -n "$EFI_PARTITION" ]]; then
        print_info "Mount EFI..."
        mkdir -p /mnt/boot/efi
        mount "$EFI_PARTITION" /mnt/boot/efi
    fi
    
    if [[ -n "$HOME_PARTITION" ]]; then
        print_info "Mount home..."
        mkdir -p /mnt/home
        if [[ "$OPTIMIZE_SSD" == "yes" ]]; then
            mount -o noatime,nodiratime "$HOME_PARTITION" /mnt/home
        else
            mount "$HOME_PARTITION" /mnt/home
        fi
    fi
    
    print_success "Hoàn thành mount"
}

# ═══════════════════════════════════════════════════════════
#  CÀI ĐẶT HỆ THỐNG
# ═══════════════════════════════════════════════════════════

update_mirrorlist() {
    if [[ "$AUTO_MIRROR" == "yes" ]]; then
        print_header "CẬP NHẬT MIRRORLIST"
        print_info "Cập nhật mirrorlist với reflector..."
        
        pacman -S --noconfirm --needed reflector
        reflector --country Vietnam,Singapore,Japan,Korea --protocol https --sort rate --save /etc/pacman.d/mirrorlist
        
        print_success "Đã cập nhật mirrorlist"
    fi
}

install_base_system() {
    print_header "CÀI ĐẶT HỆ THỐNG CƠ BẢN"
    ensure_required_commands

    local packages=(base linux linux-firmware)

    # Microcode
    if [[ "$CPU_VENDOR" == "intel" ]]; then
        packages+=(intel-ucode)
    elif [[ "$CPU_VENDOR" == "amd" ]]; then
        packages+=(amd-ucode)
    fi

    # Network tools
    case $NETWORK_MANAGER in
        networkmanager)
            packages+=(networkmanager)
            ;;
        systemd-networkd)
            packages+=(systemd-resolvconf)
            ;;
        iwd)
            packages+=(iwd)
            ;;
    esac

    # Base utilities (respect INSTALL_BASE_DEVEL)
    if [[ "$INSTALL_BASE_DEVEL" == "yes" ]]; then
        packages+=(base-devel)
    fi
    packages+=(sudo man-db man-pages)

    # Editor
    if [[ -n "$INSTALL_EDITOR" ]]; then
        packages+=("$INSTALL_EDITOR")
    fi

    # Additional tools
    [[ "$INSTALL_GIT" == "yes" ]] && packages+=(git)
    [[ "$INSTALL_WGET" == "yes" ]] && packages+=(wget curl)
    [[ "$INSTALL_BASH_COMPLETION" == "yes" ]] && packages+=(bash-completion)

    # GPU drivers
    case $GPU_DRIVER in
        intel)
            packages+=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel)
            ;;
        amd)
            packages+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon)
            ;;
        nvidia-open)
            packages+=(nvidia-open nvidia-utils lib32-nvidia-utils)
            ;;
        nvidia)
            packages+=(nvidia nvidia-utils lib32-nvidia-utils)
            ;;
    esac

    # Firewall
    [[ "$ENABLE_FIREWALL" == "yes" ]] && packages+=(ufw)

    # SSH
    [[ "$ENABLE_SSH" == "yes" ]] && packages+=(openssh)

    print_info "Cài đặt: ${packages[*]}"
    pacstrap /mnt "${packages[@]}"

    print_success "Hoàn thành cài đặt base system"
}

generate_fstab() {
    print_header "TẠO FSTAB"
    
    genfstab -U /mnt > /mnt/etc/fstab
    
    print_success "Đã tạo /etc/fstab"
}

configure_system() {
    print_header "CẤU HÌNH HỆ THỐNG"
    
    # Chroot script
    cat << CHROOT_EOF > /mnt/configure.sh
#!/bin/bash

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Keymap
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Hosts
cat << EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Root password
if [[ "$SET_ROOT_PASSWORD" == "yes" ]]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
else
    passwd -l root
fi

# Create user
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Sudo
    if [[ "$ENABLE_SUDO" == "yes" ]]; then
        echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-installer
    else
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-installer
    fi
    chmod 0440 /etc/sudoers.d/99-installer

# Enable services
systemctl enable fstrim.timer

case $NETWORK_MANAGER in
    networkmanager)
        systemctl enable NetworkManager
        ;;
    systemd-networkd)
        systemctl enable systemd-networkd
        systemctl enable systemd-resolved
        ;;
    iwd)
        systemctl enable iwd
        ;;
esac

[[ "$ENABLE_FIREWALL" == "yes" ]] && systemctl enable ufw
[[ "$ENABLE_SSH" == "yes" ]] && systemctl enable sshd

CHROOT_EOF
    
    chmod +x /mnt/configure.sh
    arch-chroot /mnt /configure.sh
    rm /mnt/configure.sh
    
    print_success "Hoàn thành cấu hình hệ thống"
}

install_bootloader() {
    print_header "CÀI ĐẶT BOOTLOADER"
    
    case $BOOTLOADER in
        grub)
            if [[ "$BOOT_MODE" == "UEFI" ]]; then
                arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
                arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
            else
                arch-chroot /mnt pacman -S --noconfirm grub
                arch-chroot /mnt grub-install --target=i386-pc "$DISK"
            fi
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            ;;
            
        systemd-boot)
            arch-chroot /mnt bootctl --path=/boot/efi install
            
            cat << EOF > /mnt/boot/efi/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /$CPU_VENDOR-ucode.img
initrd  /initramfs-linux.img
options root=$ROOT_PARTITION rw
EOF
            
            cat << EOF > /mnt/boot/efi/loader/loader.conf
default arch
timeout 3
editor  no
EOF
            ;;
            
        none)
            print_warning "Bỏ qua cài đặt bootloader"
            ;;
    esac
    
    print_success "Hoàn thành cài đặt bootloader"
}

install_desktop_environment() {
    if [[ "$INSTALL_DE" != "yes" ]]; then
        return
    fi
    
    print_header "CÀI ĐẶT DESKTOP ENVIRONMENT"
    
    local -a packages=()

    case $DESKTOP_ENV in
        gnome)
            packages+=(gnome gnome-extra)
            ;;
        plasma)
            packages+=(plasma kde-applications)
            ;;
        xfce)
            packages+=(xfce4 xfce4-goodies)
            ;;
        lxqt)
            packages+=(lxqt breeze-icons)
            ;;
        cinnamon)
            packages+=(cinnamon nemo-fileroller)
            ;;
        mate)
            packages+=(mate mate-extra)
            ;;
    esac

    case $DISPLAY_MANAGER in
        gdm)
            packages+=(gdm)
            ;;
        sddm)
            packages+=(sddm)
            ;;
        lightdm)
            packages+=(lightdm lightdm-gtk-greeter)
            ;;
    esac

    arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"

    if [[ "$DISPLAY_MANAGER" != "none" ]]; then
        arch-chroot /mnt systemctl enable "$DISPLAY_MANAGER"
    fi
    
    print_success "Hoàn thành cài đặt Desktop Environment"
}

install_aur_helper() {
    if [[ "$INSTALL_AUR_HELPER" != "yes" ]]; then
        return
    fi
    
    print_header "CÀI ĐẶT AUR HELPER"
    
    print_info "Cài đặt $AUR_HELPER cho user $USERNAME..."
    
    # Tạo script cài AUR helper trong chroot, chạy dưới user thường
    cat << 'AUR_SCRIPT_EOF' > /mnt/install_aur.sh
#!/bin/bash

AUR_HELPER="$1"
USERNAME="$2"

sudo -u "$USERNAME" bash -s -- "$AUR_HELPER" <<'USER_EOF'
AUR_HELPER="$1"
cd /tmp || exit 1

if [[ "$AUR_HELPER" == "yay" ]]; then
    git clone https://aur.archlinux.org/yay.git
    cd yay || exit 1
elif [[ "$AUR_HELPER" == "paru" ]]; then
    git clone https://aur.archlinux.org/paru.git
    cd paru || exit 1
else
    exit 0
fi

# Build và install
makepkg -si --noconfirm

# Cleanup
cd /tmp
rm -rf yay paru

USER_EOF

AUR_SCRIPT_EOF

    chmod +x /mnt/install_aur.sh
    # Ensure build tools available in chroot for AUR helper
    arch-chroot /mnt pacman -S --noconfirm --needed base-devel git || true
    arch-chroot /mnt /install_aur.sh "$AUR_HELPER" "$USERNAME"
    rm /mnt/install_aur.sh
    
    print_success "Đã cài đặt $AUR_HELPER"
}

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════

main() {
    ensure_required_commands
    preflight_checks

    collect_language_settings
    collect_time_settings
    collect_network_settings
    collect_disk_settings
    collect_partition_settings
    collect_bootloader_settings
    collect_driver_settings
    collect_user_settings
    collect_package_settings
    collect_desktop_settings
    collect_advanced_settings
    
    # Sau khi đã có thông tin ổ đĩa, kiểm tra môi trường chi tiết
    check_environment

    confirm_settings
    
    # Thực hiện cài đặt
    if [[ "$PARTITION_MODE" == "auto" ]]; then
        auto_partition
    fi
    # Refresh partition info after auto partitioning
    if [[ "$PARTITION_MODE" == "auto" ]]; then
        partprobe "$DISK"
        sleep 1
        check_environment
    fi
    
    format_partitions
    mount_partitions
    update_mirrorlist
    install_base_system
    generate_fstab
    configure_system
    install_bootloader
    install_desktop_environment
    install_aur_helper
    
    # Hoàn thành
    print_header "HOÀN THÀNH CÀI ĐẶT"
    
    print_success "Arch Linux đã được cài đặt thành công!"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "  Script viết bởi: ${BOLD}TYNO${NC}"
    echo -e "  Cảm ơn bạn đã tin tưởng sử dụng!"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo
    print_info "Bạn có thể:"
    echo "  1. Reboot vào hệ thống mới"
    echo "  2. Kiểm tra cấu hình trong /mnt"
    echo
    
    local reboot_now
    reboot_now=$(ask_yes_no "Reboot ngay bây giờ?" "yes")
    if [[ "$reboot_now" == "yes" ]]; then
        umount -R /mnt
        reboot
    else
        print_info "Nhớ unmount và reboot thủ công:"
        echo "  umount -R /mnt"
        echo "  reboot"
    fi
}

main "$@"

# ═══════════════════════════════════════════════════════════
#  THU THẬP THÔNG TIN
# ═══════════════════════════════════════════════════════════

collect_language_settings() {
    print_header "CÀI ĐẶT NGÔN NGỮ & BÀN PHÍM"
    
    print_info "Các locale phổ biến: en_US.UTF-8, vi_VN.UTF-8, ja_JP.UTF-8, ko_KR.UTF-8"
    LOCALE=$(ask_question "Chọn locale hệ thống" "en_US.UTF-8")
    
    print_info "Các keymap phổ biến: us, vn, uk, de, fr"
    KEYMAP=$(ask_question "Chọn keymap bàn phím" "us")
    
    echo
}

collect_time_settings() {
    print_header "CÀI ĐẶT THỜI GIAN"
    
    print_info "Ví dụ múi giờ: Asia/Ho_Chi_Minh, Asia/Seoul, Europe/London"
    TIMEZONE=$(ask_question "Chọn múi giờ" "Asia/Ho_Chi_Minh")
    
    ENABLE_NTP=$(ask_yes_no "Bật đồng bộ thời gian NTP?" "yes")
    
    echo
}

collect_network_settings() {
    print_header "CÀI ĐẶT MẠNG"
    
    HOSTNAME=$(ask_question "Nhập hostname" "archlinux")
    
    echo
    print_info "Chọn network manager:"
    echo "  1) NetworkManager (khuyến nghị cho desktop)"
    echo "  2) systemd-networkd (nhẹ, phù hợp server)"
    echo "  3) iwd (modern, chỉ WiFi)"
    
    local choice
    choice=$(ask_question "Chọn (1-3)" "1")
    case $choice in
        1) NETWORK_MANAGER="networkmanager" ;;
        2) NETWORK_MANAGER="systemd-networkd" ;;
        3) NETWORK_MANAGER="iwd" ;;
        *) NETWORK_MANAGER="networkmanager" ;;
    esac
    
    echo
}

collect_disk_settings() {
    print_header "CÀI ĐẶT Ổ ĐĨA"
    
    print_info "Danh sách ổ đĩa hiện có:"
    echo
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk
    echo
    
    while true; do
        DISK=$(ask_question "Chọn ổ đĩa cài đặt (vd: sda, nvme0n1)")
        DISK="/dev/$DISK"
        
        if [[ -b "$DISK" ]]; then
            break
        else
            print_error "Ổ đĩa không tồn tại. Vui lòng thử lại."
        fi
    done
    
    print_warning "CẢNH BÁO: Tất cả dữ liệu trên $DISK sẽ bị XÓA!"
    lsblk "$DISK"
    echo
    
    local confirm
    confirm=$(ask_yes_no "Bạn có chắc chắn muốn xóa toàn bộ dữ liệu trên $DISK?" "no")
    if [[ "$confirm" != "yes" ]]; then
        print_error "Hủy cài đặt."
        exit 1
    fi
    
    echo
}

collect_partition_settings() {
    print_header "CÀI ĐẶT PHÂN VÙNG"
    
    echo "Chọn chế độ phân vùng:"
    echo "  1) Tự động (khuyến nghị)"
    echo "  2) Thủ công"
    echo
    
    local choice
    choice=$(ask_question "Chọn (1-2)" "1")
    [[ "$choice" == "2" ]] && PARTITION_MODE="manual" || PARTITION_MODE="auto"
    
    if [[ "$PARTITION_MODE" == "auto" ]]; then
        collect_auto_partition_settings
    else
        collect_manual_partition_settings
    fi
    
    echo
}

collect_auto_partition_settings() {
    echo
    
    # Detect boot mode
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
        print_info "Phát hiện hệ thống UEFI"
    else
        BOOT_MODE="BIOS"
        print_info "Phát hiện hệ thống BIOS"
    fi
    
    local confirm_boot
    confirm_boot=$(ask_yes_no "Sử dụng chế độ $BOOT_MODE?" "yes")
    if [[ "$confirm_boot" != "yes" ]]; then
        [[ "$BOOT_MODE" == "UEFI" ]] && BOOT_MODE="BIOS" || BOOT_MODE="UEFI"
    fi
    
    # Filesystem
    echo
    print_info "Chọn filesystem cho phân vùng root:"
    echo "  1) ext4 (ổn định, khuyến nghị)"
    echo "  2) btrfs (snapshot, nén)"
    echo "  3) xfs (hiệu năng cao)"
    echo "  4) f2fs (tối ưu cho SSD/eMMC)"
    
    local fs_choice
    fs_choice=$(ask_question "Chọn (1-4)" "1")
    case $fs_choice in
        2) FILESYSTEM="btrfs" ;;
        3) FILESYSTEM="xfs" ;;
        4) FILESYSTEM="f2fs" ;;
        *) FILESYSTEM="ext4" ;;
    esac
    
    # Separate /home
    SEPARATE_HOME=$(ask_yes_no "Tạo phân vùng /home riêng?" "no")
    
    # Swap
    collect_swap_settings
}

collect_swap_settings() {
    echo
    CREATE_SWAP=$(ask_yes_no "Tạo phân vùng swap?" "yes")
    
    if [[ "$CREATE_SWAP" == "yes" ]]; then
        local ram_gb
        ram_gb=$(free -g | awk '/Mem:/ {print $2}')
        local recommend_swap
        
        if [[ $ram_gb -le 2 ]]; then
            recommend_swap=$((ram_gb * 2))
        elif [[ $ram_gb -le 7 ]]; then
            recommend_swap=$ram_gb
        elif [[ $ram_gb -le 15 ]]; then
            recommend_swap=4
        elif [[ $ram_gb -le 31 ]]; then
            recommend_swap=2
        else
            recommend_swap=2
        fi
        
        print_info "RAM hiện tại: ${ram_gb}GB"
        print_info "Gợi ý swap: ${recommend_swap}GB"
        
        # Validate swap size is a positive integer
        while true; do
            SWAP_SIZE=$(ask_question "Nhập kích thước swap (GB)" "$recommend_swap")
            if [[ "$SWAP_SIZE" =~ ^[0-9]+$ && "$SWAP_SIZE" -ge 0 ]]; then
                break
            else
                print_error "Kích thước swap không hợp lệ. Vui lòng nhập số nguyên dương (ví dụ 2)."
            fi
        done
    fi
}

collect_manual_partition_settings() {
    echo
    print_warning "Chế độ phân vùng thủ công"
    print_info "Bạn sẽ được mở shell để phân vùng thủ công"
    print_info "Dùng fdisk, cfdisk, parted hoặc gdisk để tạo phân vùng"
    print_info "Sau khi xong, gõ 'exit' để quay lại script"
    echo
    print_info "Lưu ý:"
    echo "  - UEFI: Cần phân vùng EFI ~512MB (type: EFI System)"
    echo "  - BIOS: Cần khoảng trống 1MB ở đầu đĩa cho GRUB"
    echo "  - Root: Tối thiểu 20GB"
    echo "  - Swap: Tùy chọn"
    echo
    
    read -r -p "Nhấn Enter để mở shell phân vùng..."
    
    # Mở subshell để phân vùng
    bash
    
    # Sau khi thoát shell
    echo
    print_success "Đã hoàn thành phân vùng thủ công"
    
    # Detect boot mode
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    
    # Hỏi phân vùng
    print_info "Danh sách phân vùng:"
    lsblk "$DISK"
    echo
    
    ROOT_PARTITION=$(ask_question "Phân vùng root (vd: sda2, nvme0n1p2)")
    ROOT_PARTITION="/dev/$ROOT_PARTITION"
    
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        EFI_PARTITION=$(ask_question "Phân vùng EFI (vd: sda1, nvme0n1p1)")
        EFI_PARTITION="/dev/$EFI_PARTITION"
    fi
    
    local has_swap
    has_swap=$(ask_yes_no "Có phân vùng swap?" "no")
    if [[ "$has_swap" == "yes" ]]; then
        SWAP_PARTITION=$(ask_question "Phân vùng swap (vd: sda3, nvme0n1p3)")
        SWAP_PARTITION="/dev/$SWAP_PARTITION"
    fi
    
    local has_home
    has_home=$(ask_yes_no "Có phân vùng /home riêng?" "no")
    if [[ "$has_home" == "yes" ]]; then
        HOME_PARTITION=$(ask_question "Phân vùng /home (vd: sda4, nvme0n1p4)")
        HOME_PARTITION="/dev/$HOME_PARTITION"
    fi
}

collect_bootloader_settings() {
    print_header "CÀI ĐẶT BOOTLOADER"
    
    echo "Chọn bootloader:"
    echo "  1) GRUB (khuyến nghị, hỗ trợ cả UEFI và BIOS)"
    echo "  2) systemd-boot (chỉ UEFI, đơn giản)"
    echo "  3) Không cài (tự cài sau)"
    echo
    
    local choice
    choice=$(ask_question "Chọn (1-3)" "1")
    case $choice in
        2) BOOTLOADER="systemd-boot" ;;
        3) BOOTLOADER="none" ;;
        *) BOOTLOADER="grub" ;;
    esac
    
    if [[ "$BOOTLOADER" == "systemd-boot" && "$BOOT_MODE" != "UEFI" ]]; then
        print_warning "systemd-boot chỉ hỗ trợ UEFI. Chuyển sang GRUB."
        BOOTLOADER="grub"
    fi
    
    echo
}

collect_driver_settings() {
    print_header "CÀI ĐẶT DRIVER & FIRMWARE"
    
    echo "Chọn CPU để cài microcode:"
    echo "  1) Intel"
    echo "  2) AMD"
    echo
    
    local cpu_choice
    cpu_choice=$(ask_question "Chọn (1-2)" "1")
    [[ "$cpu_choice" == "2" ]] && CPU_VENDOR="amd" || CPU_VENDOR="intel"
    
    echo
    echo "Chọn GPU driver:"
    echo "  1) Intel (mesa)"
    echo "  2) AMD (mesa)"
    echo "  3) Nvidia (open kernel modules - khuyến nghị)"
    echo "  4) Nvidia (proprietary)"
    echo "  5) Không cài (dùng driver mặc định)"
    echo
    
    local gpu_choice
    gpu_choice=$(ask_question "Chọn (1-5)" "5")
    case $gpu_choice in
        1) GPU_DRIVER="intel" ;;
        2) GPU_DRIVER="amd" ;;
        3) GPU_DRIVER="nvidia-open" ;;
        4) GPU_DRIVER="nvidia" ;;
        *) GPU_DRIVER="none" ;;
    esac
    
    echo
}

collect_user_settings() {
    print_header "CÀI ĐẶT USER & PASSWORD"
    
    while [[ -z "$USERNAME" ]]; do
        USERNAME=$(ask_question "Nhập tên user")
        if [[ -z "$USERNAME" ]]; then
            print_error "Username không được để trống!"
        fi
    done
    
    USER_PASSWORD=$(ask_password "Mật khẩu cho $USERNAME")
    
    ENABLE_SUDO=$(ask_yes_no "Cấp quyền sudo FULL ROOT cho $USERNAME?" "yes")
    
    SET_ROOT_PASSWORD=$(ask_yes_no "Đặt mật khẩu cho root?" "yes")
    if [[ "$SET_ROOT_PASSWORD" == "yes" ]]; then
        ROOT_PASSWORD=$(ask_password "Mật khẩu cho root")
    fi
    
    echo
}

collect_package_settings() {
    print_header "CÀI ĐẶT PACKAGES"
    
    AUTO_MIRROR=$(ask_yes_no "Tự động chọn mirror nhanh nhất?" "yes")
    
    INSTALL_BASE_DEVEL=$(ask_yes_no "Cài base-devel? (cần để build packages)" "yes")
    
    echo
    print_info "Chọn text editor:"
    echo "  1) vim"
    echo "  2) neovim"
    echo "  3) nano"
    echo "  4) Không cài"
    
    local editor_choice
    editor_choice=$(ask_question "Chọn (1-4)" "2")
    case $editor_choice in
        1) INSTALL_EDITOR="vim" ;;
        2) INSTALL_EDITOR="neovim" ;;
        3) INSTALL_EDITOR="nano" ;;
        *) INSTALL_EDITOR="" ;;
    esac
    
    INSTALL_GIT=$(ask_yes_no "Cài git?" "yes")
    INSTALL_WGET=$(ask_yes_no "Cài wget & curl?" "yes")
    INSTALL_BASH_COMPLETION=$(ask_yes_no "Cài bash-completion?" "yes")
    
    echo
    print_info "AUR Helper cho phép cài package từ AUR (Arch User Repository)"
    INSTALL_AUR_HELPER=$(ask_yes_no "Cài AUR helper?" "yes")
    
    if [[ "$INSTALL_AUR_HELPER" == "yes" ]]; then
        echo
        echo "Chọn AUR helper:"
        echo "  1) yay (Go, nhanh, phổ biến nhất)"
        echo "  2) paru (Rust, tính năng nhiều hơn)"
        
        local aur_choice
        aur_choice=$(ask_question "Chọn (1-2)" "1")
        [[ "$aur_choice" == "2" ]] && AUR_HELPER="paru" || AUR_HELPER="yay"
    fi
    
    echo
}

collect_desktop_settings() {
    print_header "CÀI ĐẶT DESKTOP ENVIRONMENT"
    
    INSTALL_DE=$(ask_yes_no "Cài Desktop Environment?" "no")
    
    if [[ "$INSTALL_DE" == "yes" ]]; then
        echo
        echo "Chọn Desktop Environment:"
        echo "  1) GNOME"
        echo "  2) KDE Plasma"
        echo "  3) XFCE"
        echo "  4) LXQt"
        echo "  5) Cinnamon"
        echo "  6) MATE"
        
        local de_choice
        de_choice=$(ask_question "Chọn (1-6)" "1")
        case $de_choice in
            2) DESKTOP_ENV="plasma" ;;
            3) DESKTOP_ENV="xfce" ;;
            4) DESKTOP_ENV="lxqt" ;;
            5) DESKTOP_ENV="cinnamon" ;;
            6) DESKTOP_ENV="mate" ;;
            *) DESKTOP_ENV="gnome" ;;
        esac
        
        echo
        echo "Chọn Display Manager:"
        echo "  1) GDM (cho GNOME)"
        echo "  2) SDDM (cho KDE/LXQt)"
        echo "  3) LightDM (nhẹ, đa năng)"
        echo "  4) Không dùng (startx thủ công)"
        
        local dm_choice
        dm_choice=$(ask_question "Chọn (1-4)" "1")
        case $dm_choice in
            2) DISPLAY_MANAGER="sddm" ;;
            3) DISPLAY_MANAGER="lightdm" ;;
            4) DISPLAY_MANAGER="none" ;;
            *) DISPLAY_MANAGER="gdm" ;;
        esac
    fi
    
    echo
}

collect_advanced_settings() {
    print_header "CÀI ĐẶT NÂNG CAO"
    
    ENABLE_LVM=$(ask_yes_no "Bật LVM?" "no")
    ENABLE_LUKS=$(ask_yes_no "Bật mã hóa LUKS?" "no")
    ENABLE_FIREWALL=$(ask_yes_no "Bật firewall (ufw)?" "yes")
    ENABLE_SSH=$(ask_yes_no "Cài SSH server (openssh)?" "no")
    OPTIMIZE_SSD=$(ask_yes_no "Tối ưu mount options cho SSD?" "yes")
    
    echo
}

# ═══════════════════════════════════════════════════════════
#  XÁC NHẬN CẤU HÌNH
# ═══════════════════════════════════════════════════════════

confirm_settings() {
    print_header "XÁC NHẬN CẤU HÌNH"
    
    echo -e "${BOLD}Ngôn ngữ & Bàn phím:${NC}"
    echo "  Locale: $LOCALE"
    echo "  Keymap: $KEYMAP"
    echo
    
    echo -e "${BOLD}Thời gian:${NC}"
    echo "  Múi giờ: $TIMEZONE"
    echo "  NTP: $ENABLE_NTP"
    echo
    
    echo -e "${BOLD}Mạng:${NC}"
    echo "  Hostname: $HOSTNAME"
    echo "  Network Manager: $NETWORK_MANAGER"
    echo
    
    echo -e "${BOLD}Ổ đĩa:${NC}"
    echo "  Ổ cài đặt: $DISK"
    echo "  Chế độ phân vùng: $PARTITION_MODE"
    
    if [[ "$PARTITION_MODE" == "auto" ]]; then
        echo "  Boot mode: $BOOT_MODE"
        echo "  Filesystem: $FILESYSTEM"
        echo "  Phân vùng /home riêng: $SEPARATE_HOME"
        echo "  Swap: $CREATE_SWAP"
        [[ "$CREATE_SWAP" == "yes" ]] && echo "  Swap size: ${SWAP_SIZE}GB"
    else
        echo "  Root: $ROOT_PARTITION"
        [[ -n "$EFI_PARTITION" ]] && echo "  EFI: $EFI_PARTITION"
        [[ -n "$SWAP_PARTITION" ]] && echo "  Swap: $SWAP_PARTITION"
        [[ -n "$HOME_PARTITION" ]] && echo "  Home: $HOME_PARTITION"
    fi
    echo
    
    echo -e "${BOLD}Bootloader:${NC}"
    echo "  $BOOTLOADER"
    echo
    
    echo -e "${BOLD}Driver:${NC}"
    echo "  CPU: $CPU_VENDOR"
    echo "  GPU: $GPU_DRIVER"
    echo
    
    echo -e "${BOLD}User:${NC}"
    echo "  Username: $USERNAME"
    echo "  Sudo: $ENABLE_SUDO"
    echo "  Root password: $SET_ROOT_PASSWORD"
    echo
    
    echo -e "${BOLD}Desktop:${NC}"
    if [[ "$INSTALL_DE" == "yes" ]]; then
        echo "  DE: $DESKTOP_ENV"
        echo "  DM: $DISPLAY_MANAGER"
    else
        echo "  Không cài DE"
    fi
    echo
    
    if [[ "$INSTALL_AUR_HELPER" == "yes" ]]; then
        echo -e "${BOLD}AUR Helper:${NC}"
        echo "  $AUR_HELPER"
        echo
    fi
    
    echo -e "${BOLD}Nâng cao:${NC}"
    echo "  LVM: $ENABLE_LVM"
    echo "  LUKS: $ENABLE_LUKS"
    echo "  Firewall: $ENABLE_FIREWALL"
    echo "  SSH: $ENABLE_SSH"
    echo "  Tối ưu SSD: $OPTIMIZE_SSD"
    echo
    
    local confirm
    confirm=$(ask_yes_no "Xác nhận bắt đầu cài đặt?" "yes")
    if [[ "$confirm" != "yes" ]]; then
        print_error "Hủy cài đặt."
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════
#  PHÂN VÙNG TỰ ĐỘNG
# ═══════════════════════════════════════════════════════════

auto_partition() {
    print_header "PHÂN VÙNG TỰ ĐỘNG"
    
    # Yêu cầu xác nhận trước khi thực hiện mọi thao tác phá hủy
    local confirm_disk
    echo
    print_warning "LƯU Ý: auto_partition sẽ xóa toàn bộ dữ liệu trên $DISK"
    read -r -p "Gõ chính xác đường dẫn ổ đĩa để xác nhận (ví dụ /dev/sda): " confirm_disk
    if [[ "$confirm_disk" != "$DISK" ]]; then
        print_error "Xác nhận không đúng. Hủy phân vùng tự động."
        exit 1
    fi

    print_info "Xóa toàn bộ dữ liệu trên $DISK..."
    wipefs -af "$DISK"
    sgdisk --zap-all "$DISK"
    
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        print_info "Tạo bảng phân vùng GPT..."
        parted -s "$DISK" mklabel gpt
        
        print_info "Tạo phân vùng EFI (512MB)..."
        parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
        parted -s "$DISK" set 1 esp on
        
        # partition numbering handled via device node checks later

        # Compute positions in MiB (EFI ends at 513MiB)
        local root_start=513
        if [[ "$CREATE_SWAP" == "yes" ]]; then
            local swap_end=$((513 + SWAP_SIZE * 1024))
            print_info "Tạo phân vùng swap (${SWAP_SIZE}GB)..."
            parted -s "$DISK" mkpart primary linux-swap 513MiB ${swap_end}MiB
            :
            root_start=$swap_end
        fi

        if [[ "$SEPARATE_HOME" == "yes" ]]; then
            print_info "Tạo phân vùng root (50GB)..."
            local root_end=$((root_start + 50 * 1024))
            parted -s "$DISK" mkpart primary "$FILESYSTEM" ${root_start}MiB ${root_end}MiB

            print_info "Tạo phân vùng /home (phần còn lại)..."
            parted -s "$DISK" mkpart primary "$FILESYSTEM" ${root_end}MiB 100%
        else
            print_info "Tạo phân vùng root (phần còn lại)..."
            parted -s "$DISK" mkpart primary "$FILESYSTEM" ${root_start}MiB 100%
        fi
        
    else
        print_info "Tạo bảng phân vùng MBR..."
        parted -s "$DISK" mklabel msdos
        
        local start_pos=1
        if [[ "$CREATE_SWAP" == "yes" ]]; then
            local swap_end=$((1 + SWAP_SIZE * 1024))
            print_info "Tạo phân vùng swap (${SWAP_SIZE}GB)..."
            parted -s "$DISK" mkpart primary linux-swap 1MiB ${swap_end}MiB
            start_pos=$swap_end
        fi

        if [[ "$SEPARATE_HOME" == "yes" ]]; then
            print_info "Tạo phân vùng root (50GB)..."
            local root_end=$((start_pos + 50 * 1024))
            parted -s "$DISK" mkpart primary "$FILESYSTEM" ${start_pos}MiB ${root_end}MiB

            print_info "Tạo phân vùng /home (phần còn lại)..."
            parted -s "$DISK" mkpart primary "$FILESYSTEM" ${root_end}MiB 100%
        else
            print_info "Tạo phân vùng root (phần còn lại)..."
            parted -s "$DISK" mkpart primary "$FILESYSTEM" ${start_pos}MiB 100%
        fi
        
        parted -s "$DISK" set 1 boot on
    fi
    
    print_success

}
