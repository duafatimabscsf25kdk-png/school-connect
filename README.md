# School Connect – Offline Teacher Messenger

Setup (needs internet ONCE, on your computer, to download packages):

    flutter --version        # Flutter 3.24+ / Dart 3.3+
    ./setup.sh               # generates android/ for your Flutter version, applies manifest + minSdk 24
    flutter build apk --release
    # APK: build/app/outputs/flutter-apk/app-release.apk

Install the same APK on every teacher phone and the office phone (adb install, USB copy, or Nearby Share).
