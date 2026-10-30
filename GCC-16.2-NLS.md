# GCC 16.2 原生 Windows 工具链构建说明（mingw-builds）

> 个人备份仓库（`tjzjzx/mingw-builds-gcc16.2-nls`）：在 upstream
> `niXman/mingw-builds@dac115a` 之上叠加了 NLS（libintl）+ iconv 的改动，
> 仅作自用备份，不向上游提交 PR。
> 预编译工具链见 [Releases](https://github.com/tjzjzx/mingw-builds-gcc16.2-nls/releases)。

## 环境

| 项         | 值                                                           |
| ---------- | ------------------------------------------------------------ |
| 构建环境   | Windows 侧 MSYS2（便携 tar.xz 安装）                         |
| MSYS2 路径 | `E:\msys64`                                                  |
| 构建根目录 | `E:\buildroot`（MSYS 内为 `/e/buildroot`）                   |
| 源码仓库   | https://github.com/niXman/mingw-builds.git @ `dac115a`       |
| 依赖       | `lndir git subversion tar zip p7zip make patch automake-wrapper autoconf autoconf-archive libtool flex bison gettext gettext-devel wget sshpass texinfo autogen dejagnu pkgconf` |

## 使用的配置

```
./build --mode=gcc-16.2.0 \
        --buildroot=/e/buildroot \
        --arch=x86_64 \
        --threads=posix \
        --exceptions=seh \
        --with-default-msvcrt=ucrt \
        --rt-version=v14 \
        --rev=0 \
        --jobs=32 \
        --enable-languages=c,c++,fortran \
        --bin-compress \
        --no-bootstrap \
        --gnu-url-prefix=https://mirrors.tuna.tsinghua.edu.cn/gnu \
        --logviewer-command=cat \
        --no-colors
```

依据 `.github/workflows/build_cmake.yml`（上游 CI 推荐配置）

## 为 iconv + NLS 做的改动

1. `scripts/gettext.sh`（新增）：构建 GNU gettext 0.26 的 `gettext-runtime`，
   安装到**独立前缀** `$PREREQ_DIR/$PKG_NAME`
   （即 `E:\buildroot\prerequisites\x86_64-gettext-static`），
   静态库（`--enable-static --disable-shared`），并链接 libiconv 前置依赖。
   **必须给 gettext 自己传 `--enable-nls`**：若传 `--disable-nls`，gettext 会把
   `USE_INCLUDED_LIBINTL` 置为 `no`，只编出不安装的 `libgnuintl`（符号带 `libintl_` 前缀），
   不会安装 `libintl.a`/`libintl.h`，GCC 仍然拿不到 libintl。
   **不能装进 `$PREREQ_DIR/$HOST-$LINK_TYPE_SUFFIX`（gmp/mpfr/isl 共用的目录）**：
   该目录在 `COMMON_CPPFLAGS` 里，所有包都能看到 `libintl.h`。gdbm 等包会自动探测到
   NLS 却不会链 `-lintl`，链接时报
   `undefined reference to 'libintl_dgettext'`。
2. `library/subtargets.sh`：在 `libiconv`/`zlib` 之后、`gmp` 之前加入 `gettext` 子目标。
3. `scripts/gcc-16.2.0.sh`：
   - `--disable-nls` → `--enable-nls`
   - `--with-libiconv` → `--with-libiconv-prefix=$PREREQ_DIR/$BUILD_ARCHITECTURE-libiconv-$LINK_TYPE_SUFFIX`
   - 新增 `--with-libintl-prefix=$PREREQ_DIR/$BUILD_ARCHITECTURE-gettext-$LINK_TYPE_SUFFIX`
     （= `E:\buildroot\prerequisites\x86_64-gettext-static`，与 gettext.sh 的独立前缀一致）
   - 新增 `--localedir=$(cd "$BASE_BUILD_DIR" && pwd -W)$MINGWPREFIX/share/locale`
     （把 NLS 目录固化为**原生 Windows 绝对路径**，见下一节）

### 为什么必须新增 gettext 前置依赖

GCC 16.2 的发布包中已经**不再自带** `intl/`（gettext 运行时）。`gcc/configure` 里的
`AM_GNU_GETTEXT([external])` 找不到 libintl 时会静默置 `USE_NLS=no`，
即只改 `--enable-nls` 并不会真正得到本地化。`Makefile.def` 里仍保留
`module=gettext; module_srcdir="gettext/gettext-runtime"`，但源码包里没有该目录。

libiconv 本身无需额外处理：`scripts/libiconv.sh` 已是 prereq，
`scripts/mingw-w64-runtime-post.sh` 会把 `include/*.h`、`lib/*.dll.a`、`lib/*.a`、
`bin/*.dll` 复制进最终工具链的 `x86_64-w64-mingw32/{include,lib}` 与 `bin`。

## NLS 运行时路径（关键坑）

GCC 的 `intl.cc` 直接 `bindtextdomain ("gcc", LOCALEDIR)`，`LOCALEDIR` 是编译期常量。
构建时 `--prefix=/mingw64`，理论上应固化为 `/mingw64/share/locale`；Windows CRT 会把以 `/`
开头的路径解析为**当前盘符根目录**下的 `\mingw64\share\locale`，所以只有当工具链正好位于
`X:\mingw64` 且当前盘符是 `X:` 时才找得到翻译。

**第一次构建得到的 19 个 gcc 二进制里，实际固化的却是：**

```
E:/msys64/mingw64/share/locale
```

（`intl.o` 的 `.rdata` 里只有这一个字符串；用
`grep -a -o ".\{0,25\}share/locale" mingw64/libexec/gcc/x86_64-w64-mingw32/16.2.0/cc1.exe`
可直接看出。它来自 `mingw-builds` 预置的 bootstrap 工具链前缀 / 复用的旧构建目录，
与 MSYS2 安装路径完全相同。）

后果：运行时找不到 `gcc.mo`，`LANG=zh_CN.UTF-8 gcc --help` 仍是英文；
把 .mo 复制到 `E:\msys64\mingw64\share\locale\zh_CN\LC_MESSAGES\` 后立刻变成中文：

```
用法：gcc.exe [选项] 文件...
选项：
  --help                   显示此帮助说明。
```

由此确认——**NLS 已经编进二进制，问题只在 LOCALEDIR 固化值**。

**修复（两步）**：

1. 在 `scripts/gcc-16.2.0.sh` 的 `PKG_CONFIGURE_FLAGS` 中显式传
   `--localedir=$(cd "$BASE_BUILD_DIR" && pwd -W)$MINGWPREFIX/share/locale`
   （`pwd -W` 给出 `E:/...` 原生路径；命令行参数优先于 `/etc/config.site`
   和 Makefile 变量），保证 fallback 值正确。
2. 新增 `patches/gcc/gcc-16.2-win32-relocatable-localedir.patch`
   （已加入 `PKG_PATCHES`）：在 `gcc/intl.cc` 与 `libcpp/init.cc` 里增加
   `win32_relocatable_localedir()`，用 `GetModuleFileNameA` 取当前 exe 路径，
   逐级向上查找 `<prefix>/share/locale`（最多 6 层，覆盖 `bin/gcc.exe` 与
   `libexec/gcc/<target>/<ver>/cc1.exe` 两种布局），找到就
   `bindtextdomain("gcc", 该路径)`；找不到才退回编译期 `LOCALEDIR`。

于是 **NLS 目录随 exe 位置走，不再绑定构建路径**，工具链可整体复制/解压到任意目录。
（为了不在 libcpp 里引入 `<windows.h>` 宏污染，补丁手写了
`GetModuleFileNameA` / `GetFileAttributesA` 的 `__declspec(dllimport)` 声明。）

验证方法（构建后）：

```bash
LANG=zh_CN.UTF-8 mingw64/bin/gcc.exe --help | head -2   # 应显示「用法：gcc.exe [选项] 文件...」
LANG=zh_CN.UTF-8 mingw64/bin/gcc.exe -c                 # fatal error: 没有输入文件
# 把 mingw64 整个目录复制到别处（任意盘符）再跑一次，仍应显示中文
```

## 产物与最终验证结果

- 工具链目录：`E:\buildroot\x86_64-1620-posix-seh-ucrt-rt_v14-rev0\mingw64`（776 MB）
- 压缩包：`E:\buildroot\archives\x86_64-16.2.0-release-posix-seh-ucrt-rt_v14-rev0.7z`（104 MB，13941 个文件）
- 各包日志：`E:\buildroot\logs\`、`E:\buildroot\prerequisites-logs\`
- 构建日志：`E:\buildroot\build-run6.log`（`EXIT=0`）

实测结果：

| 检查项                | 结果                                                         |
| --------------------- | ------------------------------------------------------------ |
| `gcc.exe --version`   | `gcc 版本 16.2.0 (x86_64-posix-seh-rev0, Built by MinGW-Builds project)` |
| `-dumpmachine` / `-v` | `x86_64-w64-mingw32`，`线程模型：posix`                      |
| 配置行                | `--disable-bootstrap --enable-nls --with-libintl-prefix=...gettext-static --localedir=E:/buildroot/...` |
| 二进制                | `PE32+ executable for MS Windows 5.02 (console), x86-64`；仅依赖 `KERNEL32/ADVAPI32/api-ms-win-crt-*` |
| C + iconv             | `-liconv` 编译运行 OK，GBK「你好」→ UTF-8 正常               |
| C++17 / Fortran       | 编译运行 OK（运行需 `PATH` 含 `<prefix>/bin`，依赖 `libstdc++-6.dll`/`libgcc_s_seh-1.dll`） |
| NLS（中文）           | `LANG=zh_CN.UTF-8 gcc --help` → `用法：gcc.exe [选项] 文件...`；`gcc -c` → `fatal error: 没有输入文件` |
| NLS（英文）           | `LANG=en_US.UTF-8` → `Usage: gcc.exe [options] file...`      |
| **可迁移性**          | 把整个 `mingw64` 复制到 `E:\reloc-test\mingw64` 后：中文 `--help` 正常、`-Wall` 输出 `在函数‘main’中` / `未使用的变量‘x’`、编译运行正常 |

## 复现要点

```bash
# 1) 原生 Windows 可执行
file mingw64/bin/gcc.exe            # PE32+ executable ... x86-64
mingw64/bin/gcc.exe -dumpmachine    # x86_64-w64-mingw32

# 2) NLS
ls mingw64/share/locale/zh_CN/LC_MESSAGES/gcc.mo
LANG=zh_CN.UTF-8 mingw64/bin/gcc.exe --help | head -2

# 3) iconv
ls mingw64/x86_64-w64-mingw32/include/iconv.h
ls mingw64/x86_64-w64-mingw32/lib/libiconv.a
```

## 中文环境提示

MSYS2 的 `LANG`/`LC_ALL` 若为 `zh_CN.UTF-8`，gcc 的翻译目录按 `LANGUAGE` /
`LC_ALL` / `LANG` 顺序查找 `share/locale/<lang>/LC_MESSAGES/gcc.mo`。
