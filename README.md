# FreeSWITCH 1.10.12 + mod_fcc + mod_taering_stream 离线部署说明

### 0.55 修正版更新记录（2026-11-20）

- **停止后再次启动**：在原部署目录执行 `./start.sh`。镜像和 Compose 配置相同时，脚本会启动已有容器，保留宿主机的 XML 配置，包括 Event Socket 的监听地址和手工调整的模块加载列表。
- **首次初始化中断**：在同一目录再次执行 `./start.sh`，入口脚本会从暂存目录继续发布默认配置。请保留初始化过程中生成的隐藏目录 `conf/.freeswitch-init-v1/`。
- **旧版留下的残缺配置**：如果启动日志提示配置目录已有文件但缺少 `freeswitch.xml`，先核对 Compose 挂载的宿主机目录。路径正确时，从该部署的备份恢复缺失文件，再执行 `./start.sh`。

**已有 0.55 部署升级**：请在维护窗口操作，首次切换镜像会重建容器。先备份现有配置，将新版离线包解压到单独目录。下面示例假设新版已解压到 `/tmp/freeswitch-1.10.12-fcc1.2.1-taering0.55`。在**原部署目录**执行以下命令，沿用原有的 `conf/`、`.env`、`compose.yaml` 和数据卷。

本项目用于通过 Docker Compose 部署已经编译完成的 FreeSWITCH，不需要在目标服务器重新下载源码或执行编译。

镜像包含：

- FreeSWITCH `1.10.12-release`
- mod_fcc `1.2.1-open`
- mod_taering_stream `0.54`（商业授权模块）
- `mod_callcenter`
- MariaDB/MySQL、PostgreSQL、SQLite、ODBC 和 Redis 支持
- `mod_shout`，支持 MP3 播放及 Icecast/SHOUTcast
- `mod_sofia`、`mod_event_socket`、`mod_conference`、`mod_fifo`、`mod_distributor`、`mod_limit` 等呼叫中心常用模块
- CD 音质提示音和 MOH 等待音乐

## 1. 离线部署包

使用者只需要取得一个完整离线包：

```text
freeswitch-1.10.12-fcc1.2.1-offline-bundle.tar.gz
```

解压后目录结构如下：

```text
freeswitch-1.10.12-fcc1.2.1/
├── image/
│   └── freeswitch-1.10.12-fcc1.2.1.tar
├── compose.yaml
├── .env.example
├── README.md
├── start.sh
└── conf/
    └── README.md
```

Docker Compose 不能直接读取镜像 tar，因此需要先执行 `docker load`。包内的 `start.sh` 已将镜像导入和 Compose 启动合并成一个命令；每次执行都会重新导入包内镜像并强制重建容器，确保同名旧镜像不会被继续使用。

## 2. 目标服务器要求

### 支持的系统

本离线镜像是 **Linux x86_64/amd64** 镜像，适用于能够正常运行 Docker Engine 和 host 网络的 Linux 服务器，例如：

- Debian、Ubuntu；
- Rocky Linux、AlmaLinux、RHEL、CentOS；
- 其他主流 x86_64 Linux 发行版。

宿主机发行版不需要与镜像内的 Debian 一致，因为 FreeSWITCH 及其运行库都包含在容器镜像中。

当前包不支持 ARM64/aarch64。由于 SIP/RTP 使用 `network_mode: host`，不建议在 Windows、macOS Docker Desktop 或 WSL2 上作为生产环境运行。推荐使用原生 Linux 服务器和普通 rootful Docker Engine。

### 必须提前安装

- Docker Engine；
- Docker Compose V2 插件，命令格式为 `docker compose`；
- 用于解压交付包的 `tar` 和 `gzip`；
- 当前部署用户需要有权执行 Docker 命令，例如使用 root，或已正确加入 `docker` 用户组。

部署前检查：

```bash
uname -m
docker version
docker compose version
tar --version
```

`uname -m` 必须返回 `x86_64`。不需要提前安装 FreeSWITCH、编译器、Git、CMake、数据库客户端、声音包或任何 FreeSWITCH 开发库，也不需要访问 Docker Hub。

### CentOS Stream 9/10 安装命令

以下命令适用于 Docker 官方当前支持的 CentOS Stream 9 和 10。命令使用 `sudo`；如果已经使用 root 登录，可以删除命令前的 `sudo`。

卸载可能冲突的旧 Docker 软件包：

```bash
sudo dnf remove -y \
  docker \
  docker-client \
  docker-client-latest \
  docker-common \
  docker-latest \
  docker-latest-logrotate \
  docker-logrotate \
  docker-engine
```

如果提示软件包未安装，可以继续。安装解压、下载、校验和仓库管理工具：

```bash
sudo dnf install -y tar gzip coreutils ca-certificates curl dnf-plugins-core
```

添加 Docker 官方仓库并安装 Docker Engine、containerd 和 Compose V2：

```bash
sudo dnf config-manager --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo

sudo dnf install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

首次安装询问 GPG 密钥时，应核对指纹：

```text
060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35
```

启动 Docker 并设置开机启动：

```bash
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

CentOS Stream 默认可能启用 SELinux。不要为了运行容器永久关闭 SELinux；如果 `conf/` 出现权限拒绝，应检查目录标签和审计日志。

### Ubuntu 22.04/24.04/26.04 安装命令

以下命令适用于 Docker 官方当前支持的 Ubuntu 22.04 LTS、24.04 LTS 和 26.04 LTS。命令使用 `sudo`；如果已经使用 root 登录，可以删除命令前的 `sudo`。

卸载可能冲突的软件包：

```bash
sudo apt remove -y $(dpkg --get-selections \
  docker.io docker-compose docker-compose-v2 docker-doc docker-buildx \
  podman-docker containerd runc 2>/dev/null | cut -f1)
```

如果没有找到冲突软件包，可以继续。安装基础工具并添加 Docker 官方签名密钥：

```bash
sudo apt update
sudo apt install -y ca-certificates curl tar gzip coreutils
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

添加 Docker 官方 APT 仓库：

```bash
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

安装并启动 Docker Engine、containerd 和 Compose V2：

```bash
sudo apt update
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

### Debian 11/12/13 安装命令

以下命令适用于 Docker 官方当前支持的 Debian 11、12 和 13。命令使用 `sudo`；如果系统未安装 `sudo`，请先使用 `su -` 切换到 root，然后删除命令前的 `sudo`。

卸载可能冲突的软件包：

```bash
sudo apt remove -y $(dpkg --get-selections \
  docker.io docker-compose docker-doc docker-buildx podman-docker \
  containerd runc 2>/dev/null | cut -f1)
```

如果没有找到冲突软件包，可以继续。安装基础工具并添加 Docker 官方签名密钥：

```bash
sudo apt update
sudo apt install -y ca-certificates curl tar gzip coreutils
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

添加 Docker 官方 APT 仓库：

```bash
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

安装并启动 Docker Engine、containerd 和 Compose V2：

```bash
sudo apt update
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

以上安装命令需要目标服务器能够访问操作系统软件源和 `download.docker.com`。FreeSWITCH 离线包不包含 Docker Engine 的 RPM/DEB，因为不同发行版和版本需要不同安装包。如果目标服务器完全不能联网，应在同版本联网服务器上提前下载对应 Docker RPM/DEB 及依赖并一同传输，或者由系统管理员预装 Docker Engine 与 Compose V2。

Docker 官方安装文档：

- CentOS：<https://docs.docker.com/engine/install/centos/>
- Ubuntu：<https://docs.docker.com/engine/install/ubuntu/>
- Debian：<https://docs.docker.com/engine/install/debian/>

### Docker 命令权限

最简单的方式是使用 root 执行部署：

```bash
sudo ./start.sh
```

如果希望普通用户直接执行 `docker`，可以将该用户加入 `docker` 组：

```bash
sudo usermod -aG docker "$USER"
newgrp docker
docker version
docker compose version
```

加入 `docker` 组后通常需要退出并重新登录才能完全生效。`docker` 组具有接近 root 的系统权限，只能添加可信的服务器管理员。

### 服务器资源和端口

- 建议至少预留 2 GB 内存和 3 GB 可用磁盘空间；
- 生产规格应根据并发通话、录音和转码压力测试结果确定；
- 下列端口不能被其他程序占用。

Compose 默认不限制容器可使用的 CPU 和内存，由 Linux/Docker 根据宿主机可用资源调度。这样不会因为一个通用的固定上限影响高并发、转码、会议或录音业务。对应的 `.env` 默认值为：

```dotenv
FREESWITCH_CPUS=0.0
FREESWITCH_MEMORY_LIMIT=0
FREESWITCH_MEMORY_RESERVATION=0
```

`0` 表示不设置限制。如果客户需要在共享服务器上限制资源，可以根据压力测试结果改成例如：

```dotenv
FREESWITCH_CPUS=4.0
FREESWITCH_MEMORY_LIMIT=4g
FREESWITCH_MEMORY_RESERVATION=1g
```

三个参数的含义如下：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `FREESWITCH_CPUS` | CPU 最大配额 | `4.0` 表示最多使用相当于 4 个 CPU 核心的计算时间，但不代表独占这 4 个核心。`0.0` 表示不限制。 |
| `FREESWITCH_MEMORY_LIMIT` | 内存硬限制 | `4g` 表示容器最多使用 4 GB 内存。达到硬限制后，内存分配可能失败，容器也可能被 OOM 终止。`0` 表示不限制。 |
| `FREESWITCH_MEMORY_RESERVATION` | 内存软限制 | `1g` 表示当宿主机发生内存竞争时，Docker/Linux 会把 1 GB 作为该容器的软限制参考。它不会在启动时预先占用 1 GB，也不保证一定为容器保留 1 GB。`0` 表示不设置软限制。 |

设置原则：

- 专用 FreeSWITCH 服务器通常保持三个参数为 `0`，让 FreeSWITCH 使用宿主机可用资源；
- 多个业务共享同一台服务器时，可以根据压力测试设置限制；
- `FREESWITCH_MEMORY_RESERVATION` 应小于 `FREESWITCH_MEMORY_LIMIT`；
- 如果内存硬限制为 `4g`，软限制可以从 `1g` 或 `2g` 开始测试；
- 软限制不是资源预留或服务质量保证。如果必须保障资源，应同时做好宿主机容量规划和业务隔离；
- 限制过低可能导致音频卡顿、呼叫失败或容器被终止。

修改 `.env` 后需要重建容器才能应用资源参数，配置文件和持久化数据不会丢失：

```bash
docker compose up -d --no-build --force-recreate
```

查看实际生效值：

```bash
docker inspect freeswitch-fcc --format \
  'NanoCPUs={{.HostConfig.NanoCpus}} Memory={{.HostConfig.Memory}} MemoryReservation={{.HostConfig.MemoryReservation}}'
```

Docker 输出的内存单位是字节；三个值都为 `0` 表示没有设置对应限制。

默认使用 `network_mode: host`，容器直接使用宿主机网络：

| 用途 | 默认端口 |
| --- | --- |
| SIP internal | 5060 TCP/UDP |
| SIP external | 5080 TCP/UDP |
| Event Socket | 127.0.0.1:8021 TCP |
| FCC API | 127.0.0.1:18080 TCP |
| RTP 媒体 | 16384-32768 UDP |

Event Socket 和 FCC API 默认仅监听本机地址。防火墙只应开放业务实际需要的端口，不要直接向公网开放 8021。

Rocky Linux、AlmaLinux、RHEL、CentOS 等启用 SELinux 的系统，如果首次启动出现 `conf/` 权限拒绝，应先检查审计日志和目录标签，再为该 bind mount 配置合适的 SELinux 标签；不要直接长期关闭 SELinux。

## 3. 传输文件

可以通过 SCP、SFTP、移动硬盘或内网文件服务器传输单一离线包：

```bash
scp freeswitch-1.10.12-fcc1.2.1-offline-bundle.tar.gz root@目标服务器:/opt/
```

传输后建议在发送端和目标服务器分别执行以下命令，确认校验值一致：

```bash
sha256sum freeswitch-1.10.12-fcc1.2.1-offline-bundle.tar.gz
```

## 4. 解压并启动

在目标服务器执行：

```bash
cd /opt
tar -xzf freeswitch-1.10.12-fcc1.2.1-offline-bundle.tar.gz
cd freeswitch-1.10.12-fcc1.2.1
./start.sh
```

`start.sh` 会自动完成：

- 检查 Docker 和 Docker Compose V2；
- 首次执行 `docker load` 导入包内镜像；
- 创建 `.env` 和 `conf/`；
- 执行 `docker compose up -d --no-build`；
- 显示容器状态。

整个过程不访问 Docker Hub，也不重新编译。首次成功运行以后，可以直接在该目录使用常规 Compose 命令：

```bash
docker compose up -d --no-build
docker compose ps
```

## 5. 第一次启动与配置目录

第一次启动时，容器会把镜像中完整、版本匹配的默认配置复制到宿主机：

```text
/opt/freeswitch-1.10.12-fcc1.2.1/conf/
```

此目录通过 Compose 完整映射到：

```text
/usr/local/freeswitch/etc/freeswitch
```

以后启动不会覆盖已经存在的 `conf/freeswitch.xml`，因此所有配置修改都会保留在宿主机。

这里的 `./conf` 不是固定的 `/opt/conf`：`./` 表示 `compose.yaml` 所在目录。如果整个部署目录解压在：

```text
/opt/freeswitch-1.10.12-fcc1.2.1/
```

那么 `./conf` 对应的宿主机绝对路径就是：

```text
/opt/freeswitch-1.10.12-fcc1.2.1/conf/
```

可以把整个部署目录放在 `/opt`、`/data` 或其他位置。也可以只修改 `compose.yaml` 中挂载冒号左边的宿主机路径，例如：

```yaml
- /data/freeswitch/conf:/usr/local/freeswitch/etc/freeswitch
```

冒号右边的容器路径 `/usr/local/freeswitch/etc/freeswitch` 不应修改。更换一个空的宿主机配置目录后，容器首次启动会再次释放默认配置；如果要迁移已有配置，应先将原 `conf/` 的全部内容复制到新目录，再重建容器：

```bash
mkdir -p /data/freeswitch/conf
cp -a ./conf/. /data/freeswitch/conf/
docker compose up -d --no-build --force-recreate
```

检查启动状态：

```bash
docker compose exec -T freeswitch fs_cli -x status
docker compose exec -T freeswitch fs_cli -x 'module_exists mod_fcc'
docker compose exec -T freeswitch fs_cli -x 'module_exists mod_callcenter'
```

正常结果应显示 FreeSWITCH `1.10.12-release` 已就绪，两个模块结果均为 `true`，容器状态为 `healthy`。

## 6. 修改配置并重新加载

所有 FreeSWITCH XML 配置均在：

```text
/opt/freeswitch-1.10.12-fcc1.2.1/conf/
```

常用目录和文件：

| 配置 | 路径 |
| --- | --- |
| 全局变量 | `conf/vars.xml` |
| 模块加载 | `conf/autoload_configs/modules.conf.xml` |
| FCC | `conf/autoload_configs/mod_fcc.conf.xml` |
| Callcenter | `conf/autoload_configs/callcenter.conf.xml` |
| Event Socket | `conf/autoload_configs/event_socket.conf.xml` |
| Taering Stream | `conf/autoload_configs/mod_taering_stream.conf.xml` |
| SIP profiles | `conf/sip_profiles/` |
| 网关 | `conf/sip_profiles/external/` |
| 用户目录 | `conf/directory/` |
| 拨号计划 | `conf/dialplan/` |
| ACL | `conf/autoload_configs/acl.conf.xml` |

大多数 XML 修改完成后执行：

```bash
docker compose exec -T freeswitch fs_cli -x reloadxml
```

如果修改了 SIP profile 的监听地址、端口或 TLS 等启动参数，建议直接重启容器：

```bash
docker compose restart freeswitch
```

仅修改网关、用户、拨号计划或 callcenter 队列时，通常执行 `reloadxml` 即可；已经加载到内存中的队列、网关或 profile 配置可能还需要相应的 reload/rescan 命令。

## 7. FCC 配置说明

FCC 和其他 FreeSWITCH 模块一样，完全由宿主机 `conf/` 中的 XML 管理：

```text
conf/autoload_configs/mod_fcc.conf.xml
```

第一次启动生成完整配置后，打开该文件，将默认 token：

```xml
<param name="api_token" value="change-me"/>
```

修改成客户自己的高强度随机值，同时检查监听地址、端口、并发数、CPS、默认用户域和默认网关等参数。容器入口脚本不会修改或覆盖任何 FCC XML 参数。

修改完成后执行：

```bash
docker compose exec -T freeswitch fs_cli -x reloadxml
docker compose exec -T freeswitch fs_cli -x 'reload mod_fcc'
```

如果模块正在处理业务，建议安排维护窗口；也可以直接重启容器确保全部 FCC 配置重新加载：

```bash
docker compose restart freeswitch
```

在修改默认 token 前，不要将 FCC API 暴露到公网。如果把监听地址改为 `0.0.0.0`，必须使用防火墙和可信 TLS 反向代理保护 FCC API。

## 8. 数据持久化

以下内容使用 Docker named volume 保存：

- FreeSWITCH 数据库
- 日志
- 录音

查看实际 volume：

```bash
docker volume ls | grep freeswitch-fcc
```

停止并删除容器不会删除这些数据：

```bash
docker compose down
```

不要在生产环境随意执行下面的命令，它会删除数据库、日志和录音 volume：

```bash
docker compose down -v
```

部署备份至少应包含：

- 整个部署目录下的 `conf/`
- `.env`
- FreeSWITCH 数据库 volume
- 需要保留的录音 volume

## 9. 常用运维命令

查看状态：

```bash
docker compose ps
docker compose exec -T freeswitch fs_cli -x status
```

进入 FreeSWITCH CLI：

```bash
docker compose exec freeswitch fs_cli
```

实时查看日志：

```bash
docker compose logs -f --tail=200 freeswitch
```

查看 SIP profile：

```bash
docker compose exec -T freeswitch fs_cli -x 'sofia status'
```

查看模块：

```bash
docker compose exec -T freeswitch fs_cli -x 'show modules'
```

查看 Taering Stream 模块与授权状态：

```bash
docker compose exec -T freeswitch fs_cli -x 'module_exists mod_taering_stream'
docker compose exec -T freeswitch fs_cli -x 'taering_stream stats'
docker compose exec -T freeswitch fs_cli -x 'taering_stream license'
```

模块首次启动会联网检查商业授权。Compose 将宿主机 `/etc/machine-id` 只读挂载到容器，模块仅使用其 SHA-256 作为稳定宿主机标识。installation ID 和授权缓存保存在持久化的 `conf/autoload_configs/` 中，重建容器不会丢失。首次部署显示 `pending` 时，表示模块已经正确安装并进入待授权状态；后台授权后会自动轮询生效。

重启：

```bash
docker compose restart freeswitch
```

停止和启动：

```bash
docker compose stop freeswitch
docker compose start freeswitch
```

## 10. 正式上线前必须检查

默认 FreeSWITCH 示例配置只适合初始化和测试，正式上线前至少完成以下修改：

1. 修改 `conf/vars.xml` 中的默认用户密码。
2. 修改 Event Socket 密码并限制 ACL，禁止公网访问 8021。
3. 根据实际公网/内网环境设置 SIP IP、NAT 和 RTP 参数。
4. 删除或禁用不需要的示例用户、示例网关和示例拨号计划。
5. 配置实际的呼叫中心队列、坐席和 tier。
6. 配置实际网关、号码规则和呼入路由。
7. 限制 FCC API 的访问来源并妥善保存 token。
8. 配置日志、录音、数据库和配置目录的定期备份。
9. 设置宿主机防火墙，并确认 RTP 端口范围与运营商一致。
10. 完成呼入、呼出、转接、排队、录音、MOH、DTMF 和异常恢复测试。

## 11. 故障排查

### 容器不是 healthy

```bash
docker compose ps
docker compose logs --tail=300 freeswitch
docker compose exec -T freeswitch fs_cli -x status
```

重点检查端口冲突、XML 语法、FCC token、目录权限和数据库连接配置。

`start.sh` 每次都会重新导入离线包内的镜像并强制重建容器，避免宿主机已有的同名旧镜像被继续使用。启动时还会对旧默认配置执行两项幂等迁移：将 Event Socket 的 `listen-ip="::"` 改为 `127.0.0.1`，并在缺失时补充 `mod_taering_stream` 配置与模块加载项。用户明确设置的其他监听地址和已有模块配置不会被覆盖。

### 修改 XML 后没有生效

先检查 XML 文件，再执行：

```bash
docker compose exec -T freeswitch fs_cli -x reloadxml
```

如果修改的是 SIP 监听、TLS 或模块启动配置，重启容器：

```bash
docker compose restart freeswitch
```

### 配置目录为空

确认当前目录中不存在一个不完整的 `conf/freeswitch.xml`，然后重新启动。只有缺少 `conf/freeswitch.xml` 时，入口脚本才会从镜像初始化默认配置。

### 端口被占用

由于使用 host 网络模式，需要在宿主机检查端口：

```bash
ss -lntup | grep -E ':(5060|5080|8021|18080)\\b'
```

## 12. 镜像升级或增加自定义模块

以后收到新镜像包时：

1. 先备份 `conf/`、数据库和录音。
2. 执行 `docker load -i 新镜像.tar`。
3. 修改 `.env` 中的 `FREESWITCH_IMAGE` 为新标签。
4. 执行 `docker compose up -d --no-build --force-recreate`。
5. 验证版本、模块、SIP profile、FCC 和实际通话。

镜像升级不会自动覆盖宿主机已有的 `conf/`。如果新模块需要新的 XML 配置，应从新镜像的默认配置中单独取出并合并，不能直接覆盖生产配置。
