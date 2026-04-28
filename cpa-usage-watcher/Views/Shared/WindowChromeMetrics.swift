import SwiftUI

enum WindowChromeMetrics {
    static let systemRailHeight: CGFloat = 34
    static let systemControlCenterY: CGFloat = 16
    static let systemControlSize: CGFloat = 30
    static let systemControlTopInset: CGFloat = systemControlCenterY - systemControlSize / 2

    static let appChromeHeight: CGFloat = 66
    static let compactAppChromeHeight: CGFloat = 96
    static let appChromeTopInset: CGFloat = 14

    static let appChromeHorizontalInset: CGFloat = 28
    static let compactAppChromeHorizontalInset: CGFloat = 18
    static let collapsedSidebarButtonLeading: CGFloat = 90
    static let collapsedDetailLeadingInset: CGFloat = 118
}
