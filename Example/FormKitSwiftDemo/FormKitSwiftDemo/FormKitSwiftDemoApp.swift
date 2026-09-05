import SwiftUI

@main
struct FormKitSwiftDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-UITEST_CONTROLLED_FOCUS") {
                ControlledFocusDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("-UITEST_ROW_REMOVAL") {
                ControlledFocusDemoView(showsArray: true)
            } else if ProcessInfo.processInfo.arguments.contains("-UITEST_PICKER_LAYOUT") {
                PickerLayoutDemoView()
            } else {
                DemoContentView()
            }
        }
    }
}
