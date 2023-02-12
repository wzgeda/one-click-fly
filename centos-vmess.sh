#!/bin/bash
function main {
    # rebuild yum cache
    yum makecache
    
    # install require
    yum install certbot nginx unzip -y
    base_url=https://github.com/XTLS/Xray-core
    version=$(curl ${base_url} | grep 'style="max-width: none' | sed -r 's|.*Xray-core (.*)<\/span>|\1|')
    download_url=$base_url/releases/download/${version}/Xray-linux-64.zip
    wget ${download_url} -O Xray-linux-64.zip
    unzip -o Xray-linux-64.zip -d ./xray

    # get certificate
    read -p "请输入要获取证书的域名: " sni
    certbot certonly --standalone -d ${sni}
    ca=/etc/letsencrypt/live/${sni}/fullchain.pem
    key=/etc/letsencrypt/live/${sni}/privkey.pem


    read -p "请输入ssl端口(默认:443): " ssl_port
    if [ -z ${ssl_port} ];then
        ssl_port=443
    fi
    read -p "请输入vmess端口(默认:10000): " vmess_port
    if [ -z ${vmess_port} ];then
        vmess_port=10000
    fi
    read -p "请输入vmess密码(id): " id
    read -p "请输入websocket路径(例如:/ray,请自定义不要使用/ray): " path

    # config xray
    systemctl stop xray
    \cp ./xray/xray /usr/bin/
    if [ ! -d "/etc/xray/" ];then
        mkdir /etc/xray/
    fi

    # xray configfile
    cat > /etc/xray/config.json <<-EOF
{
  "inbounds": [
    {
      "port": ${vmess_port},
      "listen":"127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${id}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "${path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    # xray service
    cat > /etc/systemd/system/xray.service <<-EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=nobody
ExecStart=/usr/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray

    
    # config nginx
    cat > /etc/nginx/nginx.conf <<-EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
include /usr/share/nginx/modules/*.conf;
events {
    worker_connections 1024;
}
http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;
    include /etc/nginx/conf.d/*.conf;
    server {
        listen ${ssl_port} ssl;
        listen [::]:${ssl_port} ssl;
      
        ssl_certificate       ${ca};
        ssl_certificate_key   ${key};
        ssl_session_timeout 1d;
        ssl_session_cache shared:MozSSL:10m;
        ssl_session_tickets off;
        ssl_protocols         TLSv1.2 TLSv1.3;
        ssl_ciphers           ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        server_name           ${sni};
        location ${path} {
            if (\$http_upgrade != "websocket") {
                return 404;
            }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:${vmess_port};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
    }
}
EOF
    rm -rf /usr/share/nginx/html/*
    echo "not" > /usr/share/nginx/html/index.html
    systemctl enable nginx
    systemctl restart nginx
    echo "ssl端口: ${ssl_port}"
    echo "域名: ${sni}"
    echo "证书: ${ca}"
    echo "证书key: ${key}"
    echo "websocket目录: ${path}"
    echo "vmess id: ${id}"
    # cron
    echo "0 2 * * * certbot renew" > /var/spool/cron/root
}
main
