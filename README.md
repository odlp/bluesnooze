![Bluesnooze logo](images/icon.png)

# Bluesnooze

[Download the latest release][download-latest] or install via Homebrew:

```sh
# Latest homebrew:
brew install bluesnooze

# Homebrew 2.5 or below
brew cask install bluesnooze
```

## About

**Bluesnooze prevents your sleeping Mac from connecting to Bluetooth accessories.**

If you pair Bluetooth headphones or speakers with both your phone & Mac it can be frustrating when your sleeping Mac connects intermittently and disrupts the audio.

With Bluesnooze the Bluetooth connection is switched off when your Mac sleeps, and switched on when your Mac wakes.

![Screenshot showing Bluesnooze in the status bar](images/screenshot.png)

You might also want to check-out Whisper –  [the volume limiter for MacOS](https://apps.apple.com/gb/app/whisper-volume-limiter/id1438132944?mt=12).

## Installation

1. Download `Bluesnooze.zip` from the [latest release][download-latest]
1. In Finder, open `Bluesnooze.zip` in your `Downloads` directory
1. Drag `Bluesnooze.app` to your `Applications` directory
1. *Optional*: Configure 'Launch at login'

## Caveats

- The app has an option to hide the icon from the status bar. To undo this setting run the following in your terminal: 
    ```sh
    defaults delete com.oliverpeate.Bluesnooze hideIcon && killall -9 Bluesnooze
    ```
    > Note: After executing this command, you will need to start the app again.

- Please note this app is not compatible with the “Allow your Apple Watch to unlock your Mac” feature.
- Unfortunately this app can't be distributed via the App Store because it uses a private API to switch Bluetooth on/off (but the release version is notarized by Apple).

[download-latest]: https://github.com/odlp/bluesnooze/releases/latest

## Enjoying Bluesnooze?

Perhaps you could [buy me a coffee](https://www.buymeacoffee.com/odlp) to say thanks :coffee:
