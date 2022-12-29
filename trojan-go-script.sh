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

    # 安装certbot nginx unzip
    yum install certbot python2-certbot-nginx nginx unzip -y

    # 创建nginx开机启动
    systemctl enable nginx

    if [ ! -f /etc/nginx/nginx.conf.bak ];then
        # nginx.conf备份不存在,备份生成nginx.conf.bak
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    fi
    read -p "Please enter the domain name you want to authenticate: " sni
    # 为认证修改nginx.conf配置
    sed -i "s/server_name.*_;/server_name\t${sni};/" /etc/nginx/nginx.conf

    # 重启nginx服务
    systemctl restart nginx

    # 删除默认html网页新建一个index.html
    rm -rf /usr/share/nginx/html/*
    echo "not" > /usr/share/nginx/html/index.html

    # 为认证临时开启http防火墙
    firewall-cmd --add-service=http

    # 开始认证
    certbot --nginx -d ${sni}

    # 设置证书与key文件地址变量ca与key
    ca=/etc/letsencrypt/live/${sni}/fullchain.pem
    key=/etc/letsencrypt/live/${sni}/privkey.pem

    # 恢复因为认证被修改的nginx.conf
    \cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf

    # echo nginx只监听本地网络
    # sed -e '/listen.*\[::\]:80.*/d' -e 's/listen.*80;/listen\t127.0.0.1:80;/' -i /etc/nginx/nginx.conf

    echo 重启nginx服务
    systemctl restart nginx

    # 定义变量,获取版本号与最新trojan-go下载地址,下载并解压
    base_url=https://github.com/p4gefau1t/trojan-go
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
    if [ -f "/etc/trojan-go/server.json" ];then
        # 如果存在server.json 删除
        rm -f /etc/trojan-go/server.json  
    fi

    # 创建server.json文件
    read -p "Please enter the trojan-go port number: " port
    read -p "Please enter the trojan-go password: " password
    cat > /etc/trojan-go/server.json <<-EOF
    {
        "run_type": "server",
        "local_addr": "0.0.0.0",
        "local_port": ${port},
        "remote_addr": "127.0.0.1",
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
    
    if [ ! -f /etc/systemd/system/trojan-go.service ];then
        sudo rm -f /etc/systemd/system/trojan-go.service
    fi
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
    \cp ./trojan-go-script.sh /opt/
    echo "0 2 * * * /opt/trojan-go-script.sh renew" > /var/spool/cron/root
    
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
