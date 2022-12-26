#!/bin/bash
echo 开启防火墙并创建开机启动服务
sudo systemctl enable --now firewalld

echo 关闭22端口，关闭sshd服务
sudo firewall-cmd --permanent --remove-service=ssh
sudo firewall-cmd --reload
sudo systemctl stop sshd
sudo systemctl disable sshd

echo 重建软件仓库缓存索引
sudo yum makecache

echo 安装certbot nginx unzip
sudo yum install certbot python2-certbot-nginx nginx unzip -y

echo 创建nginx开机启动
sudo systemctl enable nginx

if [ ! -f /etc/nginx/nginx.conf.bak ];then
    echo nginx.conf备份不存在备份生成nginx.conf.bak
    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
fi
read -p "请输入想要认证的域名: " sni
echo 为认证修改nginx.conf配置
sudo sed -i "s/server_name.*_;/server_name\t${sni};/" /etc/nginx/nginx.conf

echo 重启nginx服务
sudo systemctl restart nginx

echo 删除默认html网页新建一个index.html
sudo rm -rf /usr/share/nginx/html/*
echo "not" > /usr/share/nginx/html/index.html

echo 为认证临时开启http防火墙
sudo firewall-cmd --add-service=http

echo 开始认证
sudo certbot --nginx -d ${sni}

echo 设置证书与key文件地址变量ca与key
ca=/etc/letsencrypt/live/${sni}/fullchain.pem
key=/etc/letsencrypt/live/${sni}/privkey.pem

echo 恢复因为认证被修改的nginx.conf
sudo \cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf

# echo nginx只监听本地网络
# sed -e '/listen.*\[::\]:80.*/d' -e 's/listen.*80;/listen\t127.0.0.1:80;/' -i /etc/nginx/nginx.conf

echo 重启nginx服务
sudo systemctl restart nginx

# echo 切换至工作目录
# cd /root
echo 定义变量,获取版本号与最新trojan-go下载地址,下载并解压
base_url=https://github.com/p4gefau1t/trojan-go
version=$(curl ${base_url} | grep 'style="max-width: none' | sed -r 's|.*>(v.*)<.*|\1|')
download_url=$base_url/releases/download/${version}/trojan-go-linux-amd64.zip
wget ${download_url}
unzip -o trojan-go-linux-amd64.zip -d ./trojan-go
echo 拷贝trojan-go到bin
cd trojan-go
sudo \cp trojan-go /usr/bin/
if [ ! -d "/etc/trojan-go/" ];then
    echo 创建trojan-go配置文件
    sudo mkdir /etc/trojan-go/
fi
if [ ! -f "/etc/trojan-go/server.json" ];then
    sudo rm -f /etc/trojan-go/server.json  
fi

echo 创建server.json文件
read -p "请输入端口号,密码,websocket路径: " port password path
sudo cat > /etc/trojan-go/server.json <<EOF
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
    },
    "websocket": {
        "enabled": true,
        "path": "${path}",
        "host": "${sni}"
    },
    "shadowsocks": {
        "enabled": true,
        "password": "${password}"
    }
}
EOF
if [ ! -f /etc/systemd/system/trojan-go.service ];then
    sudo rm -f /etc/systemd/system/trojan-go.service
fi
echo 创建trojan-go服务
sudo cat > /etc/systemd/system/trojan-go.service <<EOF
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
echo 开启trojan-go防火墙端口
sudo firewall-cmd --permanent --add-port=${port}/tcp
sudo firewall-cmd --reload
echo 重新载入systemctl配置文件
sudo systemctl daemon-reload
echo 启动trojan-go服务
sudo systemctl restart trojan-go
echo 配置开机启动服务
sudo systemctl enable trojan-go
sudo systemctl status trojan-go
