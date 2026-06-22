# IPA Reverse Analysis Tool MVP

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

这是面向授权 `.ipa` 的桌面静态分析工具：支持 GUI 拖入 IPA、环境体检、资源与敏感字符串扫描，并输出 `HTML` / `JSON` / `Markdown` 报告。

## 一、运行方式

### 1.1、macOS GUI

源码模式启动 GUI 后，把 `.ipa` 文件拖入窗口并点击“开始分析”。平台安装包由项目构建脚本在目标系统本机生成。

源码模式可以运行：

```bash
cd /Users/jobs/Downloads/ipa_reverse_tool
./.venv/bin/python -m ipa_reverse_tool.main gui
```

### 1.2、命令行

```bash
python3 -m ipa_reverse_tool.main doctor --output output/diagnostics
python3 -m ipa_reverse_tool.main analyze /path/to/App.ipa --output output/latest
```

## 二、构建方式

### 2.1、macOS

在 Finder 中双击：

```text
build_macos.command/build_macos.command
```

构建产物：

```text
dist/IPA Reverse Analysis Tool.app
dist/IPA-Reverse-Analysis-Tool-macOS.dmg
```

### 2.2、Windows

在 Windows 中双击：

```text
build_windows.bat/build_windows.bat
```

脚本会在 Windows 本机创建 `.venv`、安装依赖，并输出 GUI 主程序目录和 `IPA环境体检.exe`。PyInstaller 不支持从 macOS 交叉生成 Windows `.exe`，因此必须在 Windows 上运行该脚本。

## 三、交付入口

```text
doctor/macos/IPA环境体检.command
build_macos.command/build_macos.command
build_windows.bat/build_windows.bat
IPAReverseAnalysisTool.spec
ipa_reverse_tool/core/environment_doctor.py
ipa_reverse_tool/core/ipa_analyzer.py
ipa_reverse_tool/gui.py
```

## 四、当前能力

```text
- GUI：拖入 IPA、文件选择、输出目录、进度、日志、打开报告
- 环境体检：Python 包、Apple CLT、radare2、Ghidra、Java、jtool2
- IPA 解包：定位 Payload/*.app
- Info.plist：基础字段、权限、URL Scheme、ATS、后台模式
- 资源分类：图片、plist、json、sqlite、framework、dylib、证书、web、多语言
- 字符串扫描：URL、IP、JWT、token/secret/api key 关键词
- 报告输出：reverse_report.html / reverse_report.json / reverse_report.md
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
