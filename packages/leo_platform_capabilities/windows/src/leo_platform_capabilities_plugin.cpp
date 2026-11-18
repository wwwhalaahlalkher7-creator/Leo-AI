#include "leo_platform_capabilities/leo_platform_capabilities_plugin.h"

#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wrl/client.h>
#include <bcrypt.h>

#include <string>
#include <utility>
#include <fstream>
#include <filesystem>
#include <unordered_set>
#include <iterator>
#include <algorithm>
#include <unordered_map>
#include <vector>
#include <cctype>
#include <chrono>
#include <ctime>
#include <cwctype>

namespace leo_platform_capabilities {
namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
std::unordered_set<std::wstring> g_selected_files;
std::unordered_map<std::string, std::filesystem::path> g_workspace_roots;
constexpr size_t kMaxWorkspaceTextBytes = 16 * 1024;
constexpr size_t kMaxWorkspacePreviewBytes = 64 * 1024;

const EncodableValue* FindValue(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

std::string GetString(const EncodableMap& map, const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr || !std::holds_alternative<std::string>(*value)) return {};
  return std::get<std::string>(*value);
}

std::string NewWorkspaceToken();
std::wstring Utf8ToWide(const std::string& value);
bool IsValidUtf8Text(const std::string& value);
size_t CountUnicodeCodePoints(const std::wstring& value);
bool ShellOpen(const std::wstring& target);

int64_t GetInt64(const EncodableMap& map, const char* key, bool* valid) {
  const auto* value = FindValue(map, key);
  if (value != nullptr) {
    if (const auto* wide = std::get_if<int64_t>(value)) { *valid = true; return *wide; }
    if (const auto* narrow = std::get_if<int32_t>(value)) { *valid = true; return *narrow; }
  }
  *valid = false;
  return 0;
}

bool HasSafeText(const std::string& value, size_t max_bytes, size_t max_characters,
                 bool allow_newlines) {
  if (value.size() > max_bytes || !IsValidUtf8Text(value)) return false;
  const auto wide = Utf8ToWide(value);
  if (CountUnicodeCodePoints(wide) > max_characters) return false;
  return std::none_of(value.begin(), value.end(), [allow_newlines](unsigned char ch) {
    if (ch == 0x7f) return true;
    if (ch < 0x20 && ch != '\t' && !(allow_newlines && (ch == '\r' || ch == '\n'))) return true;
    return false;
  });
}

std::string EscapeIcsText(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size() + 16);
  for (const char ch : value) {
    switch (ch) {
      case '\\': escaped += "\\\\"; break;
      case ',': escaped += "\\,"; break;
      case ';': escaped += "\\;"; break;
      case '\r': break;
      case '\n': escaped += "\\n"; break;
      default: escaped.push_back(ch); break;
    }
  }
  return escaped;
}

bool FormatIcsUtc(int64_t epoch_ms, std::string* output) {
  const auto seconds = static_cast<time_t>(epoch_ms / 1000);
  std::tm utc{};
  if (gmtime_s(&utc, &seconds) != 0) return false;
  char buffer[32]{};
  if (std::strftime(buffer, sizeof(buffer), "%Y%m%dT%H%M%SZ", &utc) == 0) return false;
  *output = buffer;
  return true;
}

bool IsSafeOpenDocumentExtension(const std::filesystem::path& path) {
  auto extension = path.extension().wstring();
  std::transform(extension.begin(), extension.end(), extension.begin(), [](wchar_t ch) {
    return static_cast<wchar_t>(std::towlower(ch));
  });
  static const std::unordered_set<std::wstring> allowed = {
      L".pdf", L".txt", L".md", L".csv", L".json", L".xml", L".doc", L".docx",
      L".xls", L".xlsx", L".ppt", L".pptx", L".jpg", L".jpeg", L".png", L".gif",
      L".webp", L".mp3", L".wav", L".ogg", L".m4a", L".mp4", L".mov"};
  return allowed.find(extension) != allowed.end();
}

EncodableValue OpenSelectedFile(const EncodableMap& args) {
  const auto raw_path = Utf8ToWide(GetString(args, "path"));
  if (raw_path.empty() || g_selected_files.find(raw_path) == g_selected_files.end()) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Choose this file through Leo's picker first.")}});
  }
  const auto attrs = GetFileAttributesW(raw_path.c_str());
  if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
      !IsSafeOpenDocumentExtension(std::filesystem::path(raw_path))) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("The selected file type or target is not safe to open automatically.")}});
  }
  if (!ShellOpen(raw_path)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Windows could not open the selected file.")}});
  }
  return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(true)},
                                     {EncodableValue("handoff"), EncodableValue("document_viewer")}});
}

EncodableValue CreateCalendarEventDraft(const EncodableMap& args) {
  const auto title = GetString(args, "title");
  const auto description = GetString(args, "description");
  const auto location = GetString(args, "location");
  bool start_valid = false;
  bool end_valid = false;
  const auto start_ms = GetInt64(args, "startEpochMs", &start_valid);
  const auto end_ms = GetInt64(args, "endEpochMs", &end_valid);
  if (!start_valid || !end_valid || start_ms <= 0 || end_ms <= start_ms ||
      end_ms - start_ms > 7LL * 24LL * 60LL * 60LL * 1000LL ||
      !HasSafeText(title, 800, 200, false) || title.empty() ||
      !HasSafeText(description, 8192, 2048, true) ||
      !HasSafeText(location, 1200, 300, false)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Calendar event details are invalid or exceed the allowed limits.")}});
  }
  std::string start_utc;
  std::string end_utc;
  std::string stamp_utc;
  const auto now_ms = static_cast<int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count());
  if (!FormatIcsUtc(start_ms, &start_utc) || !FormatIcsUtc(end_ms, &end_utc) ||
      !FormatIcsUtc(now_ms, &stamp_utc)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Calendar date is outside the supported range.")}});
  }
  const auto token = NewWorkspaceToken();
  if (token.empty()) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Could not create a unique calendar draft name.")}});
  }
  std::error_code ec;
  auto root = std::filesystem::temp_directory_path(ec);
  if (ec || root.empty()) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Temporary storage is unavailable.")}});
  }
  root /= L"LeoCalendarDrafts";
  std::filesystem::create_directories(root, ec);
  const auto root_attrs = ec ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW(root.c_str());
  if (ec || root_attrs == INVALID_FILE_ATTRIBUTES || (root_attrs & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
      (root_attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Calendar draft storage is unsafe or unavailable.")}});
  }
  const auto cutoff = std::filesystem::file_time_type::clock::now() - std::chrono::hours(48);
  for (const auto& item : std::filesystem::directory_iterator(root, ec)) {
    if (ec) break;
    const auto filename = item.path().filename().wstring();
    if (item.path().extension() == L".ics" && filename.rfind(L"event-", 0) == 0) {
      const auto written = item.last_write_time(ec);
      if (!ec && written < cutoff) std::filesystem::remove(item.path(), ec);
      ec.clear();
    }
  }
  const auto draft_path = root / (L"event-" + Utf8ToWide(token) + L".ics");
  std::string ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Leo AI//Calendar Draft//EN\r\nCALSCALE:GREGORIAN\r\nBEGIN:VEVENT\r\n";
  ics += "UID:" + token + "@leo.local\r\nDTSTAMP:" + stamp_utc + "\r\nDTSTART:" + start_utc + "\r\nDTEND:" + end_utc + "\r\n";
  ics += "SUMMARY:" + EscapeIcsText(title) + "\r\n";
  if (!description.empty()) ics += "DESCRIPTION:" + EscapeIcsText(description) + "\r\n";
  if (!location.empty()) ics += "LOCATION:" + EscapeIcsText(location) + "\r\n";
  ics += "END:VEVENT\r\nEND:VCALENDAR\r\n";
  if (ics.size() > 16 * 1024) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Calendar draft exceeds the size limit.")}});
  }
  {
    std::ofstream stream(draft_path, std::ios::binary | std::ios::trunc);
    if (!stream) return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                                     {EncodableValue("message"), EncodableValue("Could not create the calendar draft.")}});
    stream.write(ics.data(), static_cast<std::streamsize>(ics.size()));
    stream.flush();
    if (!stream) {
      stream.close();
      std::filesystem::remove(draft_path, ec);
      return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                         {EncodableValue("message"), EncodableValue("Could not write the calendar draft completely.")}});
    }
  }
  if (!ShellOpen(draft_path.wstring())) {
    std::filesystem::remove(draft_path, ec);
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("No Windows calendar app accepted the event draft.")}});
  }
  return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(true)},
                                     {EncodableValue("handoff"), EncodableValue("calendar_event_draft")},
                                     {EncodableValue("message"), EncodableValue("The default calendar app was opened with a draft. Save it there to create the event.")}});
}

EncodableValue CopyTextToClipboard(const EncodableMap& args) {
  const auto content = GetString(args, "content");
  if (!HasSafeText(content, 16 * 1024, 10000, true)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Clipboard text is invalid or exceeds the allowed size.")}});
  }
  const auto wide = Utf8ToWide(content);
  if (content.size() > 0 && wide.empty()) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Clipboard text is not valid UTF-8.")}});
  }
  if (!OpenClipboard(nullptr)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Windows clipboard is busy.")}});
  }
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, (wide.size() + 1) * sizeof(wchar_t));
  if (memory == nullptr) {
    CloseClipboard();
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Clipboard memory allocation failed.")}});
  }
  auto* destination = static_cast<wchar_t*>(GlobalLock(memory));
  if (destination == nullptr) {
    GlobalFree(memory);
    CloseClipboard();
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Clipboard memory lock failed.")}});
  }
  std::copy(wide.begin(), wide.end(), destination);
  destination[wide.size()] = L'\0';
  GlobalUnlock(memory);
  if (!EmptyClipboard()) {
    GlobalFree(memory);
    CloseClipboard();
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Windows could not clear the clipboard; existing content was not intentionally replaced.")}});
  }
  if (SetClipboardData(CF_UNICODETEXT, memory) == nullptr) {
    GlobalFree(memory);
    CloseClipboard();
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Clipboard text could not be installed after the previous clipboard contents were cleared; previous content may no longer be available.")}});
  }
  CloseClipboard();
  return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(true)},
                                     {EncodableValue("characters"), EncodableValue(static_cast<int64_t>(wide.size()))}});
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(), -1, nullptr, 0);
  if (size <= 0) return {};
  std::wstring output(static_cast<size_t>(size), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(), -1, output.data(), size) <= 0) return {};
  output.resize(static_cast<size_t>(size - 1));
  return output;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string output(static_cast<size_t>(size), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(), -1, output.data(), size, nullptr, nullptr) <= 0) return {};
  output.resize(static_cast<size_t>(size - 1));
  return output;
}

std::string NewWorkspaceToken() {
  GUID guid{};
  if (FAILED(CoCreateGuid(&guid))) return {};
  wchar_t buffer[40]{};
  if (StringFromGUID2(guid, buffer, 40) == 0) return {};
  std::wstring compact;
  for (const auto ch : std::wstring(buffer)) {
    if (ch != L'{' && ch != L'}' && ch != L'-') compact.push_back(ch);
  }
  auto token = WideToUtf8(compact);
  std::transform(token.begin(), token.end(), token.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return token;
}

std::string Sha256Hex(const std::string& bytes) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  DWORD object_length = 0;
  DWORD hash_length = 0;
  DWORD returned = 0;
  std::vector<UCHAR> object;
  std::vector<UCHAR> digest;
  std::string output;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) return {};
  const auto cleanup = [&]() {
    if (hash != nullptr) BCryptDestroyHash(hash);
    if (algorithm != nullptr) BCryptCloseAlgorithmProvider(algorithm, 0);
  };
  if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                        reinterpret_cast<PUCHAR>(&object_length), sizeof(object_length), &returned, 0) < 0 ||
      BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH,
                        reinterpret_cast<PUCHAR>(&hash_length), sizeof(hash_length), &returned, 0) < 0) {
    cleanup();
    return {};
  }
  object.resize(object_length);
  digest.resize(hash_length);
  static UCHAR empty_input = 0;
  auto* input = bytes.empty()
      ? &empty_input
      : reinterpret_cast<PUCHAR>(const_cast<char*>(bytes.data()));
  if (BCryptCreateHash(algorithm, &hash, object.data(), object_length, nullptr, 0, 0) < 0 ||
      BCryptHashData(hash, input, static_cast<ULONG>(bytes.size()), 0) < 0 ||
      BCryptFinishHash(hash, digest.data(), hash_length, 0) < 0) {
    cleanup();
    return {};
  }
  static constexpr char kHex[] = "0123456789abcdef";
  output.reserve(digest.size() * 2);
  for (const auto byte : digest) {
    output.push_back(kHex[(byte >> 4) & 0x0f]);
    output.push_back(kHex[byte & 0x0f]);
  }
  cleanup();
  return output;
}

bool HasNoUriControls(const std::string& value);

bool IsValidUtf8Text(const std::string& value) {
  if (value.find('\0') != std::string::npos) return false;
  if (value.empty()) return true;
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                             static_cast<int>(value.size()), nullptr, 0) > 0;
}

size_t CountUnicodeCodePoints(const std::wstring& value) {
  size_t count = 0;
  for (size_t index = 0; index < value.size(); ++index) {
    const auto unit = static_cast<unsigned int>(value[index]);
    if (unit >= 0xd800 && unit <= 0xdbff && index + 1 < value.size()) {
      const auto next = static_cast<unsigned int>(value[index + 1]);
      if (next >= 0xdc00 && next <= 0xdfff) ++index;
    }
    ++count;
  }
  return count;
}

bool IsSafeWorkspaceText(const std::string& value) {
  if (value.size() > kMaxWorkspaceTextBytes || !IsValidUtf8Text(value)) return false;
  return std::none_of(value.begin(), value.end(), [](unsigned char ch) {
    return ch == 0x7f || (ch < 0x20 && ch != '\t' && ch != '\r' && ch != '\n');
  });
}

bool IsSafeWorkspaceFilename(const std::string& value) {
  if (value.empty() || value.size() > 160 || value == "." || value == ".." ||
      value.find_first_of("/\\:<>\"|?*") != std::string::npos ||
      value.front() == ' ' || value.back() == '.' || value.back() == ' ' ||
      !HasNoUriControls(value) || !IsValidUtf8Text(value)) return false;
  const auto dot = value.find('.');
  std::string base = value.substr(0, dot);
  std::transform(base.begin(), base.end(), base.begin(), [](unsigned char ch) {
    return static_cast<char>(std::toupper(ch));
  });
  static const std::unordered_set<std::string> reserved = {
      "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5",
      "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4",
      "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"};
  return reserved.find(base) == reserved.end();
}

bool GetWorkspaceTarget(const EncodableMap& args,
                        std::filesystem::path* target,
                        std::string* error) {
  const auto token = GetString(args, "workspaceToken");
  const auto name = GetString(args, "relativePath");
  if (token.size() != 32 || !IsSafeWorkspaceFilename(name)) {
    *error = "The workspace token or single-file name is invalid.";
    return false;
  }
  const auto found = g_workspace_roots.find(token);
  if (found == g_workspace_roots.end()) {
    *error = "The selected workspace has expired; choose it again.";
    return false;
  }
  const auto attributes = GetFileAttributesW(found->second.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    *error = "The selected workspace is unavailable or is a reparse-point directory.";
    return false;
  }
  *target = found->second / Utf8ToWide(name);
  const auto target_attributes = GetFileAttributesW(target->c_str());
  if (target_attributes != INVALID_FILE_ATTRIBUTES &&
      ((target_attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
       (target_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)) {
    *error = "The target is a directory or reparse point; refusing to follow it.";
    return false;
  }
  const DWORD target_error = target_attributes == INVALID_FILE_ATTRIBUTES ? GetLastError() : ERROR_SUCCESS;
  if (target_attributes == INVALID_FILE_ATTRIBUTES &&
      target_error != ERROR_FILE_NOT_FOUND && target_error != ERROR_PATH_NOT_FOUND) {
    *error = "The target path could not be inspected safely.";
    return false;
  }
  return true;
}

bool ReadWorkspaceFile(const std::filesystem::path& path, std::string* bytes,
                       std::string* error) {
  const auto attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    *error = "The target file is unavailable or unsafe.";
    return false;
  }
  std::error_code filesystem_error;
  const auto size = std::filesystem::file_size(path, filesystem_error);
  if (filesystem_error || size > kMaxWorkspacePreviewBytes) {
    *error = "Existing file exceeds the 64 KiB text preview limit.";
    return false;
  }
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    *error = "Windows could not read the existing file.";
    return false;
  }
  bytes->clear();
  char buffer[8192];
  while (stream) {
    stream.read(buffer, sizeof(buffer));
    const auto count = static_cast<size_t>(stream.gcount());
    if (bytes->size() + count > kMaxWorkspacePreviewBytes) {
      *error = "Existing file grew beyond the 64 KiB text preview limit.";
      return false;
    }
    bytes->append(buffer, count);
  }
  if (stream.bad() || !IsValidUtf8Text(*bytes) ||
      std::any_of(bytes->begin(), bytes->end(), [](unsigned char ch) {
        return ch == 0x7f || (ch < 0x20 && ch != '\t' && ch != '\r' && ch != '\n');
      })) {
    *error = "Binary, invalid UTF-8, control-character, or unreadable files cannot be replaced as text.";
    return false;
  }
  return true;
}

bool WriteStagingFile(const std::filesystem::path& path, const std::string& content) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                            FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_WRITE_THROUGH, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool wrote = WriteFile(file, content.data(), static_cast<DWORD>(content.size()), &written, nullptr) != 0 &&
                     static_cast<size_t>(written) == content.size() && FlushFileBuffers(file) != 0;
  CloseHandle(file);
  if (!wrote) DeleteFileW(path.c_str());
  return wrote;
}

EncodableValue PickWorkspace() {
  const HRESULT init_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool should_uninitialize = SUCCEEDED(init_result);
  if (FAILED(init_result) && init_result != RPC_E_CHANGED_MODE) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("error"), EncodableValue("com_init_failed")}});
  }
  ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog));
  if (SUCCEEDED(hr)) {
    DWORD options = 0;
    hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) {
      options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_PICKFOLDERS;
      options &= ~FOS_FILEMUSTEXIST;
      hr = dialog->SetOptions(options);
    }
  }
  if (SUCCEEDED(hr)) hr = dialog->Show(nullptr);
  EncodableValue response;
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                            {EncodableValue("cancelled"), EncodableValue(true)}});
  } else if (SUCCEEDED(hr)) {
    ComPtr<IShellItem> item;
    hr = dialog->GetResult(&item);
    PWSTR selected = nullptr;
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &selected);
    if (SUCCEEDED(hr) && selected != nullptr) {
      std::filesystem::path root(selected);
      CoTaskMemFree(selected);
      std::error_code ec;
      root = std::filesystem::canonical(root, ec);
      const auto attrs = ec ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW(root.c_str());
      if (ec || attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
          (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                                {EncodableValue("error"), EncodableValue("unsafe_workspace")}});
      } else {
        const auto token = NewWorkspaceToken();
        if (token.empty()) {
          response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                                  {EncodableValue("error"), EncodableValue("token_generation_failed")}});
        } else {
          g_workspace_roots[token] = root;
          while (g_workspace_roots.size() > 8) g_workspace_roots.erase(g_workspace_roots.begin());
          response = EncodableValue(EncodableMap{
              {EncodableValue("success"), EncodableValue(true)},
              {EncodableValue("cancelled"), EncodableValue(false)},
              {EncodableValue("workspaceToken"), EncodableValue(token)},
      {EncodableValue("workspaceLabel"), EncodableValue(WideToUtf8(root.filename().wstring()).empty()
          ? "المجلد المحدد" : WideToUtf8(root.filename().wstring()))}});
        }
      }
    } else {
      if (selected != nullptr) CoTaskMemFree(selected);
      response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                              {EncodableValue("error"), EncodableValue("folder_unavailable")}});
    }
  } else {
    response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                            {EncodableValue("error"), EncodableValue("folder_picker_failed")}});
  }
  dialog.Reset();
  if (should_uninitialize) CoUninitialize();
  return response;
}

EncodableValue PreviewWorkspaceWrite(const EncodableMap& args) {
  std::filesystem::path target;
  std::string error;
  if (!GetWorkspaceTarget(args, &target, &error)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue(error)}});
  }
  const auto content = GetString(args, "content");
  const auto content_characters = CountUnicodeCodePoints(Utf8ToWide(content));
  if (!IsSafeWorkspaceText(content) || content_characters > 10000) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Text is invalid or exceeds 16 KiB / 10,000 characters")}});
  }
  const auto attrs = GetFileAttributesW(target.c_str());
  const bool exists = attrs != INVALID_FILE_ATTRIBUTES;
  std::string old_content;
  if (exists && !ReadWorkspaceFile(target, &old_content, &error)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue(error)}});
  }
  const auto old_hash = exists ? Sha256Hex(old_content) : std::string{};
  const auto new_hash = Sha256Hex(content);
  if ((exists && old_hash.empty()) || new_hash.empty()) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("SHA-256 preview failed")}});
  }
  return EncodableValue(EncodableMap{
      {EncodableValue("success"), EncodableValue(true)},
      {EncodableValue("exists"), EncodableValue(exists)},
      {EncodableValue("currentContent"), EncodableValue(old_content)},
      {EncodableValue("currentHash"), EncodableValue(old_hash)},
      {EncodableValue("proposedHash"), EncodableValue(new_hash)},
      {EncodableValue("bytes"), EncodableValue(static_cast<int64_t>(content.size()))}});
}

EncodableValue ApplyWorkspaceWrite(const EncodableMap& args) {
  std::filesystem::path target;
  std::string error;
  if (!GetWorkspaceTarget(args, &target, &error)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue(error)}});
  }
  const auto content = GetString(args, "content");
  const auto expected_hash = GetString(args, "expectedHash");
  const auto expected_new_hash = GetString(args, "expectedNewHash");
  const auto content_characters = CountUnicodeCodePoints(Utf8ToWide(content));
  if (!IsSafeWorkspaceText(content) || content_characters > 10000) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Text is invalid or exceeds 16 KiB / 10,000 characters")}});
  }
  const auto attrs = GetFileAttributesW(target.c_str());
  const bool exists = attrs != INVALID_FILE_ATTRIBUTES;
  std::string old_content;
  if (exists && !ReadWorkspaceFile(target, &old_content, &error)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue(error)}});
  }
  const auto current_hash = exists ? Sha256Hex(old_content) : std::string{};
  if (current_hash.empty() != expected_hash.empty() || current_hash != expected_hash) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("File changed after preview; request a new diff")}});
  }
  const auto new_hash = Sha256Hex(content);
  const auto token = NewWorkspaceToken();
  if (new_hash.empty() || token.empty() || expected_new_hash.size() != 64 ||
      new_hash != expected_new_hash) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Could not prepare a verified write")}});
  }
  const auto parent = target.parent_path();
  const auto stage = parent / Utf8ToWide("Leo-Stage-" + token + ".tmp");
  const auto backup = parent / Utf8ToWide("Leo-Backup-" + token + ".tmp");
  if (!WriteStagingFile(stage, content)) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Could not create and flush the staging file")}});
  }
  // Re-check the selected target after staging and immediately before the
  // rename. This is optimistic concurrency protection; no directory-wide write
  // handle is kept beyond the current single approved operation.
  std::filesystem::path rechecked_target;
  if (!GetWorkspaceTarget(args, &rechecked_target, &error) || rechecked_target != target) {
    DeleteFileW(stage.c_str());
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("Workspace changed during staging")}});
  }
  if (exists) {
    std::string latest_content;
    if (!ReadWorkspaceFile(target, &latest_content, &error) || Sha256Hex(latest_content) != expected_hash) {
      DeleteFileW(stage.c_str());
      return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                         {EncodableValue("message"), EncodableValue("File changed while staging; no replacement occurred")}});
    }
  } else if (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES) {
    DeleteFileW(stage.c_str());
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("message"), EncodableValue("A file appeared at the target path; no overwrite occurred")}});
  }

  bool committed = false;
  if (exists) {
    if (ReplaceFileW(target.c_str(), stage.c_str(), backup.c_str(), REPLACEFILE_WRITE_THROUGH, nullptr, nullptr)) {
      committed = true;
    } else {
      DeleteFileW(stage.c_str());
      return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                         {EncodableValue("message"), EncodableValue("Atomic replacement is unavailable; original file was not changed")}});
    }
  } else {
    if (MoveFileExW(stage.c_str(), target.c_str(), MOVEFILE_WRITE_THROUGH)) {
      committed = true;
    } else {
      DeleteFileW(stage.c_str());
      return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                         {EncodableValue("message"), EncodableValue("Cannot create target without overwriting an existing file")}});
    }
  }
  std::string verify_content;
  const bool verified = committed && ReadWorkspaceFile(target, &verify_content, &error) &&
                        Sha256Hex(verify_content) == new_hash;
  if (!verified) {
    bool rolled_back = false;
    if (exists) {
      rolled_back = ReplaceFileW(target.c_str(), backup.c_str(), nullptr,
                                 REPLACEFILE_WRITE_THROUGH, nullptr, nullptr) != 0;
    } else {
      rolled_back = DeleteFileW(target.c_str()) != 0;
    }
    return EncodableValue(EncodableMap{
        {EncodableValue("success"), EncodableValue(false)},
        {EncodableValue("rolledBack"), EncodableValue(rolled_back)},
        {EncodableValue("message"), EncodableValue(rolled_back
            ? "Post-write verification failed; previous state was restored"
            : "Post-write verification failed and automatic rollback needs manual attention")}});
  }
  const bool backup_removed = !exists || DeleteFileW(backup.c_str()) != 0;
  const auto token = GetString(args, "workspaceToken");
  g_workspace_roots.erase(token);
  EncodableMap response{
      {EncodableValue("success"), EncodableValue(true)},
      {EncodableValue("created"), EncodableValue(!exists)},
      {EncodableValue("updated"), EncodableValue(exists)},
      {EncodableValue("bytes"), EncodableValue(static_cast<int64_t>(content.size()))},
      {EncodableValue("sha256"), EncodableValue(new_hash)}};
  if (!backup_removed) {
    response.emplace(EncodableValue("message"), EncodableValue(
        "The new file was verified, but the Leo-Backup copy could not be removed. Review and remove it manually if no longer needed."));
  }
  return EncodableValue(std::move(response));
}

bool HasNoUriControls(const std::string& value) {
  return std::all_of(value.begin(), value.end(), [](unsigned char ch) {
    return ch >= 0x20 && ch != 0x7f;
  });
}

bool IsAllowedWebLink(const std::string& value) {
  if (value.size() > 2048 || !HasNoUriControls(value)) return false;
  const auto prefix = value.rfind("https://", 0) == 0 ? 8u :
                      value.rfind("http://", 0) == 0 ? 7u : 0u;
  if (prefix == 0) return false;
  const auto authority_end = value.find_first_of("/?#", prefix);
  const auto authority = value.substr(prefix, authority_end - prefix);
  return !authority.empty() && authority.find('@') == std::string::npos &&
         authority.find('\\') == std::string::npos &&
         authority.find(' ') == std::string::npos;
}

bool IsSafeEmailAddress(const std::string& value) {
  if (value.empty() || value.size() > 254 || !HasNoUriControls(value) ||
      value.find_first_of(" <>\\\";,?/") != std::string::npos) return false;
  const auto at = value.find('@');
  return at != std::string::npos && at > 0 && at + 1 < value.size() &&
         value.find('@', at + 1) == std::string::npos;
}

bool IsSafePhoneNumber(const std::string& value) {
  return value.size() <= 32 && !value.empty() &&
         std::all_of(value.begin(), value.end(), [](unsigned char ch) {
           return (ch >= '0' && ch <= '9') || ch == '+' || ch == '*' || ch == '#' ||
                  ch == '(' || ch == ')' || ch == '.' || ch == ' ' || ch == '-';
         });
}

bool IsAllowedAppTarget(const std::string& value) {
  if (value.rfind("shell:AppsFolder\\", 0) == 0) {
    const auto app_id = value.substr(std::string("shell:AppsFolder\\").size());
    return !app_id.empty() && app_id.find("..") == std::string::npos &&
           app_id.find_first_not_of(
               "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._!-") ==
               std::string::npos;
  }
  if (value.rfind("ms-", 0) == 0) {
    static const std::unordered_set<std::string> allowed = {
        "ms-settings:", "ms-settings:privacy-microphone", "ms-settings:privacy-contacts"};
    return allowed.find(value) != allowed.end();
  }
  return false;
}

bool ShellOpen(const std::wstring& target) {
  if (target.empty()) return false;
  const auto result = reinterpret_cast<INT_PTR>(
      ShellExecuteW(nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  return result > 32;
}

EncodableValue PickPath() {
  const HRESULT init_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool should_uninitialize = SUCCEEDED(init_result);
  if (FAILED(init_result) && init_result != RPC_E_CHANGED_MODE) {
    return EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                       {EncodableValue("error"), EncodableValue("com_init_failed")}});
  }

  ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog));
  if (SUCCEEDED(hr)) {
    DWORD options = 0;
    hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) {
      options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
      options |= FOS_FILEMUSTEXIST;
      hr = dialog->SetOptions(options);
    }
  }
  if (SUCCEEDED(hr)) hr = dialog->Show(nullptr);

  EncodableValue response;
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                            {EncodableValue("cancelled"), EncodableValue(true)}});
  } else if (SUCCEEDED(hr)) {
    ComPtr<IShellItem> item;
    hr = dialog->GetResult(&item);
    PWSTR path = nullptr;
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (SUCCEEDED(hr) && path != nullptr) {
      std::wstring wide_path(path);
      CoTaskMemFree(path);
      g_selected_files.insert(wide_path);
      if (g_selected_files.size() > 64) g_selected_files.erase(g_selected_files.begin());
      const int needed = WideCharToMultiByte(CP_UTF8, 0, wide_path.c_str(), -1, nullptr, 0, nullptr, nullptr);
      if (needed <= 0) {
        response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                                {EncodableValue("error"), EncodableValue("path_encoding_failed")}});
        dialog.Reset();
        if (should_uninitialize) CoUninitialize();
        return response;
      }
      std::string utf8(static_cast<size_t>(needed), '\0');
      const int converted = WideCharToMultiByte(CP_UTF8, 0, wide_path.c_str(), -1, utf8.data(), needed, nullptr, nullptr);
      if (converted <= 0) {
        response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                                {EncodableValue("error"), EncodableValue("path_encoding_failed")}});
        dialog.Reset();
        if (should_uninitialize) CoUninitialize();
        return response;
      }
      utf8.resize(static_cast<size_t>(needed - 1));
      response = EncodableValue(EncodableMap{
          {EncodableValue("success"), EncodableValue(true)},
          {EncodableValue("cancelled"), EncodableValue(false)},
          {EncodableValue("path"), EncodableValue(utf8)},
          {EncodableValue("kind"), EncodableValue("file")}});
    } else {
      if (path != nullptr) CoTaskMemFree(path);
      response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                              {EncodableValue("error"), EncodableValue("path_unavailable")}});
    }
  } else {
    response = EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(false)},
                                            {EncodableValue("error"), EncodableValue("file_picker_failed")}});
  }
  dialog.Reset();
  if (should_uninitialize) CoUninitialize();
  return response;
}

}  // namespace

void LeoPlatformCapabilitiesPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<LeoPlatformCapabilitiesPlugin>(registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

LeoPlatformCapabilitiesPlugin::LeoPlatformCapabilitiesPlugin(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger,
      "ai.leo/platform_capabilities",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) { HandleMethodCall(call, std::move(result)); });
}

LeoPlatformCapabilitiesPlugin::~LeoPlatformCapabilitiesPlugin() = default;

void LeoPlatformCapabilitiesPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = method_call.method_name();
  if (method == "getPlatform") {
    result->Success(EncodableValue("windows"));
    return;
  }
  if (method == "openMicrophonePrivacySettings") {
    const bool opened = ShellOpen(L"ms-settings:privacy-microphone");
    result->Success(EncodableValue(opened));
    return;
  }
  if (method == "checkOsPermission") {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    const auto capability = arguments == nullptr ? std::string{} : GetString(*arguments, "capabilityId");
    const bool granted = capability != "audio.microphone" &&
                         capability != "contacts.read" &&
                         capability != "system.admin_operation";
    result->Success(EncodableValue(granted));
    return;
  }
  if (method == "requestOsPermission") {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    const auto capability = arguments == nullptr ? std::string{} : GetString(*arguments, "capabilityId");
    if (capability == "audio.microphone") {
      ShellOpen(L"ms-settings:privacy-microphone");
      result->Success(EncodableValue(false));
    } else {
      result->Success(EncodableValue(capability != "system.admin_operation" && capability != "contacts.read"));
    }
    return;
  }
  if (method == "executeCapability") {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    if (arguments == nullptr) {
      result->Error("invalid_arguments", "Expected an arguments map.");
      return;
    }
    const auto operation = GetString(*arguments, "operation");
    const auto* nested = FindValue(*arguments, "arguments");
    const auto* values = nested == nullptr ? nullptr : std::get_if<EncodableMap>(nested);
    const EncodableMap empty;
    const auto& args = values == nullptr ? empty : *values;

    if (operation == "pickFile") {
      result->Success(PickPath());
      return;
    }
    if (operation == "readTextFile") {
      const auto path = Utf8ToWide(GetString(args, "path"));
      if (path.empty() || g_selected_files.find(path) == g_selected_files.end()) {
        result->Error("file_not_selected", "Choose the file through Leo's Windows file picker first.");
        return;
      }
      std::error_code filesystem_error;
      const auto size = std::filesystem::file_size(std::filesystem::path(path), filesystem_error);
      if (filesystem_error || size > 2 * 1024 * 1024) {
        result->Error("file_size_limit", "The selected file is unavailable or exceeds the 2 MiB text preview limit.");
        return;
      }
      std::ifstream stream(std::filesystem::path(path), std::ios::binary);
      if (!stream) {
        result->Error("file_open_failed", "Windows could not read the selected file.");
        return;
      }
      std::string content(static_cast<size_t>(size) + 1, '\0');
      stream.read(content.data(), static_cast<std::streamsize>(content.size()));
      const auto bytes_read = static_cast<size_t>(stream.gcount());
      if (bytes_read > 2 * 1024 * 1024) {
        result->Error("file_size_limit", "The selected file grew beyond the 2 MiB text preview limit.");
        return;
      }
      content.resize(bytes_read);
      if (content.find('\0') != std::string::npos ||
          (!content.empty() && MultiByteToWideChar(
              CP_UTF8, MB_ERR_INVALID_CHARS, content.data(), static_cast<int>(content.size()),
              nullptr, 0) <= 0)) {
        result->Error("invalid_utf8", "The selected file contains NUL bytes or is not valid UTF-8 text.");
        return;
      }
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("success"), EncodableValue(true)},
          {EncodableValue("text"), EncodableValue(content)},
          {EncodableValue("bytes"), EncodableValue(static_cast<int64_t>(content.size()))}}));
      return;
    }
    if (operation == "openSelectedFile") {
      result->Success(OpenSelectedFile(args));
      return;
    }
    if (operation == "createCalendarEventDraft") {
      result->Success(CreateCalendarEventDraft(args));
      return;
    }
    if (operation == "copyText") {
      result->Success(CopyTextToClipboard(args));
      return;
    }
    if (operation == "pickWorkspace") {
      result->Success(PickWorkspace());
      return;
    }
    if (operation == "previewWorkspaceWrite") {
      result->Success(PreviewWorkspaceWrite(args));
      return;
    }
    if (operation == "applyWorkspaceWrite") {
      result->Success(ApplyWorkspaceWrite(args));
      return;
    }
    if (operation == "releaseWorkspace") {
      g_workspace_roots.erase(GetString(args, "workspaceToken"));
      result->Success(EncodableValue(EncodableMap{{EncodableValue("success"), EncodableValue(true)}}));
      return;
    }
    std::string target;
    if (operation == "openDialer") {
      const auto number = GetString(args, "number");
      if (!IsSafePhoneNumber(number)) {
        result->Error("invalid_number", "A valid phone number is required.");
        return;
      }
      target = "tel:" + number;
    } else if (operation == "composeEmail") {
      target = GetString(args, "mailto");
      if (target.empty()) target = "mailto:" + GetString(args, "to");
    } else if (operation == "composeMessage") {
      result->Error("unsupported_operation", "No default SMS composition API is available on this Windows adapter.");
      return;
    } else if (operation == "openUrl") {
      target = GetString(args, "url");
    } else if (operation == "launchApp") {
      target = GetString(args, "target");
    } else {
      result->Error("unsupported_operation", "This operation is not implemented on Windows Alpha.");
      return;
    }
    bool target_allowed = false;
    if (operation == "openUrl") {
      target_allowed = IsAllowedWebLink(target);
    } else if (operation == "composeEmail") {
      target_allowed = target.size() <= 100000 && HasNoUriControls(target) &&
                       target.rfind("mailto:", 0) == 0 &&
                       IsSafeEmailAddress(GetString(args, "to"));
    } else if (operation == "openDialer") {
      target_allowed = target.size() <= 40 && HasNoUriControls(target) &&
                       target.rfind("tel:", 0) == 0;
    } else if (operation == "launchApp") {
      target_allowed = IsAllowedAppTarget(target);
    }
    if (target.empty() || !target_allowed) {
      result->Error("blocked_target", "The target does not use an approved link scheme or registered Windows app target.");
      return;
    }
    const bool opened = ShellOpen(Utf8ToWide(target));
    if (!opened) {
      result->Error("shell_open_failed", "Windows could not open the requested target.");
      return;
    }
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("success"), EncodableValue(true)},
        {EncodableValue("handoff"), EncodableValue(operation)}}));
    return;
  }
  result->NotImplemented();
}

}  // namespace leo_platform_capabilities
