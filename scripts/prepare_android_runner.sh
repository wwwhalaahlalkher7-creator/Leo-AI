#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/apps/leo_app"

command -v flutter >/dev/null 2>&1 || { echo "ERROR: Flutter SDK is required." >&2; exit 2; }
cd "${APP_DIR}"
if [[ ! -f android/app/build.gradle.kts ]]; then
  flutter create --platforms=android --org ai.leo --project-name leo_app --no-pub .
fi
python3 - <<'PY_ANDROID'
from pathlib import Path
path = Path("android/app/build.gradle.kts")
text = path.read_text(encoding="utf-8")
text = text.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 28")
text = text.replace('ndkVersion = flutter.ndkVersion', 'ndkVersion = "30.0.16248370"')
path.write_text(text, encoding="utf-8")
if "compileSdk = 36" not in text:
    raise SystemExit("Unable to pin the Android compile SDK to API 36.")
if "minSdk = 28" not in text:
    raise SystemExit("Unable to set the Android minimum SDK to API 28.")
if 'ndkVersion = "30.0.16248370"' not in text:
    raise SystemExit("Unable to pin the Android Gradle runner to NDK 30.0.16248370.")

# flutter_secure_storage keeps its encryption key in Android Keystore and its
# encrypted payload in app preferences. Restoring those preferences without
# the corresponding Keystore key can make task checkpoints unreadable.
manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.is_file():
    raise SystemExit("AndroidManifest.xml is missing after runner generation.")
manifest_text = manifest.read_text(encoding="utf-8")
import re
application = re.search(r"<application\b[^>]*>", manifest_text, flags=re.DOTALL)
if application is None:
    raise SystemExit("Android manifest has no application element.")
opening = application.group(0)
if re.search(r"\bandroid:allowBackup\s*=", opening):
    opening = re.sub(r"\bandroid:allowBackup\s*=\s*(['\"])[^'\"]*\1", 'android:allowBackup="false"', opening)
else:
    opening = opening[:-1] + ' android:allowBackup="false">'
# Exclude SharedPreferences from both cloud backup and device-to-device transfer.
opening = re.sub(r"\bandroid:fullBackupContent\s*=\s*(['\"])[^'\"]*\1", 'android:fullBackupContent="@xml/leo_backup_rules"', opening)
if "android:fullBackupContent=" not in opening:
    opening = opening[:-1] + ' android:fullBackupContent="@xml/leo_backup_rules">'
opening = re.sub(r"\bandroid:dataExtractionRules\s*=\s*(['\"])[^'\"]*\1", 'android:dataExtractionRules="@xml/leo_data_extraction_rules"', opening)
if "android:dataExtractionRules=" not in opening:
    opening = opening[:-1] + ' android:dataExtractionRules="@xml/leo_data_extraction_rules">'
manifest_text = manifest_text[:application.start()] + opening + manifest_text[application.end():]
manifest.write_text(manifest_text, encoding="utf-8")
if not re.search(r"<application\b[^>]*\bandroid:allowBackup=\"false\"", manifest_text):
    raise SystemExit("Unable to disable Android backup for secure task storage.")

rules = Path("android/app/src/main/res/xml")
rules.mkdir(parents=True, exist_ok=True)
(rules / "leo_backup_rules.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <exclude domain="sharedpref" path="." />
</full-backup-content>
""", encoding="utf-8")
(rules / "leo_data_extraction_rules.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="sharedpref" path="." />
    </device-transfer>
</data-extraction-rules>
""", encoding="utf-8")
PY_ANDROID
mkdir -p android/app/src/main/jniLibs/arm64-v8a
python3 "${ROOT_DIR}/scripts/verify_android_runner.py" "${APP_DIR}"
