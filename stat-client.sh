#!/bin/sh

WORKSPACE=/opt/stat_client

# 默认参数值
a_value=""
g_value=""
p_value=""
w_value=""
alias_value=""
n_flag=0
location_value=""

# 清空工作目录
clear_workspace() {
    echo "Clearing workspace: ${WORKSPACE}"
    if [ -d "$WORKSPACE" ]; then
        rm -rf "${WORKSPACE:?}/*"
    fi
    mkdir -p "$WORKSPACE"
    cd "$WORKSPACE" || exit
}

# 打印帮助信息
usage() {
    echo "Usage: $0 -a <url> -g <group> -p <password> --alias <alias> [--location <location>] [-w <w_value>] [-n]"
    exit 1
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# 检查是否是 systemd 系统
check_systemd() {
    if pidof systemd > /dev/null; then
        return 0  # 是 systemd 系统
    else
        return 1  # 不是 systemd 系统
    fi
}

# 检查并安装指定的软件包
check_and_install_package() {
    package=$1
    if ! command -v "$package" > /dev/null; then
        echo "$package is not installed. Installing $package..."
        
        # 使用不同的包管理器安装
        if command -v apt-get > /dev/null; then
            apt-get update && apt-get install -y "$package"  # Debian/Ubuntu 系列
        elif command -v yum > /dev/null; then
            yum install -y "$package"  # CentOS/RHEL 系列
        elif command -v dnf > /dev/null; then
            dnf install -y "$package"  # Fedora 系列
        elif command -v pacman > /dev/null; then
            pacman -Sy --noconfirm "$package"  # Arch 系列
        elif command -v zypper > /dev/null; then
            zypper install -y "$package"  # openSUSE 系列
        elif command -v apk > /dev/null; then
            apk add --no-cache "$package"  # Alpine 系列
        elif command -v emerge > /dev/null; then
            emerge "$package"  # Gentoo 系列
        else
            echo "Unsupported package manager. Please install $package manually."
            exit 1
        fi
    else
        echo "$package is already installed."
    fi
}

# 检查并安装 wget 和 unzip
check_wget_unzip() {
    check_and_install_package wget
    check_and_install_package unzip
}

# 检查并安装 vnstat
check_and_install_vnstat() {
    check_and_install_package vnstat

    # 启动 vnstatd 服务并设置开机自启
    if ! systemctl is-active --quiet vnstat; then
        echo "Starting vnstat service..."
        systemctl start vnstat  # 启动 vnstat 服务
    fi
    
    # 确保 vnstatd 在系统启动时启动
    systemctl enable vnstat  # 设置 vnstatd 开机自启
}

# 解析命令行参数的函数
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -a)
            a_value="$2"
            shift 2
            ;;
        -g)
            g_value="$2"
            shift 2
            ;;
        -p)
            p_value="$2"
            shift 2
            ;;
        -w)
            w_value="$2"
            shift 2
            ;;
        --alias)
            alias_value="$2"
            shift 2
            ;;
        --location)
            location_value="$2"
            shift 2
            ;;
        -n)
            n_flag=1
            shift 1
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
        esac
    done

    # 检查必需的参数是否已指定
    if [ -z "$a_value" ]; then
        echo "Error: -a <url> is required."
        usage
    fi

    if [ -z "$g_value" ]; then
        echo "Error: -g <group> is required."
        usage
    fi

    if [ -z "$p_value" ]; then
        echo "Error: -p <password> is required."
        usage
    fi

    if [ -z "$alias_value" ]; then
        echo "Error: --alias <alias> is required."
        usage
    fi
}

# 生成命令的函数
build_cmd() {
    cmd="$WORKSPACE/stat_client -a \"$a_value\" -g \"$g_value\" -p \"$p_value\" --alias \"$alias_value\""

    if [ -n "$w_value" ]; then
        cmd="$cmd -w $w_value"
    fi

    if [ "$n_flag" -eq 1 ]; then
        cmd="$cmd -n"
    fi

    if [ -n "$location_value" ]; then
        cmd="$cmd --location \"$location_value\""
    fi

    echo "$cmd"
}

# 下载并安装客户端的函数
install_client() {
    OS_ARCH="x86_64"
    latest_version=$(curl -m 10 -sL "https://api.github.com/repos/zdz/ServerStatus-Rust/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')

    if [ -z "$latest_version" ]; then
        echo "Error: Unable to fetch the latest version."
        exit 1
    fi

    wget --no-check-certificate -qO "client-${OS_ARCH}-unknown-linux-musl.zip" "https://github.com/zdz/ServerStatus-Rust/releases/download/${latest_version}/client-${OS_ARCH}-unknown-linux-musl.zip"
    unzip -o "client-${OS_ARCH}-unknown-linux-musl.zip"
    rm *.zip
}

# 配置 systemd 服务的函数
configure_systemd_service() {
    cmd=$(build_cmd)
    echo "cmd:$cmd"
    rm -r stat_client.service
    cat << EOF > /etc/systemd/system/stat_client.service
[Unit]
Description=Stat Client
After=network.target

[Service]
User=root
Group=root
Environment="RUST_BACKTRACE=1"
WorkingDirectory=$WORKSPACE
ExecStart=$cmd
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable stat_client
    systemctl restart stat_client
    systemctl status stat_client
}

# 配置 OpenRC 服务的函数
configure_openrc_service() {
    cmd=$(build_cmd)
    echo "cmd:$cmd"
    
    # 在 Alpine 上创建 OpenRC 服务脚本
    rm -r /etc/init.d/stat_client
    cat << EOF > /etc/init.d/stat_client
#!/sbin/openrc-run

name="stat_client"
command="$cmd"
command_background="yes"
pidfile="/var/run/stat_client.pid"
depend() {
    need net
    use logger
}
EOF
    chmod +x /etc/init.d/stat_client

    # 将服务添加到默认运行级别并启动
    rc-update add stat_client default
    service stat_client start
}

# 主函数
main() {
    # 检查是否为root用户
    check_root
    clear_workspace

    # 检查并安装 wget 和 unzip
    check_wget_unzip

    # 解析参数
    parse_args "$@"

    # 如果指定了-n参数，检查并安装 vnstat
    if [ "$n_flag" -eq 1 ]; then
        check_and_install_vnstat
    fi

    # 安装客户端
    install_client

    # 检查是否是 systemd 系统
    if check_systemd; then
        # 配置 systemd 服务
        configure_systemd_service
    else
        # 如果不是 systemd 系统，配置 OpenRC 服务
        configure_openrc_service
    fi
}

# 调用主函数
main "$@"
