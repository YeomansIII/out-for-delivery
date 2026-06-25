//
//  LiveActivityBundle.swift
//  LiveActivity
//

import WidgetKit
import SwiftUI

@main
struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ContractionLiveActivity()
        FeedReminderAlarmWidget()
    }
}
