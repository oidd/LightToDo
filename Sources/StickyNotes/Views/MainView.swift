import SwiftUI

struct MainView: View {
    @EnvironmentObject var notesManager: NotesManager
    @EnvironmentObject var windowManager: WindowManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.controlActiveState) var controlActiveState
    @State private var isSidebarCollapsed = false
    @State private var editorMode: String = "note" // 默认为笔记模式
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. 底层：编辑区 (全屏铺满，zIndex最低)
            EditorView(editorMode: $editorMode, isSidebarCollapsed: isSidebarCollapsed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)
            
            // 2. 中层：侧边栏 (zIndex=1，在编辑器上方，阴影可见)
            SidebarView(isCollapsed: $isSidebarCollapsed)
                .zIndex(1)
            
            // 3. 顶层：窗口控制按钮 (绝对锁定位置)
            WindowControlButtons(isActive: isWindowActive)
                .padding(.leading, 26)
                .padding(.top, 22)
                .zIndex(2)
            
            // 4. 顶层：功能按钮 (根据折叠状态调整位置)
            HStack(spacing: 10) {
                // 自定义侧边栏切换按钮
                Button(action: toggleSidebar) {
                    ZStack {
                        // 1. 点击热区 & 强制尺寸占位
                        Color.clear
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                        
                        // 2. 图标绘制
                        ZStack {
                            // 外框
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary, lineWidth: 1.4)
                                .frame(width: 20, height: 18)
                            
                            // 分割线
                            Rectangle()
                                .fill(Color.secondary)
                                .frame(width: 1.4, height: 18)
                                .offset(x: -4)
                            
                            // 左侧列表线
                            VStack(spacing: 2.5) {
                                Capsule().frame(width: 3.5, height: 1.2)
                                Capsule().frame(width: 3.5, height: 1.2)
                                Capsule().frame(width: 3.5, height: 1.2)
                            }
                            .foregroundColor(.secondary)
                            .offset(x: -7)
                        }
                    }
                    .background(Color.clear)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                // --- 模式切换器 (胶囊样式) ---
                ZStack {
                    // 背景胶囊 (灰色轨道)
                    Capsule()
                        .fill(Color(nsColor: .controlColor).opacity(0.5)) 
                        .frame(width: 104, height: 28)
                        .overlay(
                            Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                        )
                    
                    // 动态滑动滑块 (白色)
                    HStack(spacing: 0) {
                        if editorMode == "todo" { Spacer() }
                        Capsule()
                            .fill(colorScheme == .dark ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.white)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                            .frame(width: 50, height: 24)
                            .padding(.horizontal, 2)
                        if editorMode == "note" { Spacer() }
                    }
                    .frame(width: 104, height: 28)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: editorMode)
                    
                    // 文字层
                    HStack(spacing: 0) {
                        // 笔记按钮
                        Button(action: { 
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                editorMode = "note" 
                            }
                        }) {
                            Text("笔记")
                                .font(.system(size: 13, weight: editorMode == "note" ? .semibold : .medium))
                                .foregroundColor(editorMode == "note" ? .accentColor : .primary.opacity(0.6))
                                .frame(width: 50, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        // 待办按钮
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                editorMode = "todo"
                            }
                        }) {
                            Text("待办")
                                .font(.system(size: 13, weight: editorMode == "todo" ? .semibold : .medium))
                                .foregroundColor(editorMode == "todo" ? .accentColor : .primary.opacity(0.6))
                                .frame(width: 50, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 104, height: 28)
                }
                .padding(.leading, 0) // 由外层 Padding 控制
            }
            // 展开时在面板右侧 (260侧边栏 + 15 WebviewPadding = 275)，折叠时避开红绿灯 (95)
            .padding(.leading, isSidebarCollapsed ? 95 : 275)
            .padding(.top, 14)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSidebarCollapsed)
            .zIndex(3)
            
            // 5. 顶部可拖拽手柄区域（仅在右侧区域生效，避免干扰侧边栏排序）
            Color.clear
                .frame(height: 44)
                .contentShape(Rectangle())
                .allowWindowDrag()
                .padding(.leading, isSidebarCollapsed ? 95 : 260)
                .zIndex(0)
        }
        .frame(minWidth: 700, minHeight: 450)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .ignoresSafeArea()
    }
    
    private var isWindowActive: Bool {
        controlActiveState == .key || controlActiveState == .active
    }
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isSidebarCollapsed.toggle()
        }
    }
    
    private func addNewNote() {
        withAnimation {
            _ = notesManager.addNote()
        }
    }
}
