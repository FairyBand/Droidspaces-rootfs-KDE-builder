ARG TARGETPLATFORM
FROM ubuntu:26.04 AS customizer

#######################################################
ARG BUILD_KDE
ARG BUILD_KDE_plus
ARG PulseAudio
ARG ENABLE_zh_tz_ARG
ARG ENABLE_binfmt_ARG
ARG ENABLE_yj_ARG
ARG ENABLE_mesa_ARG
ARG ENABLE_kfgj_ARG
ARG ENABLE_zip_ARG
ARG ENABLE_docker_ARG
ARG ENABLE_srf_ARG
ARG ENABLE_tmoe_ARG
ARG USERNAME
ARG ANLAND_REPO=https://github.com/superturtlee/anland.git
ARG ANLAND_COMMIT=aa1d34727695ee8a75a9b6fb0722753854b80449
######################################################

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's/Components: main/Components: main restricted universe multiverse/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || \
    sed -i 's/main/main restricted universe multiverse/g' /etc/apt/sources.list 2>/dev/null && \
    apt-get update && \
    apt-get upgrade -y

# 优先复制自定义脚本
COPY scripts/download-firmware /usr/local/bin/

# 将自定义的 bashrc 脚本复制到根文件系统的 profile 目录
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# 赋予相关脚本可执行权限
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # 核心工具组件
    bash jq dialog coreutils file findutils grep sed gawk curl wget ca-certificates locales bash-completion udev dbus systemd-sysv systemd-resolved fastfetch \
    # 用户请求的基础开发/编辑工具
    git nano sudo \
    # 网络与 SSH 工具
    openssh-server net-tools iptables iputils-ping iproute2 dnsutils \
    # 用于系统监控的 procps 进程工具
    procps \
    # 核心内核模块支持
    kmod tzdata && \
    ############################################## GNOME Wayland支持 ################################################
    # 解除底层系统对中文等翻译文件(.mo)的剔除规则，防止安装桌面时丢包
    sed -i 's|^path-exclude=/usr/share/locale/\*/LC_MESSAGES/\*.mo|#&|' /etc/dpkg/dpkg.cfg.d/excludes || true && \
    apt-get install -y --no-install-recommends \
        dbus-x11 fonts-noto-cjk fonts-noto-color-emoji \
        gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-terminal nautilus mutter xwayland \
        pipewire pipewire-pulse wireplumber mesa-utils pulseaudio-utils vulkan-tools wayland-utils dbus-user-session \
        dconf-cli gsettings-desktop-schemas adwaita-icon-theme gnome-themes-extra gnome-keyring \
        xdg-user-dirs libcanberra-pulse gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop \
        libpam-systemd libpam-modules aha clinfo dmidecode libdisplay-info-bin pciutils; \
    ######################################################################################################
    #输入法 fcitx5 (可选)
    if [ "$ENABLE_srf_ARG" = "true" ]; then \
        apt-get install -y fcitx5; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ] && [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        apt-get install -y fcitx5-chinese-addons; \
    fi && \
    ## 开发工具集成 (可选)
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        build-essential gcc g++ make cmake autoconf automake libtool pkg-config clang llvm python3 python3-pip python3-dev python3-venv python-is-python3; \
    fi && \
    ## 压缩工具扩展 (可选)
    if [ "$ENABLE_zip_ARG" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        zip unzip p7zip-full bzip2 xz-utils tar gzip; \
    fi && \
    ## docker (可选)
    if [ "$ENABLE_docker_ARG" = "true" ]; then \
        apt-get install -y --no-install-recommends \
        docker.io docker-compose-v2; \
    fi && \
    ## 集成tmoe (可选)
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then \
        git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && \
        ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe && \
        chmod -R 755 /usr/local/etc/tmoe-linux; \
    fi && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 强制配置使用 iptables-legacy
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        export DEBIAN_FRONTEND=noninteractive && \
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo "Asia/Shanghai" > /etc/timezone && \
        dpkg-reconfigure -f noninteractive tzdata && \
        sed -i '/zh_CN.UTF-8/s/^# //' /etc/locale.gen && \
        locale-gen && \
        update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8; \
    else \
        locale-gen && \
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    fi && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Ubuntu 默认用户是 ubuntu，删除它避免冲突
    deluser --remove-home ubuntu || true && \
    # 创建自定义用户并直接加入 shadow 组，确保锁屏验证权限
    useradd -m -s /bin/bash -G shadow ${USERNAME} && echo "${USERNAME}:1234" | chpasswd && \
    systemctl enable ssh


# 添加环境变量
RUN cat <<'EOF' > /etc/environment
XCURSOR_SIZE=48
XDG_SESSION_TYPE=wayland
GDK_BACKEND=wayland,x11
QT_QPA_PLATFORM=wayland
MOZ_ENABLE_WAYLAND=1
ANLAND_SOCKET=/run/display.sock
EOF
# 音频选择
RUN if [ "$PulseAudio" = "socket" ]; then \
        echo "PULSE_SERVER=unix:/tmp/.pulse-socket" >> /etc/environment; \
    elif [ "$PulseAudio" = "tcp" ]; then \
        echo "PULSE_SERVER=tcp:127.0.0.1:4713" >> /etc/environment; \
    fi

# 输入法开机自启动及 GNOME Wayland 配置
RUN <<'EOF_RUN'
    if [ "$ENABLE_srf_ARG" = "true" ]; then
    mkdir -p /home/${USERNAME}/.config/autostart
    cat <<'EOF' > /home/${USERNAME}/.config/autostart/fcitx5.desktop
[Desktop Entry]
Name=Fcitx5
GenericName=Input Method
Comment=Start Input Method
Exec=fcitx5 -d
Icon=fcitx
Terminal=false
Type=Application
Categories=System;Utility;
StartupNotify=false
NoDisplay=true
EOF
    cat <<'EOF' >> /etc/environment
XMODIFIERS=@im=fcitx5
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
SDL_IM_MODULE=fcitx5
GLFW_IM_MODULE=fcitx
EOF
fi
    if [ "$ENABLE_mesa_ARG" = "true" ] ; then
        cat <<'EOF' >> /etc/environment
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1
MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE_DRI3=1
TU_DEBUG=noconform
EOF
    fi

    echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' >> /home/${USERNAME}/.bashrc
    echo 'export ANLAND_SOCKET=${ANLAND_SOCKET:-/run/display.sock}' >> /home/${USERNAME}/.bashrc
    mkdir -p /home/${USERNAME}/.config
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
    if [ "$BUILD_KDE_plus" = "true" ] ; then
    cat <<EOF > /etc/systemd/system/gnome-anland.service
[Unit]
Description=Start GNOME Wayland through anland
After=network.target display-manager.service

[Service]
Type=simple
User=${USERNAME}
EnvironmentFile=-/etc/environment
ExecStart=/usr/local/bin/start-gnome-anland
Restart=no

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/gnome-anland.service /etc/systemd/system/multi-user.target.wants/gnome-anland.service
    fi
EOF_RUN

# Mesa 驱动适配
RUN if [ "$ENABLE_mesa_ARG" = "true" ]; then \
        echo "--> [开启] 正在下载并安装最新版 Mesa 驱动..." && \
        URL=$(curl -s https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest | \
        jq -r '.assets[] | select(.name | test("mesa-for-android-container_.*_ubuntu_resolute_arm64\\.tar\\.gz")) | .browser_download_url' | head -1) && \
        if [ -z "$URL" ] || [ "$URL" = "null" ]; then echo "获取下载链接失败，可能是源仓库还没有提供 Ubuntu 版本的 Mesa 驱动或触发了限制"; exit 1; fi && \
        wget -q --tries=5 --waitretry=3 -O /tmp/mesa.tar.gz "$URL" && \
        tar -zxf /tmp/mesa.tar.gz -C / && \
        rm /tmp/mesa.tar.gz && \
        ldconfig; \
    else \
        echo "--> [跳过] 未开启 Mesa 驱动安装"; \
    fi

# anland Weston 后端与 GNOME Wayland 启动脚本
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential meson ninja-build pkg-config cmake \
        libwayland-dev libpixman-1-dev libxkbcommon-dev \
        libinput-dev libevdev-dev libdrm-dev libgbm-dev \
        libudev-dev libseat-dev libcairo2-dev \
        libjpeg-dev libwebp-dev libpam0g-dev \
        libgles-dev libegl-dev libvulkan-dev glslang-tools \
        libxcb-composite0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
        libxcursor-dev libxcb1-dev \
        libpango1.0-dev libglib2.0-dev \
        libwayland-cursor0 wayland-protocols libwayland-bin \
        libpng-dev libfontconfig-dev libfreetype-dev \
        hwdata && \
    git clone "$ANLAND_REPO" /tmp/anland && \
    cd /tmp/anland && \
    git checkout "$ANLAND_COMMIT" && \
    ./build_and_install.sh && \
    printf '%s\n' "$ANLAND_COMMIT" > /opt/weston-anland/ANLAND_COMMIT && \
    rm -rf /tmp/anland /opt/weston-anland/share/doc /opt/weston-anland/share/man && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN cat <<'EOF' > /usr/local/bin/start-gnome-anland
#!/bin/bash
set -euo pipefail

SOCK="${1:-${ANLAND_SOCKET:-/run/display.sock}}"
if [ ! -S "$SOCK" ] && [ -S /data/local/tmp/display_daemon.sock ]; then
    SOCK=/data/local/tmp/display_daemon.sock
fi

PREFIX=/opt/weston-anland
LIBDIR="$PREFIX/lib/aarch64-linux-gnu"

export LD_LIBRARY_PATH="$LIBDIR:$LIBDIR/libweston-16:$LIBDIR/weston:${LD_LIBRARY_PATH:-}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
export WESTON_MODULE_MAP="anland-backend.so=$LIBDIR/libweston-16/anland-backend.so;gl-renderer.so=$LIBDIR/libweston-16/gl-renderer.so;vulkan-renderer.so=$LIBDIR/libweston-16/vulkan-renderer.so;xwayland.so=$LIBDIR/libweston-16/xwayland.so;kiosk-shell.so=$LIBDIR/weston/kiosk-shell.so"

unset DISPLAY
export XDG_SESSION_TYPE=wayland
export GDK_BACKEND=wayland,x11
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-kgsl}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-kgsl}"
export FD_FORCE_KGSL="${FD_FORCE_KGSL:-1}"
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE="${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE:-1}"
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE_DRI3="${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE_DRI3:-1}"

WESTON_PID=
GNOME_PID=

cleanup() {
    [ -n "${GNOME_PID:-}" ] && kill "$GNOME_PID" 2>/dev/null || true
    [ -n "${WESTON_PID:-}" ] && kill "$WESTON_PID" 2>/dev/null || true
    sleep 0.3
    [ -n "${GNOME_PID:-}" ] && kill -9 "$GNOME_PID" 2>/dev/null || true
    [ -n "${WESTON_PID:-}" ] && kill -9 "$WESTON_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

rm -f "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null || true
"$PREFIX/bin/weston" -Banland-backend.so --disp-sock="$SOCK" --shell=kiosk-shell.so --no-config &
WESTON_PID=$!

WAYLAND_SOCKET=""
for _ in $(seq 1 300); do
    sleep 1
    for wl in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$wl" ] || continue
        WAYLAND_SOCKET="$(basename "$wl")"
        break 2
    done
done

if [ -z "$WAYLAND_SOCKET" ]; then
    echo "ERROR: weston wayland socket not found"
    wait "$WESTON_PID"
    exit 1
fi

export WAYLAND_DISPLAY="$WAYLAND_SOCKET"
echo "anland socket: $SOCK"
echo "wayland socket: $WAYLAND_DISPLAY"

if command -v gnome-shell >/dev/null 2>&1; then
    dbus-run-session -- gnome-shell --nested --wayland &
elif command -v gnome-session >/dev/null 2>&1; then
    dbus-run-session -- gnome-session --session=gnome &
else
    echo "ERROR: neither gnome-shell nor gnome-session was found"
    exit 1
fi
GNOME_PID=$!

wait "$WESTON_PID"
EOF
RUN chmod +x /usr/local/bin/start-gnome-anland

# 修复容器内的 DHCP 网络服务配置
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# 应用 Android 运行环境兼容性修复（重点针对 Systemd 和 Udev）
RUN <<'EOF_RUN'
# --- 1. 常规兼容性修复 ---
grep -q '^aid_inet:' /etc/group     || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

getent group droidspaces-gpu >/dev/null || groupadd -g 786 -r droidspaces-gpu
usermod -a -G aid_inet,aid_net_raw,input,video,tty,droidspaces-gpu root || true
usermod -a -G aid_inet,aid_net_raw,input,video,tty,sudo,droidspaces-gpu ${USERNAME} || true

grep -q '^_apt:' /etc/passwd && usermod -g aid_inet _apt || true

if [ -f /etc/adduser.conf ]; then
    sed -i '/^EXTRA_GROUPS=/d; /^ADD_EXTRA_GROUPS=/d' /etc/adduser.conf
    echo 'ADD_EXTRA_GROUPS=1' >> /etc/adduser.conf
    echo 'EXTRA_GROUPS="aid_inet aid_net_raw input video tty"' >> /etc/adduser.conf
fi

# --- 2. 针对 Systemd 的特定修复 ---
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

cat >> /etc/systemd/journald.conf << 'EOT'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ds-logging.conf << 'EOT'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

mkdir -p /etc/systemd/system/multi-user.target.wants
GUEST_SYSTEMD_PATH="/lib/systemd/system"

if [ -f "$GUEST_SYSTEMD_PATH/dbus.service" ]; then
    ln -sf "$GUEST_SYSTEMD_PATH/dbus.service" "/etc/systemd/system/multi-user.target.wants/dbus.service"
fi

if [ "$ENABLE_yj_ARG" = "true" ]; then
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
            ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
        fi
    done
else
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        ln -sf /dev/null "/etc/systemd/system/$service"
    done
fi

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
EOF
    fi
done

for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-hwaccess-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -q 'enable_hw_access=1' /run/droidspaces/container.config"
EOF
    fi
done

if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi

echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

COPY scripts/binfmt/qemu-binfmt-register.sh /usr/local/bin/
COPY scripts/binfmt/qemu-binfmt-register.service /etc/systemd/system/
RUN if [ "$ENABLE_binfmt_ARG" = "false" ]; then \
        rm -rf /usr/local/bin/qemu-binfmt-register.sh && \
        rm -rf /etc/systemd/system/qemu-binfmt-register.service ; \
    fi

RUN if [ "$ENABLE_binfmt_ARG" = "true" ]; then \
        chmod +x /usr/local/bin/qemu-binfmt-register.sh && \
        chmod 644 /etc/systemd/system/qemu-binfmt-register.service && \
        mkdir -p /etc/systemd/system/multi-user.target.wants && \
        ln -sf /etc/systemd/system/qemu-binfmt-register.service /etc/systemd/system/multi-user.target.wants/qemu-binfmt-register.service && \
        (apt-get purge -y qemu-* binfmt-support || true) && \
        apt-get autoremove -y && \
        apt-get autoclean && \
        rm -rf /var/lib/binfmts/* /etc/binfmt.d/* /usr/lib/binfmt.d/qemu-* && \
        dpkg --add-architecture amd64 && \
        sed -i '/^Types: deb$/a Architectures: arm64' /etc/apt/sources.list.d/ubuntu.sources && \
        printf "Types: deb\nURIs: http://archive.ubuntu.com/ubuntu/\nSuites: resolute resolute-updates resolute-security\nComponents: main universe restricted multiverse\nArchitectures: amd64\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n" > /etc/apt/sources.list.d/ubuntu-amd64.sources && \
        apt-get update && \
        (apt-get install -y --no-install-recommends qemu-user-binfmt libc6:amd64 libc6:arm64 libc-bin || \
         apt-get install -y --no-install-recommends qemu-user-binfmt) && \
        apt-get clean; \
    else \
        rm -f /usr/local/bin/qemu-binfmt-register.sh /etc/systemd/system/qemu-binfmt-register.service; \
    fi

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

FROM scratch AS export
COPY --from=customizer / /
