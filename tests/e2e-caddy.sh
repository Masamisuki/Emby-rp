#!/bin/bash
# 真机端到端测试
S=/root/emby-rp.sh
export NO_COLOR=1

echo "########## 0. 加一个假后端 ##########"
# 清掉上一轮可能的残留，保证从干净状态开始
pkill -f 'http.server 8096' 2>/dev/null
rm -rf /etc/emby-rp /var/www/emby-rp-acme /usr/local/bin/emby-rp
rm -f /var/log/caddy/emby-rp-*.log /var/log/nginx/emby-rp-*.log
if command -v caddy >/dev/null 2>&1; then
	DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq caddy >/dev/null 2>&1
fi
apt-get update -qq >/dev/null 2>&1 || true
mkdir -p /var/www/html
printf 'FRONTEND-OK\n' > /var/www/html/index.html
if ! curl -s -o /dev/null --max-time 2 http://127.0.0.1:8096/; then
	nohup python3 -m http.server 8096 --directory /var/www/html >/tmp/be.log 2>&1 &
	sleep 2
fi
curl -s -o /dev/null -w 'backend: %{http_code}\n' http://127.0.0.1:8096/

echo "########## 1. add (caddy / split / tls none / 8080) ##########"
EMBY_RP_YES=1 bash "$S" add -d test.local -e caddy -m split -p /emby \
	-F dir:/var/www/html --tls none --http-port 8080 -y
echo "rc=$?"

echo "########## 2. list ##########"
bash "$S" list

echo "########## 3. status ##########"
bash "$S" status

echo "########## 4. 真实 HTTP 探针 ##########"
for u in /_emby_rp_health / /emby/System/Info/Public; do
	printf '%-28s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: test.local' "http://127.0.0.1:8080$u")"
done

echo "########## 5. check ##########"
bash "$S" check test-local

echo "########## 6. logs ##########"
bash "$S" logs test-local | tail -5

echo "########## 7. render ##########"
bash "$S" render test-local | head -12

echo "########## 8. uninstall ##########"
EMBY_RP_YES=1 bash "$S" uninstall
echo "rc=$?"

echo "########## 9. 卸载后核查 ##########"
echo "-- /usr/local/bin/emby-rp:" ; ls -l /usr/local/bin/emby-rp 2>&1
echo "-- /etc/emby-rp:" ; ls -l /etc/emby-rp 2>&1
echo "-- caddy 包:" ; dpkg -l caddy 2>/dev/null | tail -2
echo "-- caddy 进程:" ; pgrep -a caddy || echo none
echo "-- 8080 监听:" ; ss -lntp 2>/dev/null | grep 8080 || echo none
echo "########## done ##########"
