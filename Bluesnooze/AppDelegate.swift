//
//  AppDelegate.swift
//  Bluesnooze
//
//  Created by Oliver Peate on 07/04/2020.
//  Copyright © 2020 Oliver Peate. All rights reserved.
//

import Cocoa
import IOBluetooth
import IOKit.ps
import LaunchAtLogin
import os

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let logger = Logger(subsystem: "com.oliverpeate.Bluesnooze", category: "power")
    private var isAsleep = false
    private var bluetoothPoweredOn: Bool?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        initStatusItem()
        setLaunchAtLoginState()
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

    // MARK: Notification handlers

    func setupNotificationHandlers() {
        [
            NSWorkspace.willSleepNotification: #selector(onPowerDown(note:)),
            NSWorkspace.willPowerOffNotification: #selector(onPowerDown(note:)),
            NSWorkspace.didWakeNotification: #selector(onPowerUp(note:))
        ].forEach { notification, sel in
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: sel, name: notification, object: nil)
        }

        // Charger and display changes can arrive just after willSleep (when unplugging
        // a single USB-C cable) or during a brief dark wake (when plugging it back in)
        let context = Unmanaged.passUnretained(self).toOpaque()

        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                .updateBluetoothWhileAsleep(reason: "Power source changed")
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard let context = context, !flags.contains(.beginConfigurationFlag) else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                .updateBluetoothWhileAsleep(reason: "Displays changed")
        }, context)
    }

    @objc func onPowerDown(note: NSNotification) {
        let onAC = isOnACPower()
        let externalDisplay = hasExternalDisplay()
        logger.notice("""
            \(note.name.rawValue, privacy: .public): \
            AC=\(onAC, privacy: .public) externalDisplay=\(externalDisplay, privacy: .public)
            """)

        // In clamshell mode (charger + external display) keep Bluetooth on, so a
        // Bluetooth keyboard or mouse can wake the Mac, as macOS normally allows
        if note.name == NSWorkspace.willSleepNotification {
            isAsleep = true

            if onAC && externalDisplay {
                logger.notice("Clamshell setup detected, leaving Bluetooth on")
                return
            }
        }

        setBluetooth(powerOn: false)
    }

    @objc func onPowerUp(note: NSNotification) {
        isAsleep = false
        logger.notice("\(note.name.rawValue, privacy: .public): turning Bluetooth on")
        setBluetooth(powerOn: true)
    }

    private func updateBluetoothWhileAsleep(reason: String) {
        guard isAsleep else { return }

        let onAC = isOnACPower()
        let externalDisplay = hasExternalDisplay()
        let powerOn = onAC && externalDisplay

        guard powerOn != bluetoothPoweredOn else { return }

        logger.notice("""
            \(reason, privacy: .public) while asleep: \
            AC=\(onAC, privacy: .public) externalDisplay=\(externalDisplay, privacy: .public), \
            turning Bluetooth \(powerOn ? "on" : "off", privacy: .public)
            """)
        setBluetooth(powerOn: powerOn)
    }

    private func isOnACPower() -> Bool {
        let source = IOPSGetProvidingPowerSourceType(nil).takeUnretainedValue() as String
        return source == kIOPSACPowerValue
    }

    private func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return false
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return false
        }

        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private func setBluetooth(powerOn: Bool) {
        IOBluetoothPreferenceSetControllerPowerState(powerOn ? 1 : 0)
        bluetoothPoweredOn = powerOn
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
