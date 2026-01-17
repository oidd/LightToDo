import SwiftUI

enum WindowState {
    case floating       // 自由浮动
    case snapped        // 已吸附但展开
    case collapsed      // 已收起（隐藏到边缘）
    case expanded       // 滑出展开中
    case locked         // 锁定展开（有用户操作）
}

enum SnapEdge {
    case none
    case left
    case right
}

class WindowManager: ObservableObject {
    @Published var state: WindowState = .floating
    @Published var snapEdge: SnapEdge = .none
    @Published var hasUserInteraction: Bool = false
    @Published var isMouseInside: Bool = false
    
    func recordInteraction() {
        if state == .expanded {
            hasUserInteraction = true
            state = .locked
        }
    }
    
    func resetInteraction() {
        hasUserInteraction = false
    }
}
