#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

image_name=local/freeswitch:1.10.12-fcc1.2.1
image_archive=image/freeswitch-1.10.12-fcc1.2.1.tar

[ "$(uname -s)" = Linux ] || {
    echo "错误：本离线包仅支持原生 Linux 服务器。" >&2
    exit 1
}
[ "$(uname -m)" = x86_64 ] || {
    echo "错误：本镜像仅支持 x86_64/amd64，当前架构为 $(uname -m)。" >&2
    exit 1
}

command -v docker >/dev/null 2>&1 || {
    echo "错误：没有找到 docker，请先安装 Docker Engine。" >&2
    exit 1
}
docker compose version >/dev/null 2>&1 || {
    echo "错误：没有找到 Docker Compose V2。" >&2
    exit 1
}

if [ ! -f "$image_archive" ]; then
    echo "错误：找不到离线镜像文件 $image_archive" >&2
    exit 1
fi

# The delivery tag is intentionally stable. Always load the bundled archive
# so an older local image with the same tag cannot silently win.
echo "正在导入离线包内的镜像，请稍候……"
docker load -i "$image_archive"

expected_taering_version=0.54
actual_taering_version=$(docker image inspect "$image_name" \
    --format '{{index .Config.Labels "io.taering365.mod-taering-stream.version"}}')
if [ "$actual_taering_version" != "$expected_taering_version" ]; then
    echo "错误：导入后的商业模块版本为 $actual_taering_version，期望 $expected_taering_version。" >&2
    exit 1
fi
echo "镜像校验完成：mod_taering_stream $actual_taering_version"

if [ ! -f .env ]; then
    cp .env.example .env
    echo "已从 .env.example 创建 .env。"
fi

mkdir -p conf
# A shell environment variable takes precedence over a stale FREESWITCH_IMAGE
# value in an existing .env. Force recreation so the running container adopts
# the newly imported image rather than continuing to use its previous image ID.
FREESWITCH_IMAGE="$image_name" docker compose up -d --no-build --force-recreate
docker compose ps

echo
echo "启动命令执行完成。首次启动会在 ./conf 中释放完整配置。"
echo "修改 XML 后执行：docker compose exec -T freeswitch fs_cli -x reloadxml"
