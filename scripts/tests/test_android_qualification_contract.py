from __future__ import annotations

import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from verify_android_apk import (  # noqa: E402
    AndroidApkValidationError,
    validate_android_apk,
)
from verify_android_runner import (  # noqa: E402
    AndroidRunnerValidationError,
    validate_android_runner,
)

ANDROID_NS = "http://schemas.android.com/apk/res/android"


def fake_arm64_elf(machine: int = 183, alignment: int = 16384) -> bytes:
    # ELF64 header plus one PT_LOAD header, with e_phoff=64/e_phentsize=56.
    image = bytearray(120)
    image[:4] = b"\x7fELF"
    image[4] = 2  # ELFCLASS64
    image[5] = 1  # little endian
    image[6] = 1  # current ELF version
    image[18:20] = machine.to_bytes(2, "little")
    image[32:40] = (64).to_bytes(8, "little")
    image[54:56] = (56).to_bytes(2, "little")
    image[56:58] = (1).to_bytes(2, "little")
    image[64:68] = (1).to_bytes(4, "little")  # PT_LOAD
    image[112:120] = alignment.to_bytes(8, "little")  # p_align
    return bytes(image)


def create_fake_apk(path: Path, *, wrong_abi: bool = False, wrong_arch: bool = False,
                    include_model: bool = False, omit_adapter: bool = False,
                    wrong_alignment: bool = False,
                    third_party_bad_alignment: bool = False) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        if not omit_adapter:
            archive.writestr(
                "lib/arm64-v8a/libleo_llama_backend.so",
                fake_arm64_elf(62 if wrong_arch else 183, 4096 if wrong_alignment else 16384),
            )
        archive.writestr("lib/arm64-v8a/libc++_shared.so", fake_arm64_elf())
        archive.writestr("lib/arm64-v8a/libflutter.so", fake_arm64_elf())
        if third_party_bad_alignment:
            archive.writestr(
                "lib/arm64-v8a/libsherpa-onnx-c-api.so",
                fake_arm64_elf(alignment=4096),
            )
        if wrong_abi:
            archive.writestr("lib/x86_64/libforeign.so", fake_arm64_elf())
        if include_model:
            archive.writestr("assets/models/test.gguf", b"not-a-real-model")
        archive.writestr("AndroidManifest.xml", b"binary-xml-placeholder")


def create_runner_fixture(root: Path) -> Path:
    app_dir = root / "apps" / "leo_app"
    android_app = app_dir / "android" / "app"
    manifest_dir = android_app / "src" / "main"
    rules_dir = manifest_dir / "res" / "xml"
    rules_dir.mkdir(parents=True)
    gradle = '''plugins { id("com.android.application") }
android {
    namespace = "ai.leo.leo_app"
    compileSdk = 36
    ndkVersion = "30.0.16248370"
    defaultConfig {
        applicationId = "ai.leo.leo_app"
        minSdk = 28
    }
}
'''
    (android_app / "build.gradle.kts").write_text(gradle, encoding="utf-8")
    (app_dir / "android" / "settings.gradle.kts").write_text(
        'plugins { id("com.android.application") version "9.1.0" apply false }\n',
        encoding="utf-8",
    )
    wrapper_dir = app_dir / "android" / "gradle" / "wrapper"
    wrapper_dir.mkdir(parents=True)
    (wrapper_dir / "gradle-wrapper.properties").write_text(
        "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.3.1-bin.zip\n",
        encoding="utf-8",
    )
    with zipfile.ZipFile(wrapper_dir / "gradle-wrapper.jar", "w") as wrapper_jar:
        wrapper_jar.writestr("org/gradle/wrapper/GradleWrapperMain.class", b"fixture-class")
    (app_dir / "android" / "gradlew").write_text("#!/bin/sh\n", encoding="utf-8")
    (app_dir / "android" / "gradlew").chmod(0o755)
    (app_dir / "android" / "gradlew.bat").write_text("@echo off\n", encoding="utf-8")
    (app_dir / "android" / "gradle.properties").write_text(
        "android.builtInKotlin=false\nandroid.newDsl=false\n", encoding="utf-8"
    )
    manifest = f'''<manifest xmlns:android="{ANDROID_NS}">
    <application android:label="Leo" android:allowBackup="false"
        android:fullBackupContent="@xml/leo_backup_rules"
        android:dataExtractionRules="@xml/leo_data_extraction_rules" />
</manifest>
'''
    (manifest_dir / "AndroidManifest.xml").write_text(manifest, encoding="utf-8")
    (rules_dir / "leo_backup_rules.xml").write_text(
        '''<full-backup-content>
            <exclude domain="sharedpref" path="." />
        </full-backup-content>''', encoding="utf-8"
    )
    (rules_dir / "leo_data_extraction_rules.xml").write_text(
        '''<data-extraction-rules>
            <cloud-backup><exclude domain="sharedpref" path="." /></cloud-backup>
            <device-transfer><exclude domain="sharedpref" path="." /></device-transfer>
        </data-extraction-rules>''', encoding="utf-8"
    )
    plugin_manifest = root / "packages" / "leo_platform_capabilities" / "android" / "src" / "main" / "AndroidManifest.xml"
    plugin_manifest.parent.mkdir(parents=True)
    plugin_gradle = root / "packages" / "leo_platform_capabilities" / "android" / "build.gradle"
    plugin_gradle.write_text(
        "android {\n    compileSdk 36\n    defaultConfig {\n        minSdk 28\n    }\n}\n",
        encoding="utf-8",
    )
    plugin_manifest.write_text(
        f'''<manifest xmlns:android="{ANDROID_NS}">
            <uses-permission android:name="android.permission.READ_CONTACTS" />
            <queries><intent><action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" /></intent></queries>
        </manifest>''', encoding="utf-8"
    )
    return app_dir


class AndroidQualificationContractTests(unittest.TestCase):
    def test_native_build_enforces_pinned_ndk_and_llama_revision(self):
        script = (ROOT / "scripts/build_android_native.sh").read_text(encoding="utf-8")
        self.assertIn('"30.0.16248370"', script)
        prepare = (ROOT / "scripts/prepare_android_runner.sh").read_text(encoding="utf-8")
        self.assertIn('ndkVersion = "30.0.16248370"', prepare)
        self.assertIn('"cd959bae99ff4bed22bef2604f45241c09bbb8c8"', script)
        self.assertIn("-DANDROID_ABI=arm64-v8a", script)
        self.assertIn("-DANDROID_PLATFORM=android-28", script)
        self.assertIn("compileSdk = 36", prepare)

    def test_android_app_build_runs_runner_and_apk_verification(self):
        script = (ROOT / "scripts/build_android_app.sh").read_text(encoding="utf-8")
        self.assertIn("prepare_android_runner.sh", script)
        self.assertIn("generate_bridge.sh", script)
        self.assertIn("build_android_native.sh", script)
        self.assertIn("verify_android_apk.py", script)
        self.assertIn("LEO_ANDROID_BUILD_MODE", script)
        self.assertIn("release", script)
        runner_script = (ROOT / "scripts/prepare_android_runner.sh").read_text(encoding="utf-8")
        self.assertIn("verify_android_runner.py", runner_script)
        self.assertIn("android/gradle/wrapper/gradle-wrapper.jar", runner_script)

    def test_ci_builds_and_uploads_debug_and_release_arm64_apks(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("LEO_ANDROID_BUILD_MODE: both", workflow)
        self.assertIn("app-debug.apk", workflow)
        self.assertIn("app-release.apk", workflow)
        self.assertIn("flutter-apk/SHA256SUMS.txt", workflow)
        app_builder = (ROOT / "scripts/build_android_app.sh").read_text(encoding="utf-8")
        self.assertIn('sha256sum "${CHECKSUM_FILENAMES[@]}"', app_builder)
        self.assertIn("leo-alpha-android-arm64-qualification", workflow)
        self.assertIn("zipalign", app_builder)
        self.assertIn("-P 16 -v 4", app_builder)
        self.assertIn("libsherpa-onnx", (ROOT / "scripts/tests/test_android_qualification_contract.py").read_text(encoding="utf-8"))

    def test_android_qualification_job_requires_reproducible_committed_locks(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        android_job = workflow.split("  android-app:", 1)[1].split("  windows-app:", 1)[0]
        self.assertIn("needs: full-stack", android_job)
        self.assertIn("Require committed reproducible dependency lockfiles", android_job)
        self.assertIn("LEO_REQUIRE_LOCKFILES: '1'", android_job)
        bridge = (ROOT / "scripts/generate_bridge.sh").read_text(encoding="utf-8")
        self.assertIn("check_dependency_lockfiles.py", bridge)
        self.assertIn("flutter pub get --enforce-lockfile", bridge)
        self.assertIn("cargo metadata --manifest-path", bridge)
        self.assertIn("Native Assets hook cratePath", bridge)
        self.assertIn("native_toolchain_rust must be pinned to 1.1.1", bridge)
        runner = (ROOT / "scripts/prepare_android_runner.sh").read_text(encoding="utf-8")
        self.assertIn("android.builtInKotlin=false", runner)
        self.assertIn("android.newDsl=false", runner)

    def test_removed_bootstrap_workflow_is_not_required_by_ci(self):
        # Bootstrap was retired after generated runner files and lockfiles became
        # part of the normal repository/CI contract. The main CI must not depend
        # on the deleted one-off workflow.
        bootstrap = ROOT / ".github/workflows/prepare_android_bootstrap_files.yml"
        self.assertFalse(bootstrap.exists())
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertNotIn("prepare_android_bootstrap_files.yml", workflow)

    def test_apk_validation_accepts_correct_arm64_native_package(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            apk = Path(temp_dir) / "leo.apk"
            create_fake_apk(apk)
            result = validate_android_apk(apk)
        self.assertEqual(result["abi"], "arm64-v8a")
        self.assertEqual(len(result["sha256"]), 64)
        self.assertIn("lib/arm64-v8a/libleo_llama_backend.so", result["native_libraries"])

    def test_apk_validation_rejects_missing_leo_backend(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            apk = Path(temp_dir) / "missing.apk"
            create_fake_apk(apk, omit_adapter=True)
            with self.assertRaisesRegex(AndroidApkValidationError, "missing required"):
                validate_android_apk(apk)

    def test_apk_validation_rejects_non_arm64_abi_and_wrong_elf_machine(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            wrong_abi_apk = Path(temp_dir) / "wrong-abi.apk"
            create_fake_apk(wrong_abi_apk, wrong_abi=True)
            with self.assertRaisesRegex(AndroidApkValidationError, "Unexpected native ABI"):
                validate_android_apk(wrong_abi_apk)

            wrong_arch_apk = Path(temp_dir) / "wrong-arch.apk"
            create_fake_apk(wrong_arch_apk, wrong_arch=True)
            with self.assertRaisesRegex(AndroidApkValidationError, "AArch64 ELF"):
                validate_android_apk(wrong_arch_apk)


    def test_apk_validation_rejects_native_libraries_with_4kb_load_alignment(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            apk = Path(temp_dir) / "four-kb-aligned.apk"
            create_fake_apk(apk, wrong_alignment=True)
            with self.assertRaisesRegex(AndroidApkValidationError, "not 16 KB aligned"):
                validate_android_apk(apk)

    def test_apk_validation_rejects_unaligned_transitive_voice_engine_library(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            apk = Path(temp_dir) / "unaligned-sherpa.apk"
            create_fake_apk(apk, third_party_bad_alignment=True)
            with self.assertRaisesRegex(
                AndroidApkValidationError,
                r"libsherpa-onnx-c-api\.so.*not 16 KB aligned|not 16 KB aligned.*libsherpa-onnx-c-api\.so",
            ):
                validate_android_apk(apk)

    def test_apk_validation_rejects_bundled_local_model_weights(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            apk = Path(temp_dir) / "bundled-model.apk"
            create_fake_apk(apk, include_model=True)
            with self.assertRaisesRegex(AndroidApkValidationError, "must be imported by the user"):
                validate_android_apk(apk)

    def test_runner_validation_accepts_minimum_sdk_and_backup_security_contract(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            checks = validate_android_runner(app_dir)
        self.assertIn("minSdk=28", checks)
        self.assertIn("application backup disabled", checks)
        self.assertIn("AGP=9.1.0", checks)
        self.assertIn("Gradle=9.3.1", checks)
        self.assertIn("legacy KGP/AGP DSL compatibility enabled", checks)
        self.assertIn("NDK=30.0.16248370", checks)

    def test_runner_validation_rejects_corrupt_or_non_executable_gradle_wrapper(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            wrapper_jar = app_dir / "android/gradle/wrapper/gradle-wrapper.jar"
            wrapper_jar.write_bytes(b"not-a-jar")
            with self.assertRaisesRegex(AndroidRunnerValidationError, "Gradle wrapper JAR is invalid"):
                validate_android_runner(app_dir)

        if os.name != "nt":
            with tempfile.TemporaryDirectory() as temp_dir:
                app_dir = create_runner_fixture(Path(temp_dir))
                (app_dir / "android/gradlew").chmod(0o644)
                with self.assertRaisesRegex(AndroidRunnerValidationError, "must retain its executable bit"):
                    validate_android_runner(app_dir)

    def test_runner_validation_rejects_gradle_too_old_for_agp(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            wrapper = app_dir / "android/gradle/wrapper/gradle-wrapper.properties"
            wrapper.write_text(
                "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0.0-bin.zip\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(AndroidRunnerValidationError, r"Gradle 9.3.1\+ is required"):
                validate_android_runner(app_dir)

    def test_runner_validation_rejects_builtin_kotlin_when_legacy_plugins_exist(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            properties = app_dir / "android/gradle.properties"
            properties.write_text("android.builtInKotlin=true\nandroid.newDsl=false\n", encoding="utf-8")
            with self.assertRaisesRegex(AndroidRunnerValidationError, "android.builtInKotlin=false"):
                validate_android_runner(app_dir)

    def test_runner_validation_rejects_agp_below_16kb_packaging_floor(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            settings = app_dir / "android/settings.gradle.kts"
            settings.write_text(
                'plugins { id("com.android.application") version "8.5.0" apply false }\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(AndroidRunnerValidationError, r"AGP 8.5.1\+"):
                validate_android_runner(app_dir)

    def test_runner_validation_rejects_backup_enabled(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            manifest = app_dir / "android/app/src/main/AndroidManifest.xml"
            content = manifest.read_text(encoding="utf-8").replace('android:allowBackup="false"', 'android:allowBackup="true"')
            manifest.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(AndroidRunnerValidationError, "backup must remain disabled"):
                validate_android_runner(app_dir)

    def test_runner_validation_rejects_broad_permissions(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = create_runner_fixture(Path(temp_dir))
            manifest = app_dir / "android/app/src/main/AndroidManifest.xml"
            content = manifest.read_text(encoding="utf-8").replace(
                "<application", '<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />\n    <application'
            )
            manifest.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(AndroidRunnerValidationError, "Broad Android permission"):
                validate_android_runner(app_dir)

    def test_runner_validation_rejects_broad_package_visibility_queries(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            app_dir = create_runner_fixture(root)
            plugin_manifest = root / "packages/leo_platform_capabilities/android/src/main/AndroidManifest.xml"
            content = plugin_manifest.read_text(encoding="utf-8").replace(
                "</queries>", '<package android:name="com.example.anything" /></queries>'
            )
            plugin_manifest.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(AndroidRunnerValidationError, "single launcher intent"):
                validate_android_runner(app_dir)



if __name__ == "__main__":
    unittest.main()
