#!/bin/bash
# nginx 引擎端到端（tls=none，避免需要真实域名证书）
S=/root/emby-rp.sh
export NO_COLOR=1

echo "########## 0. 准备 ##########"
pkill -f 'http.server 8096' 2>/dev/null
rm -rf /etc/emby-rp /var/www/emby-rp-acme /usr/local/bin/emby-rp
rm -f /var/log/nginx/emby-rp-*.log
if command -v nginx >/dev/null 2>&1; then
	DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq nginx nginx-common >/dev/null 2>&1
fi
apt-get update -qq >/dev/null 2>&1 || true
mkdir -p /var/www/html
printf 'FRONTEND-OK\n' > /var/www/html/index.html
curl -s -o /dev/null --max-time 2 http://127.0.0.1:8096/ || {
	nohup python3 -m http.server 8096 --directory /var/www/html >/tmp/be.log 2>&1 &
	sleep 2
}

echo "########## 1. add (nginx / split / tls none / 8080) ##########"
EMBY_RP_YES=1 bash "$S" add -d test.local -e nginx -m split -p /emby \
	-F dir:/var/www/html --tls none --http-port 8080 -y
echo "rc=$?"

echo "########## 2. nginx -t ##########"
nginx -t 2>&1 | tail -3

echo "########## 3. 探针 ##########"
for u in /_emby_rp_health / /emby/System/Info/Public /emby; do
	printf '%-30s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: test.local' "http://127.0.0.1:8080$u")"
done
echo "-- 前缀跳转 Location:"
curl -s -o /dev/null -D - -H 'Host: test.local' http://127.0.0.1:8080/emby | grep -i '^location' || true

echo "########## 4. check ##########"
bash "$S" check test-local

echo "########## 5. status ##########"
bash "$S" status

echo "########## 6. uninstall ##########"
EMBY_RP_YES=1 bash "$S" uninstall

echo "########## 7. 卸载后 ##########"
ls -l /etc/emby-rp /usr/local/bin/emby-rp 2>&1 | head -3
dpkg -l nginx 2>/dev/null | tail -1
pgrep -a nginx || echo "no nginx process"
ss -lntp 2>/dev/null | grep 8080 || echo "no 8080 listener"
ls -l /etc/nginx/conf.d/ 2>&1 | head -5
echo "########## done ##########"
