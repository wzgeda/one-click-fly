#!/bin/bash
function install(){
    # 开启防火墙并创建开机启动服务
    systemctl enable --now firewalld
    # 开启http服务,为获取证书使用
    firewall-cmd --add-service=http --permanent
    firewall-cmd --reload
    
    # 重建软件仓库缓存索引
    yum makecache

    # 下载所需软件
    yum install certbot nginx unzip -y
    base_url=https://github.com/p4gefau1t/trojan-go
    version=$(curl ${base_url} | grep 'style="max-width: none' | sed -r 's|.*>(v.*)<.*|\1|')
    download_url=$base_url/releases/download/${version}/trojan-go-linux-amd64.zip
    wget ${download_url} -O trojan-go-linux-amd64.zip
    unzip -o trojan-go-linux-amd64.zip -d ./trojan-go
    
    # 配置nginx
    systemctl enable nginx
    sed -e '/listen.*\[::\]:80/d' -re 's/listen(.*)80;/listen\181;/' -i.bak /etc/nginx/nginx.conf
    rm -rf /usr/share/nginx/html/*
    echo "not" > /usr/share/nginx/html/index.html
    systemctl restart nginx

    # 配置certbot获取证书
    read -p "Please enter the domain name you want to authenticate: " sni
    certbot certonly --standalone -d ${sni}
    ca=/etc/letsencrypt/live/${sni}/fullchain.pem
    key=/etc/letsencrypt/live/${sni}/privkey.pem
    
    
    # 配置trojan-go
    systemctl stop trojna-go
    \cp ./trojan-go/trojan-go /usr/bin/
    if [ ! -d "/etc/trojan-go/" ];then
        mkdir /etc/trojan-go/
    fi
    read -p "Please enter the trojan-go port number: " port
    read -p "Please enter the trojan-go password: " tpassword
    read -p "Please enter the websokcet path: " path
    read -p "Please enter the shadowsocks method(default:aes-128-gcm): " method
    read -p "Please enter the shadowsocks password: " spassword
    if [ -z ${method} ];then
        method=aes-128-gcm
    fi
    echo -e "port: ${port}\ntpssword: ${tpassword}\npath: ${path}\nmethod: ${method}\nspassword: ${spassword}"
    # 生成trojan-go服务端配置
    cat > /etc/trojan-go/server.json <<-EOF
    {
        "run_type": "server",
        "local_addr": "0.0.0.0",
        "local_port": ${port},
        "remote_addr": "127.0.0.1",
        "remote_port": 81,
        "password": [
            "${tpassword}"
        ],
        "ssl": {
            "cert": "${ca}",
            "key": "${key}",
            "sni": "${sni}"
        },
        "websocket": {
            "enabled": true,
            "path": "${path}",
            "host": "${sni}"
        },
        "shadowsocks": {
            "enabled": true,
            "method": "${method}",
            "password": "${spassword}"
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
    systemctl daemon-reload
    

    
    # 开启trojan-go防火墙端口
    firewall-cmd --permanent --add-port=${port}/tcp
    firewall-cmd --reload
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
        "websocket": {
            "enabled": true,
            "path": "${path}",
            "host": "${sni}"
        },
        "shadowsocks": {
            "enabled": true,
            "method": "${method}",
            "password": "${spassword}"
        },
        "mux": {
            "enabled": true
        }
    }
EOF
    # 显示当前状态
    systemctl status trojan-go
    
    # 配置续期证书定时任务每天执行certbot renew
    echo "0 2 * * * certbot renew" > /var/spool/cron/root
}
install
