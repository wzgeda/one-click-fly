#!/bin/bash
function main(){    
    # update
    apt update

    # download requires
    apt install certbot nginx unzip -y
    base_url=https://github.com/XTLS/Xray-core
    version=$(curl ${base_url} | grep 'style="max-width: none' | sed -r 's|.*Xray-core (.*)<\/span>|\1|')
    download_url=$base_url/releases/download/${version}/Xray-linux-64.zip
    wget ${download_url} -O Xray-linux-64.zip
    unzip -o Xray-linux-64.zip -d ./xray
    
    # configure nginx
    systemctl enable nginx
    sed -e '/listen.*\[::\]:80/d' -re 's/80/81/' -i.bak /etc/nginx/sites-available/default
    rm -rf /var/www/html/*
    echo "not" > /var/www/html/index.html
    systemctl restart nginx

    # get certificate
    read -p "sni " sni
    certbot certonly --standalone -d ${sni}
    ca=/etc/letsencrypt/live/${sni}/fullchain.pem
    key=/etc/letsencrypt/live/${sni}/privkey.pem

    read -p "ssl port: " ssl_port
    if [ -z ${ssl_port} ];then
        ssl_port=443
    fi
    read -p "vmess id: " id
    read -p "websocket path(demo:/ray): " path
    
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
    
    # print config
    echo "ssl port: ${ssl_port}"
    echo "sni: ${sni}"
    echo "ca: ${ca}"
    echo "key: ${key}"
    echo "websocket path: ${path}"
    echo "vmess id: ${id}"
    
    # cron
    echo "0 2 * * * certbot renew" > /var/spool/cron/root
}
main
