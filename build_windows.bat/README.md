# `build_windows.bat`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`build_windows.bat` 用于在 Windows 本机从 IPA Reverse Analysis Tool 的 Python 源码构建 GUI 主程序和独立环境体检工具。主脚本与本 `README.md` 保持在同一目录。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在 Windows 本机根据当前源码构建 GUI `.exe`。
- 构建可随主程序目录一起交付的 `IPA环境体检.exe`。
- 重新构建 GUI、分析逻辑或规则调整后的 Windows 版本。

## 二、目录结构

```text
build_windows.bat/
├── build_windows.bat
└── README.md
```

脚本会把工作目录切换到项目根目录，并读取：

```text
IPAReverseAnalysisTool.spec
requirements.txt
ipa_reverse_tool/
doctor/doctor_entry.py
```

## 三、执行前检查

- 当前系统必须为 Windows。
- 已安装 Python 3，并确保 `python` 命令已加入 `PATH`。
- 项目源码、统一 PyInstaller spec 和依赖文件保持完整。
- 清理旧 `build/`、`dist/` 前必须输入 `YES`。

## 四、运行方式

### 4.1、双击运行

在资源管理器中双击：

```text
build_windows.bat/build_windows.bat
```

### 4.2、命令行运行

```batch
cd /d "项目目录\build_windows.bat"
build_windows.bat
```

## 五、构建流程

1. 展示脚本内置说明并等待确认。
2. 切换到项目根目录。
3. 创建或复用项目 `.venv`。
4. 安装 `requirements.txt` 中的运行与构建依赖。
5. 输入 `YES` 后清理旧 `build/` 和 `dist/`。
6. 使用统一 spec 构建 Windows GUI 主程序。
7. 单独构建 `IPA环境体检.exe` 并复制到主程序目录。

## 六、输出目录

```text
dist/
└── IPA Reverse Analysis Tool/
    ├── IPA Reverse Analysis Tool.exe
    ├── IPA环境体检.exe
    └── 其它运行依赖
```

## 七、风险说明

- 脚本会在输入 `YES` 后删除旧 `build/`、`dist/` 构建产物。
- PyInstaller 必须在 Windows 上运行，不能从 macOS 交叉生成可运行的 Windows `.exe`。
- 主程序采用 `onedir` 结构，不能只拿走单个主程序 `.exe`；必须连同整个输出目录交付。

## 八、常见问题

### 8.1、提示找不到 Python

安装 Python 3 时启用“Add Python to PATH”，重新打开终端后再运行脚本。

### 8.2、提示找不到主程序

检查 PyInstaller 输出，并确认 `dist/IPA Reverse Analysis Tool/` 没有被杀毒软件隔离。

### 8.3、双击后立即关闭

从 `cmd` 中运行脚本查看完整错误，或在脚本失败后的暂停提示中检查上方输出。

## 九、未执行声明

当前脚本在 macOS 开发环境中只能做结构和文本检查；Windows `.exe` 构建必须在 Windows 本机实际执行验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
