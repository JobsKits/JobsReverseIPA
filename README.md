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
./dist/YYYY.MM.DD HH-mm-ss/IPA Reverse Analysis Tool.app
./dist/YYYY.MM.DD HH-mm-ss/IPA-Reverse-Analysis-Tool-macOS.dmg
```

### 2.2、Windows

在 Windows 中双击：

```text
./【Windows】📦生成exe.bat
```

脚本会进入内层 `./JobsReverseIPA/`，创建或复用 `.venv`，安装依赖，经 `YES` 确认后清理旧 `build` / `dist`，再构建 GUI 主程序和 `IPA环境体检.exe`。Windows `.exe` 必须在 Windows 本机生成，macOS 不负责交叉构建。

构建产物：

```text
.\dist\YYYY.MM.DD HH-mm-ss\IPA Reverse Analysis Tool\IPA Reverse Analysis Tool.exe
.\dist\YYYY.MM.DD HH-mm-ss\IPA Reverse Analysis Tool\IPA环境体检.exe
```

## 三、成品运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- macOS 用户通过生成的 `.dmg` 安装或直接运行其中的 `IPA Reverse Analysis Tool.app`。
- Windows 用户运行 `.\dist\YYYY.MM.DD HH-mm-ss\IPA Reverse Analysis Tool\IPA Reverse Analysis Tool.exe`。
- 环境体检工具随构建产物一起分发；macOS 体检脚本位于 DMG 内，Windows 体检程序位于主程序目录内。

源码调试仅面向开发维护，可进入内层 Python 工程后运行：

```shell
cd ./JobsReverseIPA
python3 -m ipa_reverse_tool.main doctor --output output/diagnostics
python3 -m ipa_reverse_tool.main analyze <path-to>/App.ipa --output output/latest
python3 -m ipa_reverse_tool.main gui
```

## 四、当前能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- GUI：拖入 IPA、文件选择、输出目录、进度、日志、打开报告；macOS 最小化后驻留系统顶部菜单栏，可从图标恢复或退出。
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

打包前会清理该应用工程的旧 `dist` 产物，清理失败则停止；成功后自动打开当前平台产物的磁盘位置并运行本次生成的 APP / EXE，结尾无需回车。失败时不启动软件；运行前的防误触确认保留。

必需依赖缺失时，直接回车联网安装；输入任意字符后回车取消整个流程。安装失败或复检仍不可用时停止，不继续清理旧产物或打包。健康依赖直接复用；可选升级和词库更新仍为回车跳过、任意字符执行。

第一层交付目录与平台打包脚本同层保存 `dist/`，以及最新 APP / DMG 的相对符号链接（Mac）或 EXE / 分发包的 `.lnk`（Windows）。双击快捷方式即可接触成品，真实文件保留在 `dist/`；成功构建自动更新入口，清理旧产物时移除对应旧入口。尚无成品时不生成无效快捷方式。

构建产物使用本机本地构建时间，格式为 `YYYY.MM.DD HH-mm-ss`（年月日时分秒），例如 `2020.06.04 12-23-21`。每次构建的 APP、DMG、EXE、ZIP 和配套文件统一保存到交付层 `./dist/YYYY.MM.DD HH-mm-ss/`，同次构建只取一次时间；第一层快捷方式指向本次时间目录，成功后打开该目录并启动其中的软件。旧产物沿用原有清理规则；历史产物缺少可靠构建时间时，不补写推测时间。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
