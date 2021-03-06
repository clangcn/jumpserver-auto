#!/bin/bash
# coding: utf-8
#

set -e

Project=/opt

echo -e "\033[31m 欢迎使用本脚本安装 Jumpserver \033[0m"
echo -e "\033[31m 本脚本属于全自动安装脚本，无需人工干预及输入 \033[0m"
echo -e "\033[31m 本脚本仅适用于测试环境，如需用作生产，请自行修改相应配置 \033[0m"
echo -e "\033[31m 本脚本暂时只支持全新安装的 Centos7 \033[0m"
echo -e "\033[31m 本脚本将会把 Jumpserver 安装在 $Project 目录下 \033[0m"
echo -e "\033[31m 10秒后安装将开始，祝你好运 \033[0m"

sleep 10s

if [ ! -f "jumpserver.tar.gz" ]; then
	echo -e "\033[31m 不存在离线安装包 jumpserver.tar.gz \033[0m"
	echo -e "\033[31m 脚本自动退出 \033[0m"
	exit 1
else
	echo -e "\033[31m 检测到离线安装包 jumpserver.tar.gz \033[0m"
fi

echo -e "\033[31m 正在关闭 Selinux \033[0m"
setenforce 0 || true
sed -i "s/enforcing/disabled/g" `grep enforcing -rl /etc/selinux/config` || true

echo -e "\033[31m 正在关闭防火墙 \033[0m"
systemctl stop iptables.service || true
systemctl stop firewalld.service || true

if grep -q 'LANG="zh_CN.UTF-8"' /etc/locale.conf; then
	echo -e "\033[31m 当前环境已经是zh_CN.UTF-8 \033[0m"
else
	echo -e "\033[31m 设置环境zh_CN.UTF-8 \033[0m"
	localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8 && export LC_ALL=zh_CN.UTF-8 && echo 'LANG="zh_CN.UTF-8"' > /etc/locale.conf
fi

echo -e "\033[31m 正在解压离线包到 $Project 目录 \033[0m"
tar zxf jumpserver.tar.gz -C $Project
cd $Project && tar xf Python-3.6.1.tar.xz && tar xf luna.tar.gz
chown -R root:root luna/

echo -e "\033[31m 正在安装依赖包 \033[0m"
yum -y -q localinstall $Project/package/*.rpm --nogpgcheck

echo -e "\033[31m 正在安装 mariadb \033[0m"
yum -y -q localinstall $Project/package/mariadb/*.rpm --nogpgcheck

echo -e "\033[31m 正在安装 nginx \033[0m"
yum -y -q localinstall $Project/package/nginx/*.rpm --nogpgcheck

echo -e "\033[31m 正在安装 redis \033[0m"
yum -y -q localinstall $Project/package/redis/*.rpm --nogpgcheck

echo -e "\033[31m 正在配置 mariadb、nginx、rdis 服务自启 \033[0m"
systemctl enable mariadb && systemctl enable nginx && systemctl enable redis
systemctl restart mariadb && systemctl restart redis

echo -e "\033[31m 正在配置编译 python3 \033[0m"
cd $Project/Python-3.6.1 && ./configure >> /tmp/build.log && make >> /tmp/build.log && make install >> /tmp/build.log

echo -e "\033[31m 正在配置 python3 虚拟环境 \033[0m"
cd $Project
python3 -m venv $Project/py3
source $Project/py3/bin/activate || true

echo -e "\033[31m 正在安装依赖包 \033[0m"
yum -y -q localinstall $Project/package/jumpserver/*.rpm --nogpgcheck && yum -y -q localinstall $Project/package/coco/*.rpm --nogpgcheck
pip install --no-index --find-links="$Project/package/pip/jumpserver/" pyasn1 six cffi >> /tmp/build.log
pip install -r $Project/jumpserver/requirements/requirements.txt --no-index --find-links="$Project/package/pip/jumpserver/" >> /tmp/build.log
pip install -r $Project/coco/requirements/requirements.txt --no-index --find-links="$Project/package/pip/coco/" >> /tmp/build.log

echo -e "\033[31m 正在配置数据库 \033[0m"
mysql -uroot -e "
create database jumpserver default charset 'utf8';
grant all on jumpserver.* to 'jumpserver'@'127.0.0.1' identified by 'weakPassword';
flush privileges;
quit"

echo -e "\033[31m 正在处理 jumpserver 与 coco 配置文件 \033[0m"
cd $Project
cp $Project/jumpserver/config_example.py $Project/jumpserver/config.py
cp $Project/coco/conf_example.py $Project/coco/conf.py

sed -i "s/DB_ENGINE = 'sqlite3'/# DB_ENGINE = 'sqlite3'/g" `grep "DB_ENGINE = 'sqlite3'" -rl $Project/jumpserver/config.py`
sed -i "s/DB_NAME = os.path.join/# DB_NAME = os.path.join/g" `grep "DB_NAME = os.path.join" -rl $Project/jumpserver/config.py`
sed -i "s/# DB_ENGINE = 'mysql'/DB_ENGINE = 'mysql'/g" `grep "# DB_ENGINE = 'mysql'" -rl $Project/jumpserver/config.py`
sed -i "s/# DB_HOST = '127.0.0.1'/DB_HOST = '127.0.0.1'/g" `grep "# DB_HOST = '127.0.0.1'" -rl $Project/jumpserver/config.py`
sed -i "s/# DB_PORT = 3306/DB_PORT = 3306/g" `grep "# DB_PORT = 3306" -rl $Project/jumpserver/config.py`
sed -i "s/# DB_USER = 'root'/DB_USER = 'jumpserver'/g" `grep "# DB_USER = 'root'" -rl $Project/jumpserver/config.py`
sed -i "s/# DB_PASSWORD = ''/DB_PASSWORD = 'weakPassword'/g" `grep "# DB_PASSWORD = ''" -rl $Project/jumpserver/config.py`
sed -i "s/# DB_NAME = 'jumpserver'/DB_NAME = 'jumpserver'/g" `grep "# DB_NAME = 'jumpserver'" -rl $Project/jumpserver/config.py`

echo -e "\033[31m 正在初始化数据库 \033[0m"
cd $Project/jumpserver/utils && bash make_migrations.sh >> /tmp/build.log
cd $Project

echo -e "\033[31m 正在配置 nginx \033[0m"
cat << EOF > /etc/nginx/nginx.conf
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - $remote_user [\$time_local] "\$request" '
                      '\$status $body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

    		proxy_set_header X-Real-IP \$remote_addr;
       	proxy_set_header Host \$host;
    		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

    		location /luna/ {
        		try_files \$uri / /index.html;
        		alias $Project/luna/;
        }

    		location /media/ {
        		add_header Content-Encoding gzip;
        		root $Project/jumpserver/data/;
        }

    		location /static/ {
        		root $Project/jumpserver/data/;
        }

    		location /socket.io/ {
        		proxy_pass       http://localhost:5000/socket.io/;  # 如果coco安装在别的服务器，请填写它的ip
        		proxy_buffering off;
        		proxy_http_version 1.1;
        		proxy_set_header Upgrade \$http_upgrade;
        		proxy_set_header Connection "upgrade";
        }

				location /coco/ {
        		proxy_pass       http://localhost:5000/coco/;  # 如果coco安装在别的服务器，请填写它的ip
        		proxy_set_header X-Real-IP $remote_addr;
        		proxy_set_header Host $host;
        		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        		access_log off;
    		}

    		location /guacamole/ {
        		proxy_pass       http://localhost:8081/;  # 请填写运行docker服务的服务器ip，不更改此处Windows组件无法正常使用
        		proxy_buffering off;
        		proxy_http_version 1.1;
        		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        		proxy_set_header Upgrade \$http_upgrade;
        		proxy_set_header Connection \$http_connection;
        		access_log off;
        }

    		location / {
        		proxy_pass http://localhost:8080;  # 如果jumpserver安装在别的服务器，请填写它的ip
						proxy_set_header X-Real-IP $remote_addr;
        		proxy_set_header Host $host;
        		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    		}

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }
}

EOF

sleep 1s

echo -e "\033[31m 正在配置Windows组件 \033[0m"
yum -y -q localinstall $Project/package/docker/*.rpm --nogpgcheck
yum -y -q localinstall $Project/package/docker/docker-ce/*.rpm --nogpgcheck
systemctl enable docker
systemctl restart docker
docker load < $Project/guacamole.tar
serverip=`ip addr |grep inet|grep -v 127.0.0.1|grep -v inet6|grep -v docker|awk '{print $2}'|tr -d "addr:" |head -n 1`
ip=`echo ${serverip%/*}`
docker run --name jms_guacamole -d -p 8081:8080 -v $Project/guacamole/key:/config/guacamole/key -e JUMPSERVER_KEY_DIR=/config/guacamole/key -e JUMPSERVER_SERVER=http://$ip:8080 jumpserver/guacamole:latest

docker stop jms_guacamole

systemctl restart nginx

echo -e "\033[31m 正在配置脚本 \033[0m"
cat << EOF > $Project/start_jms.sh
#!/bin/bash

ps -ef | egrep '(gunicorn|celery|beat|cocod)' | grep -v grep
if [ \$? -ne 0 ]; then
  echo -e "\033[31m 不存在Jumpserver进程，正常启动 \033[0m"
else
  echo -e "\033[31m 检测到Jumpserver进程未退出，结束中 \033[0m"
  cd $Project && sh stop_jms.sh
  sleep 5s
  ps aux | egrep '(gunicorn|celery|beat|cocod)' | awk '{ print \$2 }' | xargs kill -9
fi
source $Project/py3/bin/activate
cd $Project/jumpserver && ./jms start -d
cd $Project/coco && ./cocod start -d
docker start jms_guacamole
exit 0
EOF

sleep 1s
cat << EOF > $Project/stop_jms.sh
#!/bin/bash

source $Project/py3/bin/activate
cd $Project/coco && ./cocod stop
docker stop jms_guacamole
cd $Project/jumpserver && ./jms stop
exit 0
EOF

sleep 1s
chmod +x $Project/start_jms.sh
chmod +x $Project/stop_jms.sh

echo -e "\033[31m 正在写入开机自启 \033[0m"
if grep -q 'sh $Project/start_jms.sh' /etc/rc.local; then
	echo -e "\033[31m 自启脚本已经存在 \033[0m"
else
	chmod +x /etc/rc.local
	echo "sh $Project/start_jms.sh" >> /etc/rc.local
fi

echo -e "\033[31m 正在配置autoenv \033[0m"
if grep -q 'source $Project/autoenv/activate.sh' ~/.bashrc; then
	echo -e "\033[31m autoenv 已经配置 \033[0m"
else
	echo 'source $Project/autoenv/activate.sh' >> ~/.bashrc
fi

echo 'source $Project/py3/bin/activate' > $Project/jumpserver/.env
echo 'source $Project/py3/bin/activate' > $Project/coco/.env

cd $Project && sh start_jms.sh >> /tmp/build.log

echo -e "\033[31m 如果启动失败请到 $Project 目录下手动执行 start_jms.sh 启动 Jumpserver \033[0m"
echo -e "\033[31m 安装 log 请查看 /tmp/build.log \033[0m"
echo -e "\033[31m 访问 http://$ip \033[0m"

exit 0
