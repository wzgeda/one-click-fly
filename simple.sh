#!/bin/bash
function install(){
    # 开启防火墙并创建开机启动服务
    systemctl enable --now firewalld

    # 关闭22端口，关闭sshd服务
    firewall-cmd --permanent --remove-service=ssh
    firewall-cmd --reload
    systemctl stop sshd
    systemctl disable sshd

    # 重建软件仓库缓存索引
    yum makecache

    # 安装certbot unzip
    yum install certbot unzip -y
 
    # 开始认证
    read -p "Please enter the domain name you want to authenticate: " sni
    firewall-cmd --add-service=http
    certbot certonly --standalone -d ${sni}

    # 设置证书与key文件地址变量ca与key
    ca=/etc/letsencrypt/live/${sni}/fullchain.pem
    key=/etc/letsencrypt/live/${sni}/privkey.pem

    # 定义变量,获取版本号与最新trojan-go下载地址,下载并解压
    base_url=https://github.com/gfw-report/trojan-go
    version=$(curl ${base_url} | grep 'style="max-width: none' | sed -r 's|.*>(v.*)<.*|\1|')
    download_url=$base_url/releases/download/${version}/trojan-go-linux-amd64.zip
    wget ${download_url} -O trojan-go-linux-amd64.zip
    unzip -o trojan-go-linux-amd64.zip -d ./trojan-go
    # 拷贝trojan-go到bin
    \cp ./trojan-go/trojan-go /usr/bin/
    if [ ! -d "/etc/trojan-go/" ];then
        # 创建trojan-go配置目录
        mkdir /etc/trojan-go/
    fi

    # 创建server.json文件
    read -p "Please enter the trojan-go port number: " port
    read -p "Please enter the trojan-go password: " password
    cat > /etc/trojan-go/server.json <<-EOF
    {
        "run_type": "server",
        "local_addr": "0.0.0.0",
        "local_port": ${port},
        "remote_addr": "www.czce.com.cn",
        "remote_port": 80,
        "password": [
            "${password}"
        ],
        "ssl": {
            "cert": "${ca}",
            "key": "${key}",
            "sni": "${sni}"
        }
    }
EOF

    # 创建trojan-go服务
    cat > /etc/systemd/system/trojan-go.service <<-EOF
    [Unit]
    Description=Trojan-Go - An unidentifiable mechanism that helps you bypass GFW
    Documentation=https://p4gefau1t.github.io/trojan-go/
    After=network.target nss-lookup.target

    [Service]
    User=root
    CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
    AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
    NoNewPrivileges=true
    ExecStart=/usr/bin/trojan-go -config /etc/trojan-go/server.json
    Restart=on-failure
    RestartSec=10s
    LimitNOFILE=infinity

    [Install]
    WantedBy=multi-user.target
EOF
    # 配置续期证书定时任务每天执行certbot renew
    \cp ./simple.sh /opt/
    echo "0 2 * * * bash /opt/simple.sh renew" > /var/spool/cron/root
    
    # 开启trojan-go防火墙端口
    firewall-cmd --permanent --add-port=${port}/tcp
    firewall-cmd --reload
    # 重新载入systemctl配置文件
    systemctl daemon-reload
    # 启动trojan-go服务
    systemctl restart trojan-go
    # 配置开机启动服务
    systemctl enable trojan-go
    # 生成客户端配置文件
    cat > client.json <<-EOF
    {
        "run_type": "client",
        "local_addr": "127.0.0.1",
        "local_port": 1080,
        "remote_addr": "${sni}",
        "remote_port": ${port},
        "password": [
            "${password}"
        ],
        "ssl": {
            "sni": "${sni}"
        },
        "mux": {
            "enabled": true
        }
    }
EOF
    # 显示当前状态
    systemctl status trojan-go
}

function renew(){
    echo 临时开启http端口
    firewall-cmd --add-service=http
    certbot renew
    firewall-cmd --reload
}
case $1 in
    install)
        install
        ;;
    renew)
        renew
        ;;
    *)
        echo '错误选项，只有安装(install)与证书续期(renew)选项'
esac
