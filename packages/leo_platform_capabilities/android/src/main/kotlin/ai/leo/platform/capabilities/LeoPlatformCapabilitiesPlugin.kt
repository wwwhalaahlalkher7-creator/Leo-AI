package ai.leo.platform.capabilities

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.CalendarContract
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.nio.charset.CodingErrorAction
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Android adapter. Leo's consent dialog is shown in Flutter before any
 * dangerous permission request reaches this class. */
class LeoPlatformCapabilitiesPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL = "ai.leo/platform_capabilities"
        private const val PERMISSION_REQUEST = 4107
        private const val PICK_REQUEST = 4108
        private const val WORKSPACE_PICK_REQUEST = 4109
        private const val MAX_WORKSPACE_TEXT_BYTES = 16 * 1024
        private const val MAX_WORKSPACE_PREVIEW_BYTES = 64 * 1024
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingActivityResult: MethodChannel.Result? = null
    private var pendingWorkspaceResult: MethodChannel.Result? = null
    private val workspaceRoots = linkedMapOf<String, Uri>()
    private val selectedDocumentUris = linkedSetOf<String>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingPermissionResult?.error("detached", "Plugin detached", null)
        pendingActivityResult?.error("detached", "Plugin detached", null)
        pendingWorkspaceResult?.error("detached", "Plugin detached", null)
        pendingPermissionResult = null
        pendingActivityResult = null
        pendingWorkspaceResult = null
        workspaceRoots.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatform" -> result.success("android")
            "checkOsPermission" -> {
                val capabilityId = call.argument<String>("capabilityId") ?: ""
                result.success(checkPermission(capabilityId))
            }
            "requestOsPermission" -> {
                val capabilityId = call.argument<String>("capabilityId") ?: ""
                requestPermission(capabilityId, result)
            }
            "executeCapability" -> executeCapability(call, result)
            else -> result.notImplemented()
        }
    }

    private fun requiredPermission(capabilityId: String): String? = when (capabilityId) {
        "audio.microphone" -> Manifest.permission.RECORD_AUDIO
        "contacts.read" -> Manifest.permission.READ_CONTACTS
        "phone.call_direct" -> Manifest.permission.CALL_PHONE
        else -> null
    }

    private fun checkPermission(capabilityId: String): Boolean {
        val current = activity ?: return false
        val permission = requiredPermission(capabilityId) ?: return true
        return current.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(capabilityId: String, result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error("no_activity", "An Android Activity is required", null)
            return
        }
        val permission = requiredPermission(capabilityId)
        if (permission == null) {
            // SAF, dialer and application handoffs are scoped OS interactions,
            // not broad runtime permissions.
            result.success(true)
            return
        }
        if (current.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_in_progress", "Another permission request is active", null)
            return
        }
        pendingPermissionResult = result
        current.requestPermissions(arrayOf(permission), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    private fun executeCapability(call: MethodCall, result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error("no_activity", "An Android Activity is required", null)
            return
        }
        val operation = call.argument<String>("operation") ?: ""
        @Suppress("UNCHECKED_CAST")
        val args = call.argument<Map<String, Any?>> ("arguments") ?: emptyMap()
        try {
            when (operation) {
                "openDialer" -> {
                    val number = args["number"]?.toString()?.trim().orEmpty()
                    if (!isSafePhoneNumber(number)) return result.error("invalid_number", "A valid phone number is required", null)
                    current.startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", number, null)))
                    result.success(mapOf("success" to true, "handoff" to "dialer"))
                }
                "composeEmail" -> {
                    val to = args["to"]?.toString()?.trim().orEmpty()
                    val subject = args["subject"]?.toString().orEmpty()
                    val body = args["body"]?.toString().orEmpty()
                    if (to.length > 254 || !Regex("^[^\\s@]+@[^\\s@]+$").matches(to) ||
                        subject.length > 998 || body.length > 8192 ||
                        to.contains('\u0000') || subject.contains('\u0000') || body.contains('\u0000') ||
                        to.any { it.code < 0x20 || it.code == 0x7f } ||
                        subject.any { it.code < 0x20 || it.code == 0x7f } ||
                        body.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
                        return result.error("invalid_mail_draft", "Mail draft values are invalid or exceed their size limits", null)
                    }
                    val mailUri = Uri.fromParts("mailto", to, null)
                    val intent = Intent(Intent.ACTION_SENDTO, mailUri).apply {
                        putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                        putExtra(Intent.EXTRA_TEXT, body)
                    }
                    current.startActivity(Intent.createChooser(intent, "إرسال عبر تطبيق البريد"))
                    result.success(mapOf("success" to true, "handoff" to "mail_app"))
                }
                "composeMessage" -> {
                    val number = args["number"]?.toString()?.trim().orEmpty()
                    val body = args["body"]?.toString().orEmpty()
                    if (!isSafePhoneNumber(number)) return result.error("invalid_number", "A valid destination number is required", null)
                    if (body.length > 4096 || body.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
                        return result.error("invalid_message_draft", "Message draft is invalid or exceeds the allowed size", null)
                    }
                    val intent = Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", number, null))
                    intent.putExtra("sms_body", body)
                    current.startActivity(Intent.createChooser(intent, "إرسال عبر تطبيق الرسائل"))
                    result.success(mapOf("success" to true, "handoff" to "messaging_app"))
                }
                "pickFile" -> launchPicker(result)
                "readTextFile" -> readTextFile(current, args["uri"]?.toString().orEmpty(), result)
                "openSelectedFile" -> openSelectedFile(current, args["uri"]?.toString().orEmpty(), result)
                "createCalendarEventDraft" -> createCalendarEventDraft(current, args, result)
                "copyText" -> copyTextToClipboard(current, args["content"]?.toString().orEmpty(), result)
                "pickWorkspace" -> launchWorkspacePicker(current, result)
                "previewWorkspaceWrite" -> previewWorkspaceWrite(current, args, result)
                "applyWorkspaceWrite" -> applyWorkspaceWrite(current, args, result)
                "releaseWorkspace" -> {
                    workspaceRoots.remove(args["workspaceToken"]?.toString().orEmpty())
                    result.success(mapOf("success" to true))
                }
                "launchApp" -> {
                    val packageName = args["packageName"]?.toString()?.trim().orEmpty()
                    if (packageName.length > 255 || !Regex("^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+$").matches(packageName)) {
                        return result.error("invalid_package", "A valid application package is required", null)
                    }
                    val intent = current.packageManager.getLaunchIntentForPackage(packageName)
                        ?: return result.error("app_unavailable", "The app is not visible or has no launch activity", null)
                    current.startActivity(intent)
                    result.success(mapOf("success" to true, "packageName" to packageName))
                }
                "openUrl" -> {
                    val raw = args["url"]?.toString()?.trim().orEmpty()
                    val uri = Uri.parse(raw)
                    val scheme = uri.scheme?.lowercase()
                    if (raw.length > 2048 || scheme !in setOf("http", "https") ||
                        uri.host.isNullOrEmpty() || uri.encodedUserInfo != null ||
                        raw.any { it.code < 0x20 || it.code == 0x7f }) {
                        return result.error("scheme_blocked", "Generic link opening accepts valid HTTP/HTTPS URLs only", null)
                    }
                    current.startActivity(Intent(Intent.ACTION_VIEW, uri.buildUpon().scheme(scheme).build()))
                    result.success(mapOf("success" to true, "scheme" to uri.scheme))
                }
                "readContacts" -> readContacts(current, result)
                else -> result.error("unsupported_operation", "This operation is not implemented on Android Alpha", operation)
            }
        } catch (error: Exception) {
            result.error("native_operation_failed", error.message ?: "Native operation failed", null)
        }
    }

    private fun launchPicker(result: MethodChannel.Result) {
        val current = activity ?: return result.error("no_activity", "An Activity is required", null)
        if (pendingActivityResult != null) return result.error("picker_in_progress", "A picker is already open", null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
        }
        pendingActivityResult = result
        current.startActivityForResult(intent, PICK_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == WORKSPACE_PICK_REQUEST) {
            val callback = pendingWorkspaceResult
            pendingWorkspaceResult = null
            if (callback == null) return true
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(mapOf("success" to false, "cancelled" to true))
                return true
            }
            val current = activity
            if (current == null) {
                callback.error("no_activity", "The activity was detached while choosing the workspace", null)
                return true
            }
            val grantedFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            val requiredFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            if ((grantedFlags and requiredFlags) != requiredFlags) {
                callback.error("workspace_permission_missing", "The document provider did not grant both read and write access", null)
                return true
            }
            val treeUri = data.data!!
            val token = UUID.randomUUID().toString().replace("-", "")
            workspaceRoots[token] = treeUri
            val workspaceLabel = runCatching {
                current.contentResolver.query(
                    rootDocumentUri(treeUri),
                    arrayOf(Document.COLUMN_DISPLAY_NAME),
                    null, null, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            }.getOrNull()?.takeIf { !it.isNullOrBlank() } ?: "المجلد المحدد"
            while (workspaceRoots.size > 8) {
                workspaceRoots.remove(workspaceRoots.keys.first())
            }
            callback.success(mapOf(
                "success" to true,
                "cancelled" to false,
                "workspaceToken" to token,
                "workspaceLabel" to workspaceLabel
            ))
            return true
        }
        if (requestCode != PICK_REQUEST) return false
        val callback = pendingActivityResult
        pendingActivityResult = null
        if (callback == null) return true
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(mapOf("cancelled" to true))
            return true
        }
        val uri = data.data!!
        selectedDocumentUris.add(uri.toString())
        while (selectedDocumentUris.size > 64) {
            selectedDocumentUris.remove(selectedDocumentUris.first())
        }
        // Alpha reads selected documents only during the active app session.
        // Do not take a persistable grant: revoking Leo's scoped consent should
        // not leave an unnecessary URI permission behind in Android settings.
        callback.success(mapOf(
            "cancelled" to false,
            "kind" to "file",
            "uri" to uri.toString()
        ))
        return true
    }

    private fun readTextFile(current: Activity, rawUri: String, result: MethodChannel.Result) {
        if (!rawUri.startsWith("content://") || rawUri !in selectedDocumentUris) {
            return result.error("invalid_file_uri", "Only a document selected through Leo's picker in this session is accepted", null)
        }
        try {
            val uri = Uri.parse(rawUri)
            val input = current.contentResolver.openInputStream(uri)
                ?: return result.error("file_unavailable", "The selected document is unavailable", null)
            val output = ByteArrayOutputStream()
            input.use { stream ->
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val count = stream.read(buffer)
                    if (count <= 0) break
                    total += count
                    if (total > 2 * 1024 * 1024) {
                        return result.error("file_too_large", "Text preview is limited to 2 MiB", null)
                    }
                    output.write(buffer, 0, count)
                }
            }
            val fileBytes = output.toByteArray()
            if (fileBytes.any { it == 0.toByte() }) {
                return result.error("not_plain_text", "Selected file contains NUL bytes and is not treated as plain text", null)
            }
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            val text = decoder.decode(java.nio.ByteBuffer.wrap(fileBytes)).toString()
            result.success(mapOf("success" to true, "text" to text, "bytes" to output.size()))
        } catch (error: Exception) {
            result.error("file_read_failed", error.message ?: "Unable to read selected document", null)
        }
    }


    private fun openSelectedFile(current: Activity, rawUri: String, result: MethodChannel.Result) {
        if (!rawUri.startsWith("content://") || rawUri !in selectedDocumentUris) {
            return result.error("invalid_file_uri", "Only a file selected through Leo's picker in this session can be opened", null)
        }
        val uri = Uri.parse(rawUri)
        val displayName = runCatching {
            current.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull().orEmpty()
        val extension = displayName.substringAfterLast('.', "").lowercase()
        val allowedExtensions = setOf(
            "pdf", "txt", "md", "csv", "json", "xml", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "jpg", "jpeg", "png", "gif", "webp", "mp3", "wav", "ogg", "m4a", "mp4", "mov"
        )
        if (extension !in allowedExtensions) {
            return result.error("file_type_blocked", "This file type is not opened automatically by Leo", null)
        }
        val providerMimeType = current.contentResolver.getType(uri)
            ?.takeIf { Regex("^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$").matches(it) }
            ?.lowercase()
        val blockedMimeTypes = setOf(
            "text/html", "application/xhtml+xml", "image/svg+xml",
            "application/javascript", "text/javascript", "application/x-javascript",
            "application/vnd.android.package-archive", "application/java-archive",
            "application/x-msdownload", "application/x-dosexec", "application/x-executable",
            "application/x-sh", "application/x-bat", "application/x-msi",
        )
        val mimeLooksActive = providerMimeType?.let { mime ->
            mime in blockedMimeTypes || mime.contains("javascript") || mime.contains("executable")
        } == true
        if (mimeLooksActive) {
            return result.error("file_mime_blocked", "The selected document's content type is not opened automatically by Leo", null)
        }
        val acceptedMimeTypes = when (extension) {
            "pdf" -> setOf("application/pdf", "application/x-pdf")
            "txt" -> setOf("text/plain")
            "md" -> setOf("text/markdown", "text/plain")
            "csv" -> setOf("text/csv", "text/plain", "application/csv")
            "json" -> setOf("application/json", "text/json", "text/plain")
            "xml" -> setOf("application/xml", "text/xml", "text/plain")
            "doc" -> setOf("application/msword")
            "docx" -> setOf("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
            "xls" -> setOf("application/vnd.ms-excel")
            "xlsx" -> setOf("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            "ppt" -> setOf("application/vnd.ms-powerpoint")
            "pptx" -> setOf("application/vnd.openxmlformats-officedocument.presentationml.presentation")
            "jpg", "jpeg" -> setOf("image/jpeg")
            "png" -> setOf("image/png")
            "gif" -> setOf("image/gif")
            "webp" -> setOf("image/webp")
            "mp3" -> setOf("audio/mpeg", "audio/mp3")
            "wav" -> setOf("audio/wav", "audio/x-wav")
            "ogg" -> setOf("audio/ogg", "application/ogg")
            "m4a" -> setOf("audio/mp4", "audio/x-m4a")
            "mp4" -> setOf("video/mp4")
            "mov" -> setOf("video/quicktime")
            else -> return result.error("file_type_blocked", "The selected file type is not supported", null)
        }
        if (providerMimeType != null && providerMimeType != "application/octet-stream" &&
            providerMimeType !in acceptedMimeTypes) {
            return result.error("file_mime_mismatch", "The provider's content type does not match this file extension", null)
        }
        val resolvedType = providerMimeType
            ?.takeIf { it != "application/octet-stream" && it in acceptedMimeTypes }
            ?: acceptedMimeTypes.first()
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, resolvedType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(current.contentResolver, "Leo selected document", uri)
        }
        current.startActivity(Intent.createChooser(intent, "فتح الملف بالتطبيق المناسب"))
        result.success(mapOf("success" to true, "handoff" to "document_viewer"))
    }

    private fun createCalendarEventDraft(
        current: Activity,
        args: Map<String, Any?>,
        result: MethodChannel.Result
    ) {
        val title = args["title"]?.toString().orEmpty()
        val description = args["description"]?.toString().orEmpty()
        val location = args["location"]?.toString().orEmpty()
        val begin = (args["startEpochMs"] as? Number)?.toLong()
            ?: return result.error("invalid_event_time", "Calendar start time is invalid", null)
        val end = (args["endEpochMs"] as? Number)?.toLong()
            ?: return result.error("invalid_event_time", "Calendar end time is invalid", null)
        if (title.isBlank() || title.length > 200 || description.length > 2048 || location.length > 300 ||
            begin <= 0L || end <= begin || end - begin > 7L * 24L * 60L * 60L * 1000L ||
            listOf(title, location).any { value -> value.any { it.code < 0x20 || it.code == 0x7f } } ||
            description.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
            return result.error("invalid_calendar_event", "Calendar event details are invalid or exceed the allowed limits", null)
        }
        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, title)
            putExtra(CalendarContract.Events.DESCRIPTION, description)
            putExtra(CalendarContract.Events.EVENT_LOCATION, location)
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
        }
        current.startActivity(Intent.createChooser(intent, "اختيار تطبيق التقويم"))
        result.success(mapOf("success" to true, "handoff" to "calendar_event_draft"))
    }

    private fun copyTextToClipboard(current: Activity, content: String, result: MethodChannel.Result) {
        if (content.toByteArray(Charsets.UTF_8).size > 16 * 1024 || content.length > 10000 ||
            content.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
            return result.error("clipboard_text_invalid", "Clipboard text is invalid or exceeds the allowed size", null)
        }
        val clipboard = current.getSystemService(Activity.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return result.error("clipboard_unavailable", "Android clipboard service is unavailable", null)
        clipboard.setPrimaryClip(ClipData.newPlainText("Leo", content))
        result.success(mapOf("success" to true, "characters" to content.length))
    }

    private fun launchWorkspacePicker(current: Activity, result: MethodChannel.Result) {
        if (pendingWorkspaceResult != null || pendingActivityResult != null) {
            return result.error("picker_in_progress", "Another system picker is already open", null)
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        pendingWorkspaceResult = result
        current.startActivityForResult(intent, WORKSPACE_PICK_REQUEST)
    }

    private fun safeWorkspaceFileName(raw: String): Boolean {
        if (raw.isBlank() || raw != raw.trim() || raw.toByteArray(Charsets.UTF_8).size > 160 || raw == "." || raw == "..") return false
        if (raw.contains('/') || raw.contains('\\') || raw.contains(':') ||
            raw.endsWith('.') || raw.endsWith(' ')) return false
        if (raw.any { it.code < 0x20 || it.code == 0x7f || it in "<>\"|?*" }) return false
        val device = raw.substringBefore('.').uppercase()
        if (device in setOf("CON", "PRN", "AUX", "NUL") ||
            Regex("^(COM|LPT)[1-9]$").matches(device)) return false
        return true
    }

    private fun workspaceRoot(token: String): Uri? {
        if (!Regex("^[a-fA-F0-9]{32}$").matches(token)) return null
        return workspaceRoots[token]
    }

    private fun rootDocumentUri(treeUri: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )

    private fun findWorkspaceChild(
        current: Activity,
        treeUri: Uri,
        parentDocumentUri: Uri,
        displayName: String
    ): Uri? {
        val parentId = DocumentsContract.getDocumentId(parentDocumentUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        var match: Uri? = null
        current.contentResolver.query(
            childrenUri,
            arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS),
            null, null, null
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndex(Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndex(Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndex(Document.COLUMN_MIME_TYPE)
            val flagsColumn = cursor.getColumnIndex(Document.COLUMN_FLAGS)
            while (cursor.moveToNext()) {
                val name = if (nameColumn >= 0) cursor.getString(nameColumn) else null
                if (name != displayName) continue
                if (match != null) {
                    throw IllegalStateException("The document provider returned duplicate names; refusing an ambiguous write")
                }
                val mime = if (mimeColumn >= 0) cursor.getString(mimeColumn) else null
                val flags = if (flagsColumn >= 0) cursor.getLong(flagsColumn) else 0L
                if (mime == Document.MIME_TYPE_DIR ||
                    (flags and Document.FLAG_VIRTUAL_DOCUMENT.toLong()) != 0L) {
                    throw IllegalArgumentException("The target is a directory or virtual document")
                }
                val documentId = if (idColumn >= 0) cursor.getString(idColumn) else null
                if (documentId.isNullOrBlank()) throw IllegalStateException("Missing document identifier")
                match = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            }
        } ?: throw IllegalStateException("The selected document provider did not return a workspace listing")
        return match
    }

    private fun workspaceDocumentName(current: Activity, uri: Uri): String? =
        current.contentResolver.query(
            uri,
            arrayOf(Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }

    private fun readWorkspaceBytes(current: Activity, uri: Uri): ByteArray {
        val output = ByteArrayOutputStream()
        val input = current.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The target file cannot be opened")
        input.use { stream ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = stream.read(buffer)
                if (count <= 0) break
                if (output.size() + count > MAX_WORKSPACE_PREVIEW_BYTES) {
                    throw IllegalArgumentException("The existing file exceeds the 64 KiB preview limit")
                }
                output.write(buffer, 0, count)
            }
        }
        val bytes = output.toByteArray()
        if (bytes.any { it == 0.toByte() }) {
            throw IllegalArgumentException("Binary files cannot be replaced by the text editor")
        }
        val decoded = decodeWorkspaceText(bytes)
        if (decoded.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
            throw IllegalArgumentException("Files with unsupported control characters cannot be replaced as text")
        }
        return bytes
    }

    private fun decodeWorkspaceText(bytes: ByteArray): String {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return decoder.decode(ByteBuffer.wrap(bytes)).toString()
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun previewWorkspaceWrite(
        current: Activity,
        args: Map<String, Any?>,
        result: MethodChannel.Result
    ) {
        try {
            val token = args["workspaceToken"]?.toString().orEmpty()
            val treeUri = workspaceRoot(token)
                ?: return result.error("workspace_expired", "The selected workspace has expired; choose it again", null)
            val name = args["relativePath"]?.toString().orEmpty()
            val proposedText = args["content"]?.toString() ?: ""
            if (!safeWorkspaceFileName(name) || proposedText.codePointCount(0, proposedText.length) > 10_000 ||
                proposedText.toByteArray(Charsets.UTF_8).size > MAX_WORKSPACE_TEXT_BYTES ||
                proposedText.contains('\u0000') || proposedText.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
                return result.error("invalid_workspace_write", "The proposed filename or text is invalid or too large", null)
            }
            val proposedBytes = proposedText.toByteArray(Charsets.UTF_8)
            val rootUri = rootDocumentUri(treeUri)
            val targetUri = findWorkspaceChild(current, treeUri, rootUri, name)
            val oldBytes = if (targetUri == null) ByteArray(0) else readWorkspaceBytes(current, targetUri)
            val oldText = decodeWorkspaceText(oldBytes)
            result.success(mapOf(
                "success" to true,
                "exists" to (targetUri != null),
                "currentContent" to oldText,
                "currentHash" to if (targetUri == null) "" else sha256(oldBytes),
                "proposedHash" to sha256(proposedBytes),
                "bytes" to proposedBytes.size
            ))
        } catch (error: Exception) {
            result.error("workspace_preview_failed", error.message ?: "Unable to preview the workspace file", null)
        }
    }

    private fun applyWorkspaceWrite(
        current: Activity,
        args: Map<String, Any?>,
        result: MethodChannel.Result
    ) {
        var stageUri: Uri? = null
        var backupUri: Uri? = null
        var targetName = ""
        var targetUri: Uri? = null
        var treeUri: Uri? = null
        var rootUri: Uri? = null
        try {
            val token = args["workspaceToken"]?.toString().orEmpty()
            treeUri = workspaceRoot(token)
                ?: return result.error("workspace_expired", "The selected workspace has expired; choose it again", null)
            targetName = args["relativePath"]?.toString().orEmpty()
            val content = args["content"]?.toString() ?: ""
            val expectedHash = args["expectedHash"]?.toString() ?: ""
            val expectedNewHash = args["expectedNewHash"]?.toString() ?: ""
            val newBytes = content.toByteArray(Charsets.UTF_8)
            if (!safeWorkspaceFileName(targetName) || content.codePointCount(0, content.length) > 10_000 ||
                newBytes.size > MAX_WORKSPACE_TEXT_BYTES ||
                content.contains('\u0000') || content.any { it.code == 0x7f || (it.code < 0x20 && it != '\t' && it != '\r' && it != '\n') }) {
                return result.error("invalid_workspace_write", "The proposed filename or text is invalid or too large", null)
            }
            rootUri = rootDocumentUri(treeUri)
            targetUri = findWorkspaceChild(current, treeUri, rootUri, targetName)
            val currentBytes = if (targetUri == null) ByteArray(0) else readWorkspaceBytes(current, targetUri!!)
            val currentHash = if (targetUri == null) "" else sha256(currentBytes)
            val newHash = sha256(newBytes)
            if (currentHash != expectedHash || !Regex("^[a-f0-9]{64}$").matches(expectedNewHash) ||
                newHash != expectedNewHash) {
                return result.error("workspace_conflict", "The file changed after preview. Review a fresh preview before writing", null)
            }

            val stageName = "Leo-Stage-${UUID.randomUUID()}.tmp"
            stageUri = DocumentsContract.createDocument(current.contentResolver, rootUri!!, "text/plain", stageName)
                ?: return result.error("workspace_stage_failed", "The document provider cannot create a staging file", null)
            val output = current.contentResolver.openOutputStream(stageUri!!, "w")
                ?: throw IllegalStateException("The staging file cannot be written")
            output.use { it.write(newBytes); it.flush() }

            if (targetUri != null) {
                // Re-read after staging immediately before renaming the original.
                // SAF providers do not expose a compare-and-swap rename API, so
                // this narrows (but cannot eliminate) the provider-level race.
                val latestTarget = findWorkspaceChild(current, treeUri!!, rootUri!!, targetName)
                    ?: throw IllegalStateException("The target disappeared after preview")
                if (sha256(readWorkspaceBytes(current, latestTarget)) != expectedHash) {
                    throw IllegalStateException("The file changed while staging; request a new preview")
                }
                targetUri = latestTarget
                val backupName = "Leo-Backup-${UUID.randomUUID()}.tmp"
                backupUri = DocumentsContract.renameDocument(current.contentResolver, targetUri!!, backupName)
                    ?: throw IllegalStateException("The selected provider cannot atomically stage the previous file; no content was replaced")
                val promoted = DocumentsContract.renameDocument(current.contentResolver, stageUri!!, targetName)
                    ?: throw IllegalStateException("The provider could not promote the staged file")
                stageUri = promoted
                if (workspaceDocumentName(current, promoted) != targetName) {
                    throw IllegalStateException("The provider changed the target filename; refusing an unexpected write")
                }
                val verified = readWorkspaceBytes(current, promoted)
                if (sha256(verified) != newHash) {
                    throw IllegalStateException("Post-write verification failed; the previous file will be restored")
                }
                stageUri = null
                if (!DocumentsContract.deleteDocument(current.contentResolver, backupUri!!)) {
                    // The content is already verified and committed. Leave the backup
                    // in place rather than reporting failure and inviting a retry.
                    result.success(mapOf(
                        "success" to true,
                        "created" to false,
                        "updated" to true,
                        "bytes" to newBytes.size,
                        "sha256" to newHash,
                        "message" to "تم التعديل والتحقق منه، لكن تعذر حذف النسخة الاحتياطية Leo-Backup؛ يمكنك حذفها يدوياً بعد مراجعتها."
                    ))
                    workspaceRoots.remove(token)
                    backupUri = null
                    return
                }
                backupUri = null
            } else {
                if (findWorkspaceChild(current, treeUri!!, rootUri!!, targetName) != null) {
                    throw IllegalStateException("A file appeared after preview; no overwrite was attempted")
                }
                val promoted = DocumentsContract.renameDocument(current.contentResolver, stageUri!!, targetName)
                    ?: throw IllegalStateException("The provider cannot safely rename the staged file; no file was created")
                stageUri = promoted
                if (workspaceDocumentName(current, promoted) != targetName) {
                    throw IllegalStateException("The provider changed the target filename; refusing an unexpected write")
                }
                val verified = readWorkspaceBytes(current, promoted)
                if (sha256(verified) != newHash) {
                    throw IllegalStateException("Post-write verification failed; the staged file will be removed")
                }
                stageUri = null
            }
            workspaceRoots.remove(token)
            result.success(mapOf(
                "success" to true,
                "created" to (expectedHash.isEmpty()),
                "updated" to expectedHash.isNotEmpty(),
                "bytes" to newBytes.size,
                "sha256" to newHash
            ))
        } catch (error: Exception) {
            var failureMessage = error.message ?: "Unable to safely write the workspace file"
            if (stageUri != null) {
                val removed = runCatching {
                    DocumentsContract.deleteDocument(current.contentResolver, stageUri!!)
                }.getOrDefault(false)
                if (!removed) failureMessage += "; the staged Leo file may remain in the selected folder"
            }
            if (backupUri != null && targetName.isNotEmpty()) {
                val restored = runCatching {
                    DocumentsContract.renameDocument(current.contentResolver, backupUri!!, targetName)
                }.getOrNull()
                if (restored == null) {
                    failureMessage += "; previous content remains in the selected folder as a Leo-Backup file"
                } else {
                    backupUri = null
                }
            }
            result.error("workspace_write_failed", failureMessage, null)
        }
    }


    private fun isSafePhoneNumber(value: String): Boolean =
        value.length in 1..32 && Regex("^[0-9+*#(). -]{1,32}$").matches(value.trim())

    private fun readContacts(current: Activity, result: MethodChannel.Result) {
        if (!checkPermission("contacts.read")) {
            return result.error("permission_required", "Contacts permission is not granted", null)
        }
        val rows = mutableListOf<Map<String, String>>()
        val cursor = current.contentResolver.query(
            android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER
            ), null, null,
            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
        )
        cursor?.use {
            val nameColumn = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberColumn = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (it.moveToNext() && rows.size < 500) {
                rows.add(mapOf(
                    "name" to (if (nameColumn >= 0) it.getString(nameColumn) else ""),
                    "number" to (if (numberColumn >= 0) it.getString(numberColumn) else "")
                ))
            }
        }
        result.success(mapOf("success" to true, "contacts" to rows, "truncated" to (rows.size == 500)))
    }
}
