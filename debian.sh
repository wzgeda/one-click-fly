#!/bin/bash
function install(){
    # start ufw
    ufw enable
    systemctl enable ufw

    # close sshd
    ufw delete allow 22
    systemctl stop sshd
    systemctl disable sshd

    # update
    apt update

    # download requires
    apt install certbot nginx unzip -y
    base_url=https://github.com/p4gefau1t/trojan-go
    version=$(curl ${base_url} | grep 'style="max-width: none' | sed -r 's|.*>(v.*)<.*|\1|')
    download_url=$base_url/releases/download/${version}/trojan-go-linux-amd64.zip
    wget ${download_url} -O trojan-go-linux-amd64.zip
    unzip -o trojan-go-linux-amd64.zip -d ./trojan-go
    
    # configure nginx
    systemctl enable nginx
    sed -e '/listen.*\[::\]:80/d' -re 's/80/81/' -i.bak /etc/nginx/sites-available/default
    rm -rf /var/www/html/*
    echo "not" > /var/www/html/index.html
    systemctl restart nginx

    # configure certbot
    ufw allow 80/tcp
    read -p "Please enter the domain name you want to authenticate: " sni
    certbot certonly --standalone -d ${sni}
    ca=/etc/letsencrypt/live/${sni}/fullchain.pem
    key=/etc/letsencrypt/live/${sni}/privkey.pem
    ufw delete allow 80/tcp
    
    # configure trojan-go
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
    # generate server config
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
    
    # create trojan-go service
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
    

    
    # enable trojan-go port
    ufw allow ${port}/tcp
    # enable trojan-go serive
    systemctl restart trojan-go
    # configure Boot
    systemctl enable trojan-go
    # generate client config
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
    # display status
    systemctl status trojan-go
}
    # configure scheduled tasks (certbot)
    \cp ./debian.sh /opt/
    echo "0 2 * * * bash /opt/debian.sh renew" > /var/spool/cron/root
    
function renew(){
    echo temporary opening port
    ufw allow 80/tcp
    certbot renew
    ufw delete allow 80/tcp
}
case $1 in
    install)
        install
        ;;
    renew)
        renew
        ;;
    *)
        echo 'error，only install and renew options'
esac
