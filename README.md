# StickyNotes 便签软件

一款轻量级的 Mac 原生便签 + Todo 应用，使用 Swift 和 SwiftUI 构建。

## ✨ 特色功能

### 📝 便签功能
- 创建多个便签
- 支持标题和内容
- 6 种颜色可选（黄、绿、蓝、粉、紫、橙）
- 数据自动保存

### ✅ Todo 功能
- 快速添加任务
- 勾选完成状态
- 3 级优先级（低、普通、高）
- 按优先级和完成状态智能排序

### 🎯 边缘吸附功能（核心特色）
- **自动吸附**：窗口移动到屏幕左/右边缘时自动吸附并收起
- **悬停滑出**：鼠标悬停在收起的标签上，窗口自动滑出
- **智能收回**：
  - 滑出后未操作 → 鼠标移出即收回
  - 滑出后有操作 → 点击窗口外部才收回
- **拖离解除**：手动拖动窗口离开边缘后，不再自动吸附

## 🛠 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode Command Line Tools（仅编译时需要）

## 🚀 快速开始

### 方法一：直接运行（推荐）

```bash
cd /Users/ivean/Documents/软件安装/我的扩展/便签软件/StickyNotes
swift run
```

### 方法二：打包为 App Bundle

```bash
cd /Users/ivean/Documents/软件安装/我的扩展/便签软件/StickyNotes
chmod +x build_app.sh
./build_app.sh
```

打包完成后，双击 `StickyNotes.app` 即可运行。

### 方法三：安装到应用程序文件夹

```bash
# 先执行打包
./build_app.sh

# 复制到应用程序文件夹
cp -r StickyNotes.app /Applications/
```

## 📁 项目结构

```
StickyNotes/
├── Package.swift              # Swift Package Manager 配置
├── build_app.sh               # App Bundle 打包脚本
├── README.md                  # 本说明文件
└── Sources/StickyNotes/
    ├── StickyNotesApp.swift   # 应用入口
    ├── Models/
    │   ├── Note.swift         # 便签数据模型
    │   └── TodoItem.swift     # Todo 数据模型
    ├── Views/
    │   ├── MainView.swift     # 主视图
    │   ├── NoteListView.swift # 便签列表
    │   ├── NoteEditorView.swift # 便签编辑器
    │   └── TodoListView.swift # Todo 列表
    ├── ViewModels/
    │   └── NotesManager.swift # 数据管理器
    ├── Window/
    │   ├── WindowManager.swift    # 窗口状态管理
    │   └── EdgeSnapWindow.swift   # 边缘吸附控制器
    └── Utils/
        └── StorageManager.swift   # 数据持久化
```

## 💾 数据存储

数据保存在以下位置：
```
~/Library/Application Support/StickyNotes/
├── notes.json    # 便签数据
└── todos.json    # Todo 数据
```

## 🔧 开发命令

```bash
# 调试模式构建
swift build

# 发布模式构建
swift build -c release

# 直接运行
swift run

# 清理构建缓存
swift package clean
```

## 📝 使用提示

1. **边缘吸附**：将窗口拖动到屏幕最左侧或最右侧边缘，窗口会自动吸附并在短暂停留后收起
2. **快速访问**：收起后，将鼠标移到屏幕边缘的小标签上即可滑出窗口
3. **锁定窗口**：在滑出的窗口内进行任何操作后，窗口不会自动收回，需点击窗口外部才会收起
4. **解除吸附**：直接拖动窗口离开边缘即可恢复自由浮动模式

## 📄 License

MIT License
