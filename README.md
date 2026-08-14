# lindos 🖥️

> **[赤石科技]** 一个修复了 Linux「不能蓝屏、没有注册表、没有捆绑软件」等 Bug 的"系统"（整活项目）一键安装脚本。
>
> **我们不生产 Feature，我们只是 Feature 的搬运工。** 只不过这些 Feature，在别的系统里叫 Bug。

把散落在开源社区里的"Windows 体验移植"项目整合成一条命令，让你的 Linux 拥有 Windows 的"灵魂"——蓝屏、注册表、UAC、Windows 更新、cmd.exe、Win+R、MMC 管理控制台，甚至桌面水印。

![lindos](https://img.shields.io/badge/lindos-赤石科技-blue)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ⚠️ 警告

- **仅供虚拟机 / 测试机整活使用！** 请勿在生产环境或主力机运行。
- Linux_uac 会修改 `/etc/pam.d/sudo`；windows_update / bsod 默认会**真重启系统**（可用 `--no-reboot` / `--restore` 规避）。
- 所有项目版权归原作者所有，各组件按各自许可证（GPL-3.0 / MIT 等）分发。

## 🧩 整合组件（9 个）

| 组件 | 功能 | 技术栈 | 来源 |
|---|---|---|---|
| `regedit` | Linux 版注册表编辑器（/etc → HKLM） | C / GTK3 | [heyManNice/regedit](https://github.com/heyManNice/regedit) |
| `Linux_uac` | Linux 版 UAC 弹窗（PAM 认证） | PAM + SDL2 | [WenAnrong/Linux_uac](https://github.com/WenAnrong/Linux_uac) |
| `windows_update_in_linux` | Linux 版 Windows 更新（50/50 玄学） | C / libdrm | [WenAnrong/windows_update_in_linux](https://github.com/WenAnrong/windows_update_in_linux) |
| `aptx` | 带软件推荐的 apt 封装器 | Python | [WenAnrong/aptx](https://github.com/WenAnrong/aptx) |
| `runbox` | Linux 版 Win+R 运行框 | Rust / GTK4 | [HelloAIXIAOJI/runbox](https://github.com/HelloAIXIAOJI/runbox) |
| `cmd` | Linux 版 cmd.exe 命令行 | C89 | [ChenPi11/cmd](https://github.com/ChenPi11/cmd) |
| `bsod` | Linux 版蓝屏死机（DRM 直渲） | C / libdrm | [heyManNice/bsod](https://github.com/heyManNice/bsod) |
| `mmclinux` | 仿 Windows MMC 管理控制台 | Python / tkinter | [windowsuninstaller/mmclinux](https://gitee.com/windowsuninstaller/mmclinux) |
| `activate-linux` | 桌面"激活 Windows"水印 | PPA | [ppa:edd/misc](https://launchpad.net/~edd/+archive/ubuntu/misc) |

## 🚀 快速开始

支持 **Debian / Ubuntu**（apt 系，推荐 Ubuntu 22.04+ / Debian 12+）。

```bash
# 一键安装（全部组件，交互式菜单）
sudo ./lindos-installer.sh

# 或者直接管道安装
curl -sSL https://raw.githubusercontent.com/liwusen/lindos-installer/main/lindos-installer.sh | sudo bash -s -- --all
```

## 📖 用法

```bash
sudo ./lindos-installer.sh                          # 交互式菜单（默认全选）
sudo ./lindos-installer.sh --all                    # 全部安装（无交互）
sudo ./lindos-installer.sh --list regedit,bsod,activate-linux   # 只装指定组件
sudo ./lindos-installer.sh --uninstall              # 卸载（尽力而为）
sudo ./lindos-installer.sh --help                   # 帮助
```

### GitHub 加速镜像（国内网络必备 🇨🇳）

直连 github.com 慢/失败时使用（脚本也会自动检测并切换）：

```bash
sudo ./lindos-installer.sh --mirror                # 启用默认镜像 gh-proxy.org
LINDO_MIRROR=https://gh.llkk.cc sudo ./lindos-installer.sh --mirror   # 自定义镜像
sudo ./lindos-installer.sh --no-mirror             # 强制直连
```

镜像仅作用于 `github.com` 的克隆，gitee 的 mmclinux 不受影响。

## 🎮 体验入口

| 组件 | 命令 |
|---|---|
| regedit | `linux-regedit` |
| Linux_uac | 任意 `sudo` 命令（自动弹 UAC） |
| windows_update | `sudo windows_update_in_linux --no-reboot` |
| aptx | `sudo aptx update && sudo aptx install <包>` |
| runbox | `runbox`（Super+R 热键，Wayland 需手动绑定） |
| cmd | `cmd` |
| bsod | `sudo bsod --show "原因"` |
| mmclinux | `mmclinux` |
| activate-linux | `activate-linux` |

## 📁 项目结构

```
lindos/
├── lindos-installer.sh    # 一键安装脚本（唯一文件，自包含）
└── README.md
```

## 🛠️ 脚本特性

- **幂等**：已克隆的仓库自动跳过，直接重新编译安装
- **发行版感知**：自动识别 Debian / Ubuntu，自动启用 universe 源
- **失败兜底**：aptx 自带 install.sh 失败时降级为源码直跑
- **可卸载**：`--uninstall` 尽力还原（含 /etc/pam.d/sudo 的修改）

## 📜 许可证

- 本安装脚本：MIT License
- 各整合组件：GPL-3.0 / MIT 等（见各自仓库）

## 🙏 致谢

向以下整活项目的作者致敬——是你们让 Linux 变得更"Windows"：

- [heyManNice/regedit](https://github.com/heyManNice/regedit) · [heyManNice/bsod](https://github.com/heyManNice/bsod)
- [WenAnrong/Linux_uac](https://github.com/WenAnrong/Linux_uac) · [WenAnrong/windows_update_in_linux](https://github.com/WenAnrong/windows_update_in_linux) · [WenAnrong/aptx](https://github.com/WenAnrong/aptx)
- [HelloAIXIAOJI/runbox](https://github.com/HelloAIXIAOJI/runbox) · [ChenPi11/cmd](https://github.com/ChenPi11/cmd)
- [windowsuninstaller/mmclinux](https://gitee.com/windowsuninstaller/mmclinux)
- [activate-linux](https://launchpad.net/~edd/+archive/ubuntu/misc)（PPA 维护者 Dirk Eddelbuettel）

---

**lindos——它不完美，但它很 Windows。**
**本系统仅供娱乐，安装前请备份数据。**
