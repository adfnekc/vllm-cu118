# Docker二进制安装和镜像构建脚本
# 描述：通过二进制包安装Docker 18.09.9，后台启动dockerd，非root用户可用

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置参数
DOCKER_VERSION="18.09.9"
DOCKER_DOWNLOAD_URL="https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"
INSTALL_DIR="/usr/bin"
DOCKER_DATA_ROOT="/var/lib/docker"  # Docker数据目录
DOCKER_PID_FILE="/var/run/docker.pid"  # Docker进程PID文件
DOCKER_LOG_FILE="/var/log/docker.log"  # Docker日志文件

# 打印信息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令执行状态
check_status() {
    if [ $? -eq 0 ]; then
        print_info "$1 成功"
    else
        print_error "$1 失败"
        exit 1
    fi
}

# 检查是否有sudo权限
check_sudo() {
    if ! sudo -v &>/dev/null; then
        print_error "当前用户没有sudo权限，请确保用户有sudo权限后再运行"
        exit 1
    fi
    print_info "sudo权限检查通过"
}

# 创建docker组并将当前用户加入
setup_docker_group() {
    print_info "配置docker用户组..."
    
    # 检查docker组是否存在
    if getent group docker > /dev/null 2>&1; then
        print_info "docker组已存在"
    else
        sudo groupadd docker
        check_status "创建docker组"
    fi
    
    # 将当前用户加入docker组
    CURRENT_USER=$(whoami)
    if groups $CURRENT_USER | grep &>/dev/null '\bdocker\b'; then
        print_info "用户 $CURRENT_USER 已在docker组中"
    else
        sudo usermod -aG docker $CURRENT_USER
        check_status "将用户 $CURRENT_USER 添加到docker组"
        print_warn "用户已添加到docker组，需要重新登录才能生效"
        print_warn "脚本将继续执行，但当前会话可能仍需使用sudo"
        NEED_RELOGIN=true
    fi
}

# 下载Docker二进制包
download_docker() {
    print_info "下载Docker ${DOCKER_VERSION} 二进制包..."
    
    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    cd $TMP_DIR
    
    # 下载
    print_info "从 $DOCKER_DOWNLOAD_URL 下载..."
    if command -v curl &>/dev/null; then
        curl -L -o docker.tgz $DOCKER_DOWNLOAD_URL
    elif command -v wget &>/dev/null; then
        wget -O docker.tgz $DOCKER_DOWNLOAD_URL
    else
        print_error "未找到curl或wget，请先安装"
        exit 1
    fi
    check_status "Docker下载"
    
    # 解压
    print_info "解压二进制包..."
    tar xzf docker.tgz
    check_status "解压"
}

# 安装Docker二进制文件
install_docker_binaries() {
    print_info "安装Docker二进制文件到 $INSTALL_DIR..."
    
    # 停止现有Docker进程（如果运行中）
    stop_docker
    
    # 复制二进制文件
    sudo cp docker/* $INSTALL_DIR/
    check_status "复制二进制文件"
    
    # 设置所有权和权限
    print_info "设置二进制文件权限..."
    sudo chown root:docker $INSTALL_DIR/docker* 2>/dev/null || true
    sudo chown root:docker $INSTALL_DIR/containerd* 2>/dev/null || true
    sudo chown root:docker $INSTALL_DIR/ctr 2>/dev/null || true
    sudo chown root:docker $INSTALL_DIR/runc 2>/dev/null || true
    sudo chmod 755 $INSTALL_DIR/docker* $INSTALL_DIR/containerd* $INSTALL_DIR/ctr $INSTALL_DIR/runc 2>/dev/null || true
    
    print_info "二进制文件安装完成"
}

# 创建Docker配置文件
create_docker_config() {
    print_info "创建Docker配置文件..."
    
    # 创建配置目录
    sudo mkdir -p /etc/docker
    
    # 写入daemon.json配置
    cat << EOF | sudo tee /etc/docker/daemon.json
{
  "data-root": "$DOCKER_DATA_ROOT",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "https://hub-mirror.c.163.com"],
  "group": "docker",
  "pidfile": "$DOCKER_PID_FILE"
}
EOF
    check_status "创建Docker配置"
}

# 停止Docker进程
stop_docker() {
    if [ -f "$DOCKER_PID_FILE" ]; then
        OLD_PID=$(sudo cat $DOCKER_PID_FILE 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
            print_info "停止现有Docker进程 (PID: $OLD_PID)..."
            sudo kill $OLD_PID
            sleep 2
            # 如果进程还在，强制结束
            if kill -0 $OLD_PID 2>/dev/null; then
                sudo kill -9 $OLD_PID
            fi
        fi
        sudo rm -f $DOCKER_PID_FILE
    fi
    
    # 同时停止可能运行的containerd
    if pgrep containerd > /dev/null; then
        sudo pkill containerd || true
    fi
}

# 后台启动Docker
start_docker_background() {
    print_info "后台启动dockerd..."
    
    # 创建必要目录
    sudo mkdir -p $DOCKER_DATA_ROOT
    sudo mkdir -p $(dirname $DOCKER_LOG_FILE)
    
    # 确保socket目录存在且有正确权限
    sudo mkdir -p /var/run
    sudo chmod 755 /var/run
    
    # 清理可能存在的旧socket文件
    sudo rm -f /var/run/docker.sock
    
    # 后台启动dockerd
    print_info "启动dockerd进程，日志将写入 $DOCKER_LOG_FILE"
    sudo nohup dockerd > $DOCKER_LOG_FILE 2>&1 &
    
    # 获取新启动的PID
    DOCKER_PID=$!
    echo $DOCKER_PID | sudo tee $DOCKER_PID_FILE > /dev/null
    print_info "dockerd 已启动，PID: $DOCKER_PID"
    
    # 等待dockerd启动完成
    print_info "等待dockerd启动..."
    sleep 5
    
    # 检查dockerd是否运行
    if kill -0 $DOCKER_PID 2>/dev/null; then
        print_info "dockerd 正在运行"
    else
        print_error "dockerd 启动失败，请检查日志: $DOCKER_LOG_FILE"
        sudo tail -20 $DOCKER_LOG_FILE
        exit 1
    fi
    
    # 检查socket权限
    if [ -S "/var/run/docker.sock" ]; then
        print_info "Docker socket 已创建"
        sudo ls -la /var/run/docker.sock
        # 设置socket权限，使docker组成员可以访问
        sudo chown root:docker /var/run/docker.sock
        sudo chmod 666 /var/run/docker.sock
        print_info "已设置socket权限为 docker组可访问"
    else
        print_warn "Docker socket 文件未找到，等待3秒..."
        sleep 3
        if [ -S "/var/run/docker.sock" ]; then
            sudo chown root:docker /var/run/docker.sock
            sudo chmod 666 /var/run/docker.sock
        fi
    fi
}

# 验证Docker安装
verify_docker() {
    print_info "验证Docker安装..."
    
    # 尝试使用docker命令
    if docker version > /dev/null 2>&1; then
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || docker version | grep -i version | head -1)
    else
        print_warn "当前用户无法直接运行docker，尝试使用sudo..."
        docker_version=$(sudo docker version --format '{{.Server.Version}}' 2>/dev/null || sudo docker version | grep -i version | head -1)
    fi
    
    print_info "Docker版本: $docker_version"
    
    if [[ $docker_version == *"$DOCKER_VERSION"* ]]; then
        print_info "Docker版本验证通过"
    else
        print_error "Docker版本不正确，期望 $DOCKER_VERSION"
        exit 1
    fi
    
    # 测试docker命令
    print_info "测试docker命令..."
    if docker ps > /dev/null 2>&1; then
        docker ps
        print_info "docker命令测试成功 (用户模式)"
    else
        sudo docker ps
        print_info "docker命令测试成功 (sudo模式)"
    fi
}

# 清理临时文件
cleanup() {
    print_info "清理临时文件..."
    cd /
    rm -rf $TMP_DIR
    print_info "清理完成"
}

# 构建Docker镜像
build_image() {
    print_info "开始构建Docker镜像..."
    
    # 检查Dockerfile是否存在
    if [ ! -f "Dockerfile" ]; then
        print_error "当前目录下未找到Dockerfile"
        exit 1
    fi
    
    # 检查docker命令是否可用
    if docker ps &>/dev/null; then
        # 当前用户可以直接运行docker
        docker build -t vllm-cu118:latest .
    else
        # 需要使用sudo（可能是组权限未生效）
        print_warn "当前用户无法直接运行docker，使用sudo构建"
        sudo docker build -t vllm-cu118:latest .
    fi
    check_status "镜像构建"
    
    # 显示镜像信息
    print_info "构建完成的镜像信息："
    if docker images &>/dev/null; then
        docker images | grep vllm-cu118
    else
        sudo docker images | grep vllm-cu118
    fi
}

# 主函数
main() {
    print_info "开始Docker ${DOCKER_VERSION} 二进制安装和镜像构建"
    
    # 检查sudo权限
    check_sudo
    
    # 配置docker组
    setup_docker_group
    
    # 下载Docker二进制包
    download_docker
    
    # 安装二进制文件
    install_docker_binaries
    
    # 创建配置文件
    create_docker_config
    
    # 停止可能运行的旧进程
    stop_docker
    
    # 后台启动dockerd
    start_docker_background
    
    # 验证安装
    verify_docker
    
    # 清理临时文件
    cleanup
    
    # 构建镜像
    build_image
    
    if [ "$NEED_RELOGIN" = true ]; then
        print_warn "=================================================="
        print_warn "重要提示：您已被添加到docker组"
        print_warn "请退出当前会话并重新登录，或执行 'newgrp docker' 命令"
        print_warn "之后即可无需sudo直接使用docker命令"
        print_warn "=================================================="
    fi
    
    print_info "脚本执行完成！"
}

# 执行主函数
NEED_RELOGIN=false
main