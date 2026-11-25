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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    /// What Bluesnooze does when the Mac sleeps.
    enum SleepMode: String {
        /// Switch the whole Bluetooth controller off (the original behaviour).
        case powerOff
        /// Keep Bluetooth on, and only disconnect the devices the user picked. This keeps
        /// Find My discoverability and "Unlock with Apple Watch" working.
        case disconnectDevices
    }

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let powerOffItem = NSMenuItem(title: "Turn off all Bluetooth on sleep",
                                          action: #selector(sleepModeClicked(_:)), keyEquivalent: "")
    private let disconnectItem = NSMenuItem(title: "Only disconnect selected devices on sleep",
                                            action: #selector(sleepModeClicked(_:)), keyEquivalent: "")
    private let devicesItem = NSMenuItem(title: "Devices to disconnect", action: nil, keyEquivalent: "")
    private let reconnectItem = NSMenuItem(title: "Reconnect devices on wake",
                                           action: #selector(reconnectClicked(_:)), keyEquivalent: "")

    private var isSleeping = false
    private var disconnectedOnSleep = Set<String>()
    private var connectNotification: IOBluetoothUserNotification?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        initStatusItem()
        setupDeviceMenuItems()
        setLaunchAtLoginState()
        setupNotificationHandlers()
        setBluetooth(powerOn: true)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(onDeviceConnected(_:device:))
        )
    }

    // MARK: Click handlers

    @IBAction func launchAtLoginClicked(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
        setLaunchAtLoginState()
    }

    @objc func sleepModeClicked(_ sender: NSMenuItem) {
        sleepMode = (sender === disconnectItem) ? .disconnectDevices : .powerOff
        updateDeviceMenuState()
    }

    @objc func reconnectClicked(_ sender: NSMenuItem) {
        reconnectOnWake = !reconnectOnWake
        updateDeviceMenuState()
    }

    @objc func deviceClicked(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        var devices = selectedDevices
        if devices[address] != nil {
            devices.removeValue(forKey: address)
        } else {
            devices[address] = sender.title
        }
        selectedDevices = devices
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }

    // MARK: Notification handlers

    func setupNotificationHandlers() {
        [
            NSWorkspace.willSleepNotification: #selector(onPowerDown(note:)),
            NSWorkspace.willPowerOffNotification: #selector(onPowerDown(note:)),
            NSWorkspace.didWakeNotification: #selector(onPowerUp(note:)),
            NSWorkspace.screensDidWakeNotification: #selector(onScreensWake(note:))
        ].forEach { notification, sel in
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: sel, name: notification, object: nil)
        }
    }

    @objc func onPowerDown(note: NSNotification) {
        isSleeping = true
        switch sleepMode {
        case .powerOff:
            setBluetooth(powerOn: false)
        case .disconnectDevices:
            disconnectSelectedDevices()
        }
    }

    @objc func onPowerUp(note: NSNotification) {
        switch sleepMode {
        case .powerOff:
            isSleeping = false
            setBluetooth(powerOn: true)
        case .disconnectDevices:
            // Bluetooth was never switched off, but make sure it is on.
            setBluetooth(powerOn: true)
            // A "dark wake" (the Mac wakes briefly with the display off, e.g. to handle a Bluetooth
            // connection) also posts this notification. Keep guarding until the display is really on.
            if !CGDisplayIsAsleep(CGMainDisplayID()) {
                finishWake()
            }
        }
    }

    @objc func onScreensWake(note: NSNotification) {
        if isSleeping && sleepMode == .disconnectDevices {
            finishWake()
        }
    }

    private func finishWake() {
        isSleeping = false
        if reconnectOnWake {
            reconnectDevices()
        }
        disconnectedOnSleep.removeAll()
    }

    /// Called when any device connects. If a selected device manages to reconnect while the
    /// Mac is asleep (e.g. during a dark wake), drop it again.
    @objc func onDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard isSleeping, sleepMode == .disconnectDevices,
              let address = device.addressString,
              selectedDevices[address] != nil else { return }
        disconnectedOnSleep.insert(address)
        device.closeConnection()
    }

    private func setBluetooth(powerOn: Bool) {
        IOBluetoothPreferenceSetControllerPowerState(powerOn ? 1 : 0)
    }

    // MARK: Per-device disconnect

    private func pairedDevices() -> [IOBluetoothDevice] {
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }

    private func disconnectSelectedDevices() {
        let selected = selectedDevices
        for device in pairedDevices() {
            guard let address = device.addressString, selected[address] != nil, device.isConnected() else { continue }
            disconnectedOnSleep.insert(address)
            device.closeConnection()
        }
    }

    private func reconnectDevices() {
        let addresses = disconnectedOnSleep
        let devices = pairedDevices().filter { device in
            guard let address = device.addressString else { return false }
            return addresses.contains(address) && !device.isConnected()
        }
        // openConnection() blocks until the connection is made (or fails), so keep it off the main thread.
        DispatchQueue.global(qos: .utility).async {
            devices.forEach { $0.openConnection() }
        }
    }

    // MARK: Settings

    /// Paired-device address -> display name, for the devices the user wants disconnected on sleep.
    private var selectedDevices: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "selectedDevices") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "selectedDevices") }
    }

    private var sleepMode: SleepMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "sleepMode") ?? ""
            return SleepMode(rawValue: raw) ?? .powerOff
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sleepMode") }
    }

    private var reconnectOnWake: Bool {
        get { UserDefaults.standard.bool(forKey: "reconnectOnWake") }
        set { UserDefaults.standard.set(newValue, forKey: "reconnectOnWake") }
    }

    // MARK: UI state

    private func setupDeviceMenuItems() {
        devicesItem.submenu = NSMenu(title: devicesItem.title)
        devicesItem.submenu?.delegate = self
        let items = [powerOffItem, disconnectItem, devicesItem, reconnectItem, NSMenuItem.separator()]
        items.enumerated().forEach { index, item in
            item.target = self
            statusMenu.insertItem(item, at: index)
        }
        updateDeviceMenuState()
    }

    private func updateDeviceMenuState() {
        let mode = sleepMode
        powerOffItem.state = mode == .powerOff ? .on : .off
        disconnectItem.state = mode == .disconnectDevices ? .on : .off
        reconnectItem.state = reconnectOnWake ? .on : .off
        reconnectItem.isEnabled = mode == .disconnectDevices
    }

    /// Rebuilds the device list each time the submenu opens, so it reflects the current paired devices.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === devicesItem.submenu else { return }
        menu.removeAllItems()

        let selected = selectedDevices
        var names = selected
        for device in pairedDevices() {
            if let address = device.addressString {
                names[address] = device.name ?? address
            }
        }

        if names.isEmpty {
            let empty = NSMenuItem(title: "No paired devices", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        names.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
            .forEach { address, name in
                let item = NSMenuItem(title: name, action: #selector(deviceClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = address
                item.state = selected[address] != nil ? .on : .off
                menu.addItem(item)
            }
    }

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
