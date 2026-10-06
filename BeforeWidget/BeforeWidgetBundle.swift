import WidgetKit
import SwiftUI

@main
struct BeforeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeforeWidget()
        #if !targetEnvironment(macCatalyst)
        NextMeetingLiveActivity()
        MeetingAlarmLiveActivity()
        #endif
    }
}
