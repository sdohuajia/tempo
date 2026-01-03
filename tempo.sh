#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 部署节点函数
function deploy_node() {
    set -e  # 遇到错误立即退出
    
    echo "=========================================="
    echo "Tempo 节点一键安装脚本"
    echo "=========================================="
    echo ""

    # 步骤1: 更新系统并安装依赖
    echo -e "${GREEN}[1/9] 更新系统并安装依赖包...${NC}"
    sudo apt update && sudo apt -y upgrade
    sudo apt install -y curl screen iptables build-essential git wget lz4 jq make gcc nano openssl \
    automake autoconf htop nvme-cli pkg-config libssl-dev libleveldb-dev \
    tar clang bsdmainutils ncdu unzip ca-certificates net-tools iputils-ping

    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
    echo ""

    # 步骤2: 安装 Rust
    echo -e "${GREEN}[2/9] 检查并安装 Rust...${NC}"
    
    # 检查 Rust 是否已安装
    if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
        echo -e "${YELLOW}检测到 Rust 已安装，跳过安装步骤${NC}"
        # 刷新环境变量（如果存在）
        if [ -f "$HOME/.cargo/env" ]; then
            source $HOME/.cargo/env
        fi
        export PATH="$HOME/.cargo/bin:$PATH"
        hash -r
    else
        echo -e "${GREEN}正在安装 Rust...${NC}"
        # 设置环境变量跳过路径检查
        export RUSTUP_INIT_SKIP_PATH_CHECK=yes
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        
        # 刷新环境变量
        source $HOME/.cargo/env
        export PATH="$HOME/.cargo/bin:$PATH"
        hash -r
    fi

    # 验证 Rust 安装
    echo -e "${GREEN}验证 Rust 安装...${NC}"
    rustc --version
    cargo --version

    echo -e "${GREEN}✓ Rust 安装完成${NC}"
    echo ""

    # 步骤3: 安装 Tempo
    echo -e "${GREEN}[3/9] 安装 Tempo...${NC}"
    cargo install --git https://github.com/tempoxyz/tempo.git tempo --root /usr/local --force

    echo -e "${GREEN}✓ Tempo 安装完成${NC}"
    echo ""

    # 步骤4: 验证安装
    echo -e "${GREEN}[4/9] 验证 Tempo 安装...${NC}"
    export PATH=/usr/local/bin:$PATH
    hash -r
    
    # 验证 tempo 命令是否可用
    if command -v tempo &> /dev/null; then
        echo -e "${GREEN}✓ Tempo 命令已安装${NC}"
        tempo --help | head -n 5
    else
        echo -e "${RED}错误: Tempo 安装失败${NC}"
        set +e
        return 1
    fi

    echo ""
    echo -e "${YELLOW}等待 2 秒...${NC}"
    sleep 2
    echo ""

    # 步骤5: 询问用户是否创建密钥
    echo -e "${YELLOW}[5/9] 是否创建密钥？${NC}"
    read -p "是否创建新的密钥对？(y/n): " create_key

    if [[ "$create_key" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}创建密钥目录...${NC}"
        mkdir -p $HOME/tempo/keys
        
        echo -e "${GREEN}生成私钥...${NC}"
        tempo consensus generate-private-key --output $HOME/tempo/keys/signing.key
        
        echo ""
        echo -e "${GREEN}[6/9] 显示公钥...${NC}"
        tempo consensus calculate-public-key --private-key $HOME/tempo/keys/signing.key
        
        echo ""
        echo -e "${YELLOW}等待 5 秒...${NC}"
        sleep 5
        echo ""
    else
        echo -e "${YELLOW}跳过密钥创建${NC}"
        if [ ! -f "$HOME/tempo/keys/signing.key" ]; then
            echo -e "${RED}错误: 未找到密钥文件 $HOME/tempo/keys/signing.key${NC}"
            echo -e "${YELLOW}请确保密钥文件已存在，或重新运行脚本并选择创建密钥${NC}"
            set +e
            return 1
        fi
    fi

    # 步骤7: 创建 screen 会话并下载数据
    echo -e "${GREEN}[7/9] 准备下载数据...${NC}"
    mkdir -p $HOME/tempo/data

    echo -e "${GREEN}下载区块链数据（这可能需要一些时间）...${NC}"
    tempo download --datadir $HOME/tempo/data

    echo -e "${GREEN}✓ 数据下载完成${NC}"
    echo ""

    # 步骤8: 获取钱包地址
    echo -e "${GREEN}[8/9] 配置节点运行参数...${NC}"
    read -p "请输入您的钱包地址 (cuzdan_adresi): " wallet_address

    if [ -z "$wallet_address" ]; then
        echo -e "${RED}错误: 钱包地址不能为空${NC}"
        set +e
        return 1
    fi

    echo ""
    echo -e "${GREEN}[9/9] 启动 Tempo 节点...${NC}"
    echo -e "${YELLOW}节点将在 screen 会话中运行${NC}"
    echo -e "${YELLOW}使用 'screen -r tempo' 查看节点运行状态${NC}"
    echo -e "${YELLOW}使用 Ctrl+A+D 退出 screen 会话（节点将继续运行）${NC}"
    echo ""

    # 创建启动脚本
    cat > $HOME/tempo/start_node.sh << EOF
#!/bin/bash
tempo node --datadir $HOME/tempo/data \\
  --chain testnet \\
  --port 30303 \\
  --discovery.addr 0.0.0.0 \\
  --discovery.port 30303 \\
  --consensus.signing-key $HOME/tempo/keys/signing.key \\
  --consensus.fee-recipient $wallet_address
EOF

    chmod +x $HOME/tempo/start_node.sh

    # 在 screen 中启动节点
    screen -dmS tempo bash -c "$HOME/tempo/start_node.sh"

    echo -e "${GREEN}=========================================="
    echo -e "安装完成！节点已启动${NC}"
    echo -e "${GREEN}=========================================="
    echo ""
    echo -e "常用命令："
    echo -e "  查看节点: ${YELLOW}screen -r tempo${NC}"
    echo -e "  退出 screen: ${YELLOW}Ctrl+A, 然后按 D${NC}"
    echo -e "  停止节点: ${YELLOW}screen -S tempo -X quit${NC}"
    echo -e "  重启节点: ${YELLOW}screen -dmS tempo bash -c '$HOME/tempo/start_node.sh'${NC}"
    echo ""
    echo -e "节点配置："
    echo -e "  数据目录: ${YELLOW}$HOME/tempo/data${NC}"
    echo -e "  密钥文件: ${YELLOW}$HOME/tempo/keys/signing.key${NC}"
    echo -e "  钱包地址: ${YELLOW}$wallet_address${NC}"
    echo ""
    
    set +e
    echo -e "${YELLOW}按 Enter 键返回主菜单...${NC}"
    read
}

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "================================================================"
        echo "脚本由哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "如有问题，可联系推特，仅此只有一个号"
        echo "================================================================"
        echo "退出脚本，请按键盘 Ctrl + C"
        echo "请选择要执行的操作:"
        echo ""
        echo -e "  ${GREEN}1${NC}. 部署节点"
        echo ""
        read -p "请输入选项 (1): " choice
        
        case $choice in
            1)
                deploy_node
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                sleep 2
                ;;
        esac
    done
}

# 启动主菜单
main_menu

