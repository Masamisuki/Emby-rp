#!/bin/bash
# 渲染 + 校验：source 主脚本，渲染各组合并交给 caddy validate
source /root/emby-rp.sh
mkdir -p /tmp/rt

set_site() {
	reset_site_vars
	SITE_NAME="demo"
	SITE_DOMAIN="emby.example.com"
	SITE_ENGINE="$1"
	SITE_MODE="$2"
	SITE_UPSTREAM="http://127.0.0.1:8096"
	SITE_EMAIL="admin@example.com"
	SITE_TLS="auto"
	if [[ "$2" == "split" ]]; then
		SITE_PREFIX="/emby"
		SITE_STRIP=0
		SITE_FRONTEND="dir:/var/www/emby-web"
	fi
	case "${3:-}" in
		strip) SITE_STRIP=1 ;;
		url) SITE_FRONTEND="http://127.0.0.1:8080" ;;
		insecure) SITE_UPSTREAM="https://10.0.0.5:8920"; SITE_UPSTREAM_INSECURE=1; SITE_CF=1 ;;
		nones) SITE_TLS="none"; SITE_HTTPS_PORT="80" ;;
		ports) SITE_HTTP_PORT="8080"; SITE_HTTPS_PORT="8443" ;;
		filecert) SITE_TLS="file"; SITE_CERT="/root/.caddybin/t.pem"; SITE_KEY="/root/.caddybin/t.key" ;;
		nolog) SITE_ACCESS_LOG=0 ;;
		h2on) SITE_HTTP2="on" ;;
		h2off) SITE_HTTP2="off" ;;
	esac
}

run() {
	local eng="$1" mode="$2" tag="$3"
	set_site "$eng" "$mode" "$tag"
	local f="/tmp/rt/${eng}-${mode}-${tag}.cfg"
	render_site > "$f" 2>/tmp/rt/err.txt || { echo "RENDER_FAIL $f"; cat /tmp/rt/err.txt; return; }
	if [[ "$eng" == "caddy" ]]; then
		if out="$(/root/.caddybin/caddy validate --adapter caddyfile --config "$f" 2>&1)"; then
			echo "OK   caddy $mode/$tag"
		else
			echo "FAIL caddy $mode/$tag"
			printf '%s\n' "$out" | sed 's/^/     /'
		fi
	else
		echo "RENDER nginx $mode/$tag -> $f（$(wc -l < "$f") 行，本机无 nginx，跳过 -t）"
	fi
}

for tag in default strip url insecure nones ports filecert nolog h2on h2off; do
	run caddy standalone "$tag"
	run caddy split "$tag"
	run nginx standalone "$tag"
	run nginx split "$tag"
done
