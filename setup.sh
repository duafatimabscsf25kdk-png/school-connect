#!/usr/bin/env bash
# Generates the Android platform scaffolding that matches YOUR Flutter version,
# then applies the School Connect manifest and minSdk. Run once.
set -e
cd "$(dirname "$0")"
flutter create --platforms=android --org com.schoolconnect --project-name school_connect .
rm -rf test
cp android_overlay/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && sed -i -E 's/minSdk = flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion flutter\.minSdkVersion/minSdkVersion 24/' "$f"
done
flutter pub get
echo "Done. Build with: flutter build apk --release"
