# `build_macos.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`build_macos.command` 用于从 IPA Reverse Analysis Tool 的 Python 源码构建 macOS `.app` 和 `.dmg`。DMG 内包含主程序、独立环境体检工具和 `Applications` 快捷入口。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在 macOS 本机根据当前源码构建可运行 App。
- 生成可以把 App 拖入系统“应用程序”目录的 DMG。
- 重新构建 GUI、分析逻辑或资源调整后的交付包。

## 二、目录结构

```text
build_macos.command/
├── build_macos.command
└── README.md
```

脚本依赖项目根目录中的：

```text
IPAReverseAnalysisTool.spec
requirements.txt
ipa_reverse_tool/
doctor/macos/IPA环境体检.command
```

## 三、执行前检查

- 当前系统必须为 macOS。
- 已安装 Python 3、`hdiutil` 和 `codesign`。
- 项目源码、统一 PyInstaller spec 和依赖文件保持完整。
- 清理旧 `build/`、`dist/` 前必须输入 `YES`。

## 四、运行方式

### 4.1、双击运行

在 Finder 中双击：

```text
build_macos.command/build_macos.command
```

### 4.2、终端运行

```shell
cd "/Users/jobs/Downloads/ipa_reverse_tool/build_macos.command"
./build_macos.command
```

## 五、构建流程

1. 展示脚本内置自述并等待确认。
2. 创建或复用项目 `.venv`。
3. 安装 `requirements.txt` 中的运行与构建依赖。
4. 输入 `YES` 后清理旧 `build/` 和 `dist/`。
5. 使用 `IPAReverseAnalysisTool.spec` 构建 `.app`。
6. 对本地 App 进行 ad-hoc 签名和校验。
7. 生成包含 `Applications` 快捷入口的 DMG。

## 六、输出目录

```text
dist/
├── IPA Reverse Analysis Tool.app
└── IPA-Reverse-Analysis-Tool-macOS.dmg
```

## 七、风险说明

- 脚本会在输入 `YES` 后删除旧 `build/`、`dist/` 构建产物。
- 默认是本地 ad-hoc 签名，适合本机测试；正式分发需要 Apple Developer ID 签名和 notarization。
- 构建架构取决于当前 Python 和本机架构，Apple Silicon 默认生成 arm64 版本。

## 八、日志文件

```text
/tmp/build_macos.log
```

## 九、常见问题

### 9.1、提示缺少 PyInstaller

确认 `requirements.txt` 完整，重新运行脚本，构建依赖会安装到项目 `.venv`。

### 9.2、首次打开被 Gatekeeper 拦截

进入“系统设置 -> 隐私与安全性”，确认来源后选择继续打开。正式对外发布应完成签名和公证。

### 9.3、DMG 没有 Applications 入口

检查 `dist/dmg_staging` 是否被旧构建污染，重新运行脚本并在清理步骤输入 `YES`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
