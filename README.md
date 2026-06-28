# `JobsReverseIPA`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`JobsReverseIPA` 是面向授权 `.ipa` 的桌面静态分析工具：支持 GUI 拖入 IPA、环境体检、资源与敏感字符串扫描，并输出 `HTML` / `JSON` / `Markdown` 报告。

外层目录只保留总说明和平台打包入口；Python 源码、配置、资源、工具链、doctor 和构建产物都收在内层 `./JobsReverseIPA/`。

## 一、目录结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
.
├── README.md
├── 【MacOS】📦生成dmg.command
├── 【Windows】📦生成exe.bat
└── JobsReverseIPA/
    ├── pyproject.toml
    ├── requirements.txt
    ├── IPAReverseAnalysisTool.spec
    ├── icon.png
    ├── ipa_reverse_tool/
    ├── doctor/
    ├── rules/
    ├── scripts/
    ├── templates/
    ├── tools/
    └── assets/
```

- `./README.md`：外层总说明，统一解释 macOS / Windows 打包入口和内层 Python 工程。
- `./【MacOS】📦生成dmg.command`：macOS 打包入口，双击后构建 `.app` 和 `.dmg`。
- `./【Windows】📦生成exe.bat`：Windows 打包入口，在 Windows 本机生成 GUI 主程序和环境体检 `.exe`。
- `./JobsReverseIPA/`：内层 Python 工程目录，保存源码、依赖、doctor、规则、模板、工具链和构建产物。

外层 `.bat` / `.command` 不使用同名文件夹包裹，也不分别放独立 `README.md`；两端打包说明统一收口在本文件。

## 二、打包方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 2.1、macOS

在 Finder 中双击：

```text
./【MacOS】📦生成dmg.command
```

脚本会进入内层 `./JobsReverseIPA/`，创建或复用 `.venv`，安装构建依赖，经 `YES` 确认后清理旧 `build` / `dist`，再通过 [**PyInstaller**](https://pyinstaller.org/) 构建 App 和 DMG。

构建产物：

```text
./JobsReverseIPA/dist/IPA Reverse Analysis Tool.app
./JobsReverseIPA/dist/IPA-Reverse-Analysis-Tool-macOS.dmg
```

### 2.2、Windows

在 Windows 中双击：

```text
./【Windows】📦生成exe.bat
```

脚本会进入内层 `./JobsReverseIPA/`，创建或复用 `.venv`，安装依赖，经 `YES` 确认后清理旧 `build` / `dist`，再构建 GUI 主程序和 `IPA环境体检.exe`。Windows `.exe` 必须在 Windows 本机生成，macOS 不负责交叉构建。

构建产物：

```text
.\JobsReverseIPA\dist\IPA Reverse Analysis Tool\IPA Reverse Analysis Tool.exe
.\JobsReverseIPA\dist\IPA Reverse Analysis Tool\IPA环境体检.exe
```

## 三、成品运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- macOS 用户通过生成的 `.dmg` 安装或直接运行其中的 `IPA Reverse Analysis Tool.app`。
- Windows 用户运行 `.\JobsReverseIPA\dist\IPA Reverse Analysis Tool\IPA Reverse Analysis Tool.exe`。
- 环境体检工具随构建产物一起分发；macOS 体检脚本位于 DMG 内，Windows 体检程序位于主程序目录内。

源码调试仅面向开发维护，可进入内层 Python 工程后运行：

```shell
cd ./JobsReverseIPA
python3 -m ipa_reverse_tool.main doctor --output output/diagnostics
python3 -m ipa_reverse_tool.main analyze <path-to>/App.ipa --output output/latest
python3 -m ipa_reverse_tool.main gui
```

## 四、当前能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- GUI：拖入 IPA、文件选择、输出目录、进度、日志、打开报告。
- 环境体检：Python 包、Apple CLT、radare2、Ghidra、Java、jtool2。
- IPA 解包：定位 `Payload/*.app`。
- `Info.plist`：基础字段、权限、URL Scheme、ATS、后台模式。
- 资源分类：图片、plist、json、sqlite、framework、dylib、证书、web、多语言。
- 字符串扫描：URL、IP、JWT、token/secret/api key 关键词。
- 报告输出：`reverse_report.html` / `reverse_report.json` / `reverse_report.md`。

## 五、风险说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 只分析用户有权审计的 `.ipa` 文件。
- macOS 构建脚本只做本机 ad-hoc 签名，正式公开分发仍需 Developer ID 签名和 notarization。
- Windows 构建未做代码签名，SmartScreen 可能提示未知发布者。
- 构建脚本会在内层 `./JobsReverseIPA/` 里创建 `.venv`，并在用户输入 `YES` 后删除旧 `build` / `dist`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
