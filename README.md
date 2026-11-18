# emby-rp — Emby / Jellyfin 反向代理管理器

单文件 bash 脚本，零外部依赖，一次装好就能用 `emby-rp` 管理多站点。
同时支持两种反代形态：

| 模式 | 说明 | 适用场景 |
|---|---|---|
| `standalone` | 域名根路径 = Emby/Jellyfin 本身，含官方 Web UI、WebSocket、图片、HLS | 自用、给朋友开号、直接换掉 `:8096` |
| `split` | 根路径给**前端**（静态目录或另一个后端），`/前缀` 回源 **Emby 后端** | 前后端分离：自己的播放页/门户 + 官方 API |

引擎可选 **Caddy**（自动申请 HTTPS，推荐）或 **Nginx**（配 certbot，适合已有 nginx 的机器）。

---

## 为什么不用现成的 `wuuduf/emby-proxy`

那个脚本能跑，但它把「前后端分离」当成窄路走，有几处硬限制：

1. `path` 模式**禁止**使用 `/emby`、`/emby/*`、`/web`、`/.well-known`、`/_emby_proxy_health` 作为前缀，直接 `die`。
2. 非根路径一律**剥前缀**回源（`handle_path` / `location ^~ … proxy_pass upstream/`），所以后端 Emby 的 Base URL 必须留空。
3. 它只重写 `Location` / `Content-Location` 响应头，**不重写 body**。Emby 官方 Web UI 里塞满了绝对路径 `/web/index.html`、`/embywebsocket`，一旦套在 `/foo/` 下面，播放页、图片、字幕就半残。
4. `subdomain` / `port` 模式只允许一个根上游，想做「根给前端、前缀给后端」得先落到 `path` 模式，再撞上面第 2 条的墙。

`emby-rp` 的处理方式：

- **默认「不剥前缀」（keep）**：`/emby/xxx` 原样转给后端，同时把 Emby 的 `Base URL` 设成 `/emby`。
  Emby 会自己在所有 URL 前面加 `/emby`，官方 Web UI、`/emby/embywebsocket`、图片、HLS 切片全部自洽，不会出现半残。
- **`--strip` 只作为兼容开关**：后端是别人的、动不了 Base URL 时才用。
- **`/emby` 随便用**，只禁止 `/`、`/.well-known`、`/_emby_rp_health`（这三个真会和内置逻辑打架）。
- 所有落地物登记在 `/etc/emby-rp`，`uninstall` 按清单清除，结束后自动做**残留自检**。

---

## 安装 / 运行

不需要安装，`bash emby-rp.sh` 就能跑；第一次 `add` 会自动把自身复制到 `/usr/local/bin/emby-rp`。

```bash
curl -fsSL -o /root/emby-rp.sh https://example.com/emby-rp.sh   # 或自己 scp 上去
bash /root/emby-rp.sh menu        # 交互菜单
```

首次使用建议先跑菜单里的「新建站点」，向导会问完所有参数。

---

## 三种典型用法

### 1. 最普通：整站 HTTPS 反代到本机 Emby

```bash
emby-rp add -d emby.example.com -y
```

等价于 Caddy + 自动 ACME + 反代 `http://127.0.0.1:8096`，打开 `https://emby.example.com` 就是 Emby。

### 2. 前后端分离（推荐姿势：keep 前缀）

根路径放你自己的前端，`/emby` 给后端：

```bash
emby-rp add -d emby.example.com -m split -p /emby \
  -F dir:/var/www/emby-web \
  -u http://127.0.0.1:8096 -y
```

然后**必须**在后端 Emby 里设一次 Base URL：

- Emby：`设置 → 高级 → 主机(Base URL)` → `/emby`
- Jellyfin：`控制台 → 网络 → Base URL` → `/emby`

设完重启 Emby。之后：

- 前端：`https://emby.example.com/` → `/var/www/emby-web`
- 接口：`https://emby.example.com/emby/System/Info/Public`
- 官方 UI：`https://emby.example.com/emby/web/index.html`（没有任何路径被篡改）

前端也可以是个后端服务，把目录换成 URL 即可：

```bash
emby-rp add -d emby.example.com -m split -p /emby -F http://127.0.0.1:8080 -y
```

### 3. 兼容姿势：后端改不了 Base URL，用 `--strip`

```bash
emby-rp add -d emby.example.com -m split -p /emby --strip -F dir:/var/www/emby-web -y
```

`/emby/*` 会被剥成 `/*` 回源。API 调用没问题，但**官方 Web UI 会半残**（它生成的绝对路径没有前缀），自己的前端请自己带前缀调接口。

### 其他常用参数

```bash
emby-rp add -d emby.example.com -e nginx -y                 # 用 nginx + certbot
emby-rp add -d emby.example.com --tls file \
  --cert /etc/ssl/fullchain.pem --key /etc/ssl/privkey.pem -y  # 已有证书
emby-rp add -d emby.example.com --tls none --http-port 8080 -y # 纯 HTTP，内网/测试
emby-rp add -d emby.example.com --upstream-insecure -y        # 后端是自签 https（会尝试自动识别）
emby-rp add -d emby.example.com --cf -y                       # 前面挂 Cloudflare，取 Cf-Connecting-IP
emby-rp add -d emby.example.com --no-log -y                   # 不写访问日志
```

---

## 命令

```
emby-rp add [...]        新建站点（无参数进向导）
emby-rp list             列出站点
emby-rp status [name]    站点详情（前缀、源站、证书到期、监听端口）
emby-rp check  [name]    自检：引擎状态 / 源站连通 / 健康探针 / 业务路径 / WebSocket / 证书
emby-rp logs   [name] [-f]  看访问日志
emby-rp render [name]    只打印渲染结果，不落盘（排错用）
emby-rp remove <name>    删除单个站点（可顺带删证书）
emby-rp uninstall        彻底卸载 + 残留自检
emby-rp menu | --help
```

`add` 全部参数见 `emby-rp --help`。环境变量：

- `EMBY_RP_YES=1` 所有确认自动为「是」
- `NO_COLOR=1` 关闭颜色
- `EMBY_RP_TAIL=<n>` `logs` 默认行数

---

## 落地物清单（卸载时按这个清）

| 路径 | 用途 |
|---|---|
| `/usr/local/bin/emby-rp` | 脚本本体 |
| `/etc/emby-rp/sites/<name>.conf` | 站点元数据 |
| `/etc/emby-rp/sites/<name>.caddy` | Caddy 站点片段 |
| `/etc/nginx/conf.d/emby-rp-<name>.conf` | Nginx 站点配置（含 `map $http_upgrade`，必须在 `http` 上下文） |
| `/etc/emby-rp/self.state` | 「哪些软件包/软件源是本工具装的」 |
| `/etc/emby-rp/backups/` | 每次改配置前的备份 |
| `/var/www/emby-rp-acme` | certbot webroot（保留在渲染结果里，`certbot renew` 才走得通） |
| `/var/log/caddy/emby-rp-<name>.log`, `/var/log/nginx/emby-rp-<name>.log` | 访问日志 |
| `/etc/caddy/Caddyfile` 里的托管块 | `import /etc/emby-rp/sites/*.caddy` |
| `/etc/apt/sources.list.d/caddy-stable.list` + keyring | 只在由本工具添加时会记录并删除 |

`uninstall` 会按需顺手删掉本工具装的包（caddy / nginx / certbot）和 Caddy 软件源，
然后 `find / -iname '*emby-rp*'` 自检一遍，把剩下的东西列给你看。

---

## 排错

**改了配置没生效？**
`emby-rp render <name>` 看渲染结果，`emby-rp check <name>` 看链路。配置落盘后都会先
`caddy validate` / `nginx -t`，引擎拒绝会自动回滚到上一版。

**Caddy 起来就挂，日志里 `permission denied`？**
caddy 以 `caddy` 用户运行，`/var/log/caddy` 必须归它所有（用 root 跑 `caddy validate`
会顺手建出 root 属主的日志文件，导致服务起不来）。本脚本已处理：`validate` 用服务用户跑，
落盘前 `chown` 日志目录。手工救：

```bash
chown -R caddy:caddy /var/log/caddy
```

**WebSocket / 播放拖条失败？**
`check` 的第 5 项会真的发一次 `Upgrade: websocket`。到 4xx 属正常（API Key 假），
到 000 就是链路没通——通常是 CDN 没放行 WebSocket。

**大文件上传 413？**
Nginx 站点已经写了 `client_max_body_size 0`；Caddy 没有这个上限。如果前面还有 CDN，去 CDN 放开。

**`certbot renew` 会失败吗？**
不会。渲染出来的 HTTP server 里一直保留 `/.well-known/acme-challenge/` → `/var/www/emby-rp-acme`。

---

## 设计上的几个选择

- **不用 `set -e`**：单条命令失败就整段退出容易留下半套配置，改成显式判错 + 回滚。
- **元数据与配置分离**：站点信息在 `sites/<name>.conf`，随时能 `render` 重建；改错了删掉重来即可。
- **一个站点一个文件**：Caddy 走 `import` 片段，Nginx 走 `conf.d`，多站点互不影响。
- **幂等**：重复 `add` 同名会拒绝，改配置用 `remove` + `add`，或直接编辑元数据后 `render` 对比。

---

## 自测（可选）

`tests/` 里的三个脚本是开发时用的，需要在 Linux 上跑（会装/卸 caddy、nginx，别在生产机上跑）：

- `render-check.sh`：source 主脚本，渲染 8 类变体（split/strip/url/自签/无 TLS/自定义端口/证书文件/无日志），交给 `caddy validate` 校验。
- `e2e-caddy.sh`：真机装 caddy → `add` → 探针 → `check` → `uninstall` → 残留核查。
- `e2e-nginx.sh`：同上，换 nginx（`tls=none`，不需要真域名）。
