//
//  AppDelegate.swift
//  Bluesnooze
//
//  Created by Oliver Peate on 07/04/2020.
//  Copyright © 2020 Oliver Peate. All rights reserved.
//

import Cocoa
import IOBluetooth
import LaunchAtLogin

// UserDefaults keys
private let startTimeKey = "startTime"
private let endTimeKey = "endTime"

// Default time range: 5 PM to 6 AM
private let defaultStartHour = 17 // 5 PM
private let defaultEndHour = 6   // 6 AM

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet weak var startTimeMenuItem: NSMenuItem!
    @IBOutlet weak var endTimeMenuItem: NSMenuItem!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Register default time range
        UserDefaults.standard.register(defaults: [
            startTimeKey: defaultStartHour,
            endTimeKey: defaultEndHour
        ])
        
        initStatusItem()
        setLaunchAtLoginState()
        updateTimeMenuItems()
        setupNotificationHandlers()
        setBluetooth(powerOn: true)
    }

    // MARK: Click handlers

    @IBAction func launchAtLoginClicked(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
        setLaunchAtLoginState()
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
    
    @IBAction func setStartTime(_ sender: NSMenuItem) {
        let hour = sender.tag
        UserDefaults.standard.set(hour, forKey: startTimeKey)
        updateTimeMenuItems()
    }
    
    @IBAction func setEndTime(_ sender: NSMenuItem) {
        let hour = sender.tag
        UserDefaults.standard.set(hour, forKey: endTimeKey)
        updateTimeMenuItems()
    }
    
    private func updateTimeMenuItems() {
        let startHour = UserDefaults.standard.integer(forKey: startTimeKey)
        let endHour = UserDefaults.standard.integer(forKey: endTimeKey)
        
        startTimeMenuItem.title = "Start Time: \(formatHour(startHour))"
        endTimeMenuItem.title = "End Time: \(formatHour(endHour))"
        
        // Update submenu items
        if let startSubmenu = startTimeMenuItem.submenu,
           let endSubmenu = endTimeMenuItem.submenu {
            for item in startSubmenu.items + endSubmenu.items {
                item.state = (item.tag == startHour && item.menu == startSubmenu) ||
                            (item.tag == endHour && item.menu == endSubmenu) ? .on : .off
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return formatter.string(from: date)
    }
    
    private func isWithinTimeRange() -> Bool {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        let startHour = UserDefaults.standard.integer(forKey: startTimeKey)
        let endHour = UserDefaults.standard.integer(forKey: endTimeKey)
        
        // Handle overnight range (e.g., 10 PM to 6 AM)
        if endHour <= startHour {
            return currentHour >= startHour || currentHour < endHour
        }
        
        // Normal range within the same day
        return currentHour >= startHour && currentHour < endHour
    }

    // MARK: Notification handlers

    func setupNotificationHandlers() {
        [
            NSWorkspace.willSleepNotification: #selector(onPowerDown(note:)),
            NSWorkspace.willPowerOffNotification: #selector(onPowerDown(note:)),
            NSWorkspace.didWakeNotification: #selector(onPowerUp(note:))
        ].forEach { notification, sel in
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: sel, name: notification, object: nil)
        }
    }

    @objc func onPowerDown(note: NSNotification) {
        if isWithinTimeRange() {
            setBluetooth(powerOn: false)
        }
    }

    @objc func onPowerUp(note: NSNotification) {
        setBluetooth(powerOn: true)
    }

    private func setBluetooth(powerOn: Bool) {
        IOBluetoothPreferenceSetControllerPowerState(powerOn ? 1 : 0)
    }

    // MARK: UI state

    private func initStatusItem() {
        if UserDefaults.standard.bool(forKey: "hideIcon") {
            return
        }

        if let icon = NSImage(named: "bluesnooze") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "Bluesnooze"
        }
        statusItem.menu = statusMenu
    }

    private func setLaunchAtLoginState() {
        let state = LaunchAtLogin.isEnabled ? NSControl.StateValue.on : NSControl.StateValue.off
        launchAtLoginMenuItem.state = state
    }
}
