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
      "port": ${ssl_port},
      "listen":"0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${id}",
            "alterId": 0
          }
        ],
        "fallbacks": [
            {
                "dest": 81
            }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
            "certificates": [
                {
                    "certificateFile": "${ca}",
                    "keyFile": "${key}"
                }
            ]
        },
        "wsSettings": {
            "path": "${path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
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
User=root
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
        listen       81;
        server_name  127.0.0.1;
        root         /usr/share/nginx/html;

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        error_page 404 /404.html;
        location = /404.html {
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
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
