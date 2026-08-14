#!/usr/bin/env bash
# =============================================================================
#  lindos-installer.sh
#
#  [赤石科技] lindos —— 一个修复了 Linux 不能蓝屏、没有注册表、
#  没有捆绑软件等 Bug 的"系统"（整活项目）一键安装脚本。
#
#  Slogan: 我们不生产 Feature，我们只是 Feature 的搬运工。
#          只不过这些 Feature，在别的系统里叫 Bug。
#
#  整合组件（9 个）:
#    regedit                  Linux 版注册表编辑器        (C/GTK3, meson)
#    Linux_uac                Linux 版 UAC 弹窗           (PAM+SDL2, 自带 install.sh)
#    windows_update_in_linux  Linux 版 Windows 更新       (C/libdrm, cmake)
#    aptx                     带软件推荐的 apt 封装器      (Python, 自带 install.sh)
#    runbox                   Linux 版 Win+R 运行框       (Rust/GTK4, cargo)
#    cmd                      Linux 版 cmd.exe 命令行     (C89, make)
#    bsod                     Linux 版蓝屏死机           (C/libdrm, meson)
#    mmclinux                 仿 Windows MMC 管理控制台   (Python/tkinter)
#    activate-linux           桌面"激活 Windows"水印      (PPA ppa:edd/misc)
#
#  用法:
#    sudo ./lindos-installer.sh                交互式菜单（默认全选）
#    sudo ./lindos-installer.sh --all          全部安装（无交互）
#    sudo ./lindos-installer.sh --list regedit,bsod,activate-linux
#                                              只安装指定组件
#    sudo ./lindos-installer.sh --uninstall    卸载（尽力而为）
#    sudo ./lindos-installer.sh --help         帮助
#
#  GitHub 加速镜像开关（国内网络访问 github.com 慢/失败时使用）:
#    sudo ./lindos-installer.sh --mirror       启用默认镜像 gh-proxy.org
#    sudo ./lindos-installer.sh --no-mirror    强制直连（默认）
#    自定义镜像：LINDO_MIRROR=https://gh.llkk.cc sudo ./lindos-installer.sh --mirror
#    不指定时自动检测：直连 GitHub 失败会自动启用默认镜像并提示
#
#  警告：本脚本仅供虚拟机 / 测试机整活使用，请勿在生产环境或主力机运行。
#  所有项目版权归原作者所有，各组件按各自许可证（GPL-3.0 / MIT 等）分发。
# =============================================================================

set -euo pipefail

# ----------------------------- 全局配置 -------------------------------------
LINDO_ROOT="${LINDO_ROOT:-/opt/lindos}"
SRC_DIR="${LINDO_ROOT}/src"
BIN_DIR="/usr/local/bin"
PKG_DIR="${LINDO_ROOT}/packages"

MODE="menu"          # menu | all | list | uninstall
SELECTED=""          # --list 指定的组件（逗号分隔）
RUN_NONINTERACTIVE=0

# GitHub 加速镜像（前缀式代理，如 https://gh-proxy.org）
# 优先级：--mirror 显式开启 > LINDO_MIRROR 自定义 > 自动检测
DEFAULT_MIRROR="https://gh-proxy.org"
MIRROR_BASE=""       # 空 = 直连

# ----------------------------- 组件定义 -------------------------------------
# 每个组件: 名称|说明|类型|来源
# 类型: apt=自带安装脚本, meson, cmake, cargo, make, python, ppa
declare -A COMPONENTS=(
  [regedit]="Linux 版注册表编辑器|meson|https://github.com/heyManNice/regedit.git"
  [linux_uac]="Linux 版 UAC 弹窗|apt|https://github.com/WenAnrong/Linux_uac.git"
  [windows_update]="Linux 版 Windows 更新|cmake|https://github.com/WenAnrong/windows_update_in_linux.git"
  [aptx]="带软件推荐的 apt 封装器|apt|https://github.com/WenAnrong/aptx.git"
  [runbox]="Linux 版 Win+R 运行框|cargo|https://github.com/HelloAIXIAOJI/runbox.git"
  [cmd]="Linux 版 cmd.exe 命令行|make|https://github.com/ChenPi11/cmd.git"
  [bsod]="Linux 版蓝屏死机|meson|https://github.com/heyManNice/bsod.git"
  [mmclinux]="仿 Windows MMC 管理控制台|python|https://gitee.com/windowsuninstaller/mmclinux.git"
  [activate_linux]="桌面激活 Windows 水印|ppa|ppa:edd/misc"
)

ALL_COMPONENTS="regedit linux_uac windows_update aptx runbox cmd bsod mmclinux activate_linux"

# ----------------------------- 工具函数 -------------------------------------
log()  { printf '\033[1;34m[lindos]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[  OK  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ WARN ]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[FAILED]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "请用 root 运行：sudo $0 $*"
}

distro_id() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-linux}"
  else
    echo "linux"
  fi
}

# 检测是否为 Debian/Ubuntu 系（apt 系）
is_apt_distro() {
  local id
  id="$(distro_id)"
  case "$id" in
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian) return 0 ;;
    *) return 1 ;;
  esac
}

# 检测能否直连 GitHub（有 curl/wget 才检测；都没有则假定可达）
check_github_reachability() {
  if command -v curl >/dev/null 2>&1; then
    curl -sI --connect-timeout 5 --max-time 8 https://github.com -o /dev/null && return 0
    return 1
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q --spider --timeout=8 https://github.com && return 0
    return 1
  fi
  return 0
}

# 应用镜像：仅对 github.com 前缀的 URL 做前缀式加速
apply_mirror() {
  local url="$1"
  if [ -n "$MIRROR_BASE" ] && [ "${url#https://github.com/}" != "$url" ]; then
    echo "${MIRROR_BASE}/${url}"
  else
    echo "$url"
  fi
}

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ----------------------------- 依赖安装 -------------------------------------
install_deps() {
  if ! is_apt_distro; then
    warn "当前发行版 $(distro_id) 非 apt 系：PPA 与 aptx 组件将跳过，其余组件尝试直接编译。"
    return 0
  fi

  log "安装编译依赖（apt）……"
  # 先确保 add-apt-repository 可用（启用 universe 源需要它）
  DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common || true

  # Ubuntu 需要 universe 源：debtags(aptx) 与 python3-tk(mmclinux) 都在 universe 里
  if [ "$(distro_id)" = "ubuntu" ]; then
    log "启用 universe 软件源"
    add-apt-repository -y universe >/dev/null 2>&1 \
      || warn "universe 源启用失败，aptx/mmclinux 可能装不上"
  fi

  local pkgs=(
    git curl ca-certificates wget
    build-essential pkg-config
    meson ninja-build cmake
    # regedit
    libgtk-3-dev libjson-glib-dev
    # bsod / windows_update_in_linux
    libdrm-dev libfreetype-dev libfontconfig1-dev libsystemd-dev
    # runbox
    cargo libgtk-4-dev libadwaita-1-dev
    # mmclinux（python3-tk 在 Ubuntu universe 源）
    python3 python3-tk
  )
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  ok "依赖安装完成"
}

clone_repo() {
  local url="$1" dir="$2" fetch_url
  fetch_url="$(apply_mirror "$url")"
  if [ -d "${dir}/.git" ]; then
    log "更新仓库 $dir"
    git -C "$dir" pull --ff-only -q || warn "git pull 失败，沿用现有代码"
  else
    log "克隆 $fetch_url"
    mkdir -p "$(dirname "$dir")"
    git clone --depth 1 "$fetch_url" "$dir"
  fi
}

# ----------------------------- 各组件安装 -----------------------------------
install_regedit() {
  local d="${SRC_DIR}/regedit"
  clone_repo "https://github.com/heyManNice/regedit.git" "$d"
  cd "$d"
  meson setup builddir >/dev/null
  meson compile -C builddir
  install -Dm755 builddir/linux-regedit "${BIN_DIR}/linux-regedit"
  ok "regedit -> ${BIN_DIR}/linux-regedit"
}

install_linux_uac() {
  local d="${SRC_DIR}/Linux_uac" moddir
  clone_repo "https://github.com/WenAnrong/Linux_uac.git" "$d"
  cd "$d"
  # 自带 install.sh：识别发行版、装依赖、编译、写入 /etc/pam.d/sudo
  if [ -x ./install.sh ]; then
    ./install.sh
  else
    warn "Linux_uac 缺少 install.sh，尝试手动编译"
    make
    moddir="$(pkg-config --variable=moduledir pam 2>/dev/null || true)"
    [ -n "$moddir" ] && install -Dm755 pam_uac.so "${moddir}/pam_uac.so" \
      || warn "无法定位 PAM 模块目录，请手动安装 pam_uac.so"
    install -Dm755 uac_ui /usr/local/libexec/linux-uac/uac_ui
    grep -q 'pam_uac.so' /etc/pam.d/sudo 2>/dev/null || \
      sed -i '1i auth sufficient pam_uac.so' /etc/pam.d/sudo
  fi
  ok "Linux_uac 已安装（UAC 弹窗已挂载到 sudo）"
}

install_windows_update() {
  local d="${SRC_DIR}/windows_update_in_linux"
  clone_repo "https://github.com/WenAnrong/windows_update_in_linux.git" "$d"
  cd "$d"
  cmake -B build >/dev/null
  cmake --build build
  install -Dm755 ./windows_update_in_linux "${BIN_DIR}/windows_update_in_linux"
  ok "windows_update_in_linux -> ${BIN_DIR}/windows_update_in_linux"
}

install_aptx() {
  local d="${SRC_DIR}/aptx"
  clone_repo "https://github.com/WenAnrong/aptx.git" "$d"
  cd "$d"
  if [ -x ./install.sh ] && ./install.sh; then
    :
  elif [ -x ./aptx ]; then
    # 兜底：aptx 自带 install.sh 失败（如 debtags 不可用）时源码直跑
    warn "aptx 自带 install.sh 未成功，改用源码直跑（推荐精度降级，无 debtags）"
    cat > "${BIN_DIR}/aptx" <<EOF
#!/usr/bin/env bash
cd "${d}" && exec python3 ./aptx "\$@"
EOF
    chmod +x "${BIN_DIR}/aptx"
    mkdir -p /var/lib/aptx
  else
    warn "aptx 仓库不完整，跳过"
    return 0
  fi
  ok "aptx 已安装（首次使用请先执行：sudo aptx update）"
}

install_runbox() {
  local d="${SRC_DIR}/runbox"
  clone_repo "https://github.com/HelloAIXIAOJI/runbox.git" "$d"
  cd "$d"
  cargo build --release
  install -Dm755 target/release/runbox "${BIN_DIR}/runbox"
  ok "runbox -> ${BIN_DIR}/runbox"
}

install_cmd() {
  local d="${SRC_DIR}/cmd"
  clone_repo "https://github.com/ChenPi11/cmd.git" "$d"
  cd "$d"
  make -j"$(nproc)"
  make install PREFIX=/usr/local || {
    # 兜底：直接拷贝产物
    install -Dm755 ./cmd "${BIN_DIR}/cmd" 2>/dev/null || true
  }
  ok "cmd 已安装（终端输入 cmd 体验）"
}

install_bsod() {
  local d="${SRC_DIR}/bsod"
  clone_repo "https://github.com/heyManNice/bsod.git" "$d"
  cd "$d"
  meson setup build >/dev/null
  meson compile -C build
  install -Dm755 build/bsod "${BIN_DIR}/bsod"
  ok "bsod -> ${BIN_DIR}/bsod（sudo bsod --show \"原因\" 触发蓝屏）"
}

install_mmclinux() {
  local d="${SRC_DIR}/mmclinux"
  clone_repo "https://gitee.com/windowsuninstaller/mmclinux.git" "$d"
  if ! command -v python3 >/dev/null; then
    warn "缺少 python3，跳过 mmclinux"
    return 0
  fi
  # 写入启动器（mmclinux 是 tkinter 程序，直接跑 main.py）
  cat > "${BIN_DIR}/mmclinux" <<EOF
#!/usr/bin/env bash
exec python3 "${d}/main.py" "\$@"
EOF
  chmod +x "${BIN_DIR}/mmclinux"
  ok "mmclinux -> ${BIN_DIR}/mmclinux（终端输入 mmclinux 启动）"
}

install_activate_linux() {
  if ! is_apt_distro; then
    warn "activate-linux 仅提供 apt PPA，跳过"
    return 0
  fi
  log "添加 PPA ppa:edd/misc 并安装 activate-linux"
  DEBIAN_FRONTEND=noninteractive add-apt-repository -y ppa:edd/misc
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y activate-linux
  ok "activate-linux 已安装（终端输入 activate-linux 显示水印）"
}

install_one() {
  local name="$1"
  case "$name" in
    regedit)          install_regedit ;;
    linux_uac)        install_linux_uac ;;
    windows_update)   install_windows_update ;;
    aptx)             install_aptx ;;
    runbox)           install_runbox ;;
    cmd)              install_cmd ;;
    bsod)             install_bsod ;;
    mmclinux)         install_mmclinux ;;
    activate_linux)   install_activate_linux ;;
    *) warn "未知组件：$name，跳过" ;;
  esac
}

# ----------------------------- 卸载 -----------------------------------------
uninstall_one() {
  local name="$1" d moddir
  log "卸载 $name"
  case "$name" in
    regedit)          rm -f "${BIN_DIR}/linux-regedit" ;;
    linux_uac)
      d="${SRC_DIR}/Linux_uac"
      [ -x "${d}/install.sh" ] && ( cd "$d" && ./install.sh --uninstall ) || true
      rm -f /usr/local/libexec/linux-uac/uac_ui
      moddir="$(pkg-config --variable=moduledir pam 2>/dev/null || true)"
      [ -n "$moddir" ] && rm -f "${moddir}/pam_uac.so"
      ;;
    windows_update)   rm -f "${BIN_DIR}/windows_update_in_linux" ;;
    aptx)
      local d="${SRC_DIR}/aptx"
      [ -x "${d}/uninstall.sh" ] && ( cd "$d" && ./uninstall.sh ) || rm -f "${BIN_DIR}/aptx"
      ;;
    runbox)           rm -f "${BIN_DIR}/runbox" ;;
    cmd)              rm -f "${BIN_DIR}/cmd" ;;
    bsod)             rm -f "${BIN_DIR}/bsod" ;;
    mmclinux)         rm -f "${BIN_DIR}/mmclinux" ;;
    activate_linux)
      if is_apt_distro; then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y activate-linux || true
      fi
      ;;
  esac
  ok "已移除 $name"
}

do_uninstall() {
  need_root
  for name in $ALL_COMPONENTS; do
    uninstall_one "$name"
  done
  log "源码目录保留在 ${SRC_DIR}，如需彻底删除：rm -rf ${LINDO_ROOT}"
  ok "卸载完成（部分组件自带卸载脚本，可能提示额外的清理项）"
}

# ----------------------------- 交互菜单 -------------------------------------
ask_menu() {
  local i=0 ans n idx name
  for name in $ALL_COMPONENTS; do
    i=$((i+1))
    printf '%2d) %-16s %s\n' "$i" "$name" "${COMPONENTS[$name]%%|*}"
  done
  printf '    %-16s %s\n' "ALL" "全部安装"
  printf '\n请输入组件编号（逗号分隔，如 1,3,9；回车=全部安装）: '
  # 管道安装（curl | bash）时 /dev/tty 不可用，read 失败则默认全部安装
  if ! read -r ans < /dev/tty; then ans=""; fi
  if [ -z "$ans" ]; then
    SELECTED="$ALL_COMPONENTS"
    return
  fi
  SELECTED=""
  # 逗号转空格，用默认 IFS 拆分
  ans="$(echo "$ans" | tr ',' ' ')"
  for n in $ans; do
    n="$(echo "$n" | tr -d '[:space:]')"
    case "$n" in
      all|ALL) SELECTED="$ALL_COMPONENTS"; return ;;
      [0-9]*)
        idx=0
        for name in $ALL_COMPONENTS; do
          idx=$((idx+1))
          [ "$idx" -eq "$n" ] && SELECTED="${SELECTED} ${name}"
        done
        ;;
    esac
  done
  SELECTED="$(echo "$SELECTED" | xargs)"
  [ -n "$SELECTED" ] || SELECTED="$ALL_COMPONENTS"
}

# ----------------------------- 主流程 ---------------------------------------
main() {
  local mirror_flag=""   # "on"=显式开启, "off"=显式关闭
  while [ $# -gt 0 ]; do
    case "$1" in
      --all)        MODE="all" ;;
      --list)       MODE="list"; shift; SELECTED="${1:-}" ;;
      --uninstall)  MODE="uninstall" ;;
      --mirror)     mirror_flag="on" ;;
      --no-mirror)  mirror_flag="off" ;;
      --help|-h)    usage ;;
      *) die "未知参数：$1（--help 查看用法）" ;;
    esac
    shift
  done

  case "$MODE" in
    uninstall) do_uninstall; exit 0 ;;
  esac

  need_root

  log "欢迎使用 lindos 一键安装脚本"
  warn "仅供虚拟机/测试机整活使用！不要在生产环境或主力机运行。"
  warn "Linux_uac 会修改 /etc/pam.d/sudo；windows_update/bsod 默认会真重启系统（可用 --no-reboot / --restore 规避）。"
  echo

  install_deps

  # GitHub 加速镜像判定
  case "$mirror_flag" in
    on)
      MIRROR_BASE="${LINDO_MIRROR:-$DEFAULT_MIRROR}"
      log "已启用 GitHub 加速镜像：${MIRROR_BASE}"
      ;;
    off)
      MIRROR_BASE=""
      log "强制直连 GitHub（不使用镜像）"
      ;;
    *)
      if [ -n "${LINDO_MIRROR:-}" ]; then
        MIRROR_BASE="$LINDO_MIRROR"
        log "检测到 LINDO_MIRROR，使用自定义镜像：${MIRROR_BASE}"
      elif ! check_github_reachability; then
        MIRROR_BASE="${DEFAULT_MIRROR}"
        warn "直连 GitHub 不可达，自动启用加速镜像：${MIRROR_BASE}"
        warn "如需强制直连请加 --no-mirror；如需其他镜像请设置 LINDO_MIRROR=https://xxx"
      else
        MIRROR_BASE=""
        ok "可直连 GitHub，使用官方源克隆"
      fi
      ;;
  esac

  case "$MODE" in
    all)  SELECTED="$ALL_COMPONENTS" ;;
    list)
      # 把逗号分隔转成空格
      SELECTED="$(echo "$SELECTED" | tr ',' ' ')"
      ;;
    menu) ask_menu ;;
  esac

  mkdir -p "${SRC_DIR}"
  log "安装组件：$(echo "$SELECTED" | xargs)"
  for name in $SELECTED; do
    install_one "$name"
  done

  echo
  log "安装完成！体验入口："
  for name in $SELECTED; do
    case "$name" in
      regedit)         echo "  - linux-regedit                    # 注册表编辑器" ;;
      linux_uac)       echo "  - 任意 sudo 命令                     # UAC 弹窗" ;;
      windows_update)  echo "  - sudo windows_update_in_linux --no-reboot   # 伪更新" ;;
      aptx)            echo "  - sudo aptx update && sudo aptx install <包>" ;;
      runbox)          echo "  - runbox（Super+R 热键，Wayland 需手动绑定）" ;;
      cmd)             echo "  - cmd                               # cmd.exe" ;;
      bsod)            echo "  - sudo bsod --show \"原因\"          # 蓝屏" ;;
      mmclinux)        echo "  - mmclinux                          # MMC 控制台" ;;
      activate_linux)  echo "  - activate-linux                    # 桌面水印" ;;
    esac
  done
  warn "再次提醒：整活有风险，玩机需谨慎。请重启电脑以体验蓝屏（doge）。"
}

main "$@"
