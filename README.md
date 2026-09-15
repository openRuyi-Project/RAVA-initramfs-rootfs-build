# RAVA-initramfs-rootfs-build

接收 [guix-kernel-cross-build](https://github.com/openRuyi-Project/guix-kernel-cross-build)
的内核构建产物目录,制作 **initramfs**,并把制作 initramfs 的 **chroot 环境打包成
rootfs**。

上游输入(guix-kernel-cross-build 的 `/srv/guix_result/<commit>/`):

```
Image           # riscv64 内核镜像
vmlinux         # 带 debug 信息的 ELF
lib/modules/    # 内核模块(lib/modules/<kver>/)
lib/dtb/        # 设备树(保留 vendor 子目录)
<kver>.tgz      # 模块压缩包
```

本仓库产出:

```
/srv/initramfs_result/<commit>/<profile>/initramfs.img       # initramfs
/srv/initramfs_result/<commit>/<profile>/<profile>-rootfs.img.zst
/srv/initramfs_result/<commit>/<profile>/<profile>-rootfs.tar.gz
```

## 镜像

通过 GitHub Actions 流水线(`.github/workflows/docker-image.yml`)构建并推送到
`hub.oepkgs.net/rvci/RAVA-initramfs-rootfs-build`,由推送的 tag 触发:

| 推送的 tag | 发布的镜像 tag |
|---|---|
| `v*` | `openeuler-<tag>` + `openeuler-release`;`openruyi-<tag>` + `openruyi-release` |
| `dev-v*` | `openeuler-<tag>` + `openeuler-dev`;`openruyi-<tag>` + `openruyi-dev` |

base image 由 matrix 决定:

| variant | base image |
|---|---|
| `openeuler` | `openeuler/openeuler:24.03-lts-sp3` |
| `openruyi` | `git.openruyi.cn/openruyi/creek-x86-64:latest` |

注意:**流水线不会产出 `latest` tag**,拉取时请使用具体版本 tag 或
`<variant>-release` / `<variant>-dev`。

## 用法

```bash
initramfs-rootfs-build <内核构建产物目录> [选项] [profile ...]
```

| 参数 | 说明 |
|---|---|
| `<内核构建产物目录>` | guix-kernel-cross-build 的构建产物目录,须含 `Image` 和 `lib/modules/<kver>`(有且只有一个内核版本) |
| `openeuler` | openEuler 24.03 LTS SP3 的 rva20 + rva23 两个 profile |
| `openruyi` | openruyi 的 rva20 + rva23 两个 profile |
| `all` | 全部 4 个 profile(**缺省值**) |
| 具体 profile | `openEuler-24.03-LTS-SP3-RVA20` / `openEuler-24.03-LTS-SP3-RVA23` / `openruyi-rva20` / `openruyi-rva23` |

选项和具体 profile 可混用、可多个,自动去重;不支持的 profile 会报错退出。

## 运行

容器需 `--privileged`(bind 挂载 `/dev` `/proc` `/sys`、loop 挂载制作 ext4 镜像),
且宿主机需注册 riscv64 的 `binfmt_misc`(chroot 内执行目标架构程序):

```bash
# 注册 qemu-riscv64(宿主机上执行一次)
docker run --privileged --rm tonistiigi/binfmt --install riscv64

# 运行构建
docker run --privileged --rm \
    -v /srv/guix_result:/srv/guix_result \
    -v /srv/initramfs_result:/srv/initramfs_result \
    hub.oepkgs.net/rvci/RAVA-initramfs-rootfs-build:openeuler-dev \
    initramfs-rootfs-build /srv/guix_result/<commit> all

# 也可以进容器交互执行
docker run -ti --privileged \
    -v /srv/guix_result:/srv/guix_result \
    -v /srv/initramfs_result:/srv/initramfs_result \
    hub.oepkgs.net/rvci/RAVA-initramfs-rootfs-build:openruyi-dev bash
initramfs-rootfs-build /srv/guix_result/<commit> openeuler > build.log 2>&1

# 只构建单个 profile
initramfs-rootfs-build /srv/guix_result/<commit> openruyi-rva23
```

## 流程

对每个 profile 执行:

1. **安装目标系统**:在输出目录下的 `rootfs/` 工作目录里,用
   `dnf --forcearch riscv64 --installroot` 安装对应发行版
   (openEuler: `minimal-environment` 环境组;openruyi: `openruyi-minimal` 包),
   附加 `dracut`、`dracut-network`、`nfs-utils`/`nfs-client`、
   `systemd-timesyncd` 等;openruyi 另做 `libudev-zero` → `systemd-udev` 替换
2. **生成 initramfs**:把内核模块 `rsync` 进 chroot 的 `lib/modules/<kver>`,
   chroot 内 `depmod` 后用 `dracut --no-hostonly --add " nfs network base "` 生成
   (openEuler rva23 附加 `--add-drivers k1-emac` 网卡驱动)
3. **配置并清理 rootfs**:配置 `fstab`、`hostname`、root 密码、sshd、
   `resolv.conf`、timesyncd NTP(openruyi 另有 systemd-resolve
   用户 + NetworkManager 自启),然后清理 dnf 缓存、卸载挂载
4. **打包 rootfs**:ext4 镜像(rootfs 大小 + 5120MB 预留)zstd 压缩为
   `img.zst`,目录打包为 `tar.gz`,均生成 md5sum 校验文件
5. **清理** rootfs 工作目录,只保留打包产物

失败即退出,EXIT trap 兜底 umount 当前 chroot 的挂载、清理临时镜像文件。

## profile 与软件源

| profile | 软件源 |
|---|---|
| `openEuler-24.03-LTS-SP3-RVA20` | `https://fast-mirror.isrc.ac.cn/openeuler/openEuler-24.03-LTS-SP3/everything/riscv64/rva20/riscv64/` |
| `openEuler-24.03-LTS-SP3-RVA23` | `https://fast-mirror.isrc.ac.cn/openeuler/openEuler-24.03-LTS-SP3/everything/riscv64/rva23/riscv64/` |
| `openruyi-rva20` | `https://boat.openruyi.cn/unstable/rva20` |
| `openruyi-rva23` | `https://boat.openruyi.cn/unstable/rva23` |

## 构建产物

构建完毕后产物存放在 `/srv/initramfs_result/<commit>/<profile>/` 下:

```
initramfs.img                      # initramfs(dracut 生成)
initramfs.img.md5sum               # initramfs.img 的 md5 校验
<profile>-rootfs.img.zst           # ext4 镜像 zstd 压缩(rootfs 大小 + 5GB 预留)
<profile>-rootfs.img.zst.md5sum    # img.zst 的 md5 校验
<profile>-rootfs.tar.gz            # rootfs 目录 tar.gz 压缩包
<profile>-rootfs.tar.gz.md5sum     # tar.gz 的 md5 校验
```

rootfs 由制作 initramfs 的 chroot 环境打包而来,**内含配套的内核模块**
(`lib/modules/<kver>`),与传入的内核构建产物配套使用。
