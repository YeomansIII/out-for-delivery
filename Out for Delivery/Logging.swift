//
//  Logging.swift
//  Out for Delivery
//
//  Shared os.Logger channels. The `sharing` channel traces the CloudKit
//  multi-caregiver flow (store load, share create, share accept) so issues can be
//  diagnosed from Console.app by filtering on subsystem "us.yeomans.Out-for-Delivery".
//

import os

extension Logger {
    static let sharing = Logger(subsystem: "us.yeomans.Out-for-Delivery", category: "sharing")
}
