---
name: build-release-apk
description: Build Flutter Android ARM64 release APK kèm version (app-arm64-v8a-release-v<version>.apk), upload nó lên GitHub Releases, push git changes, và chạy full index sync với Codebase Memory MCP.
---

# Flutter Build & Release (ARM64) + Codebase Memory Sync

Skill này tự động hóa toàn diện quy trình build, phát hành và đồng bộ đồ thị tri thức mã nguồn cho ứng dụng Flutter Android với **4 bước chuẩn**:
1. **Chỉ build file APK ARM64 và đổi tên kèm theo version** (ví dụ: `app-arm64-v8a-release-v1.0.53.apk`).
2. **Tải file APK kèm version lên GitHub Release** tương ứng với phiên bản.
3. **Commit và push các thay đổi mã nguồn cùng Git Tag lên Git repository**.
4. **Chạy Full Index Sync đồ thị tri thức mã nguồn qua `codebase-memory-mcp`**.

---

## 🚀 Cách thực hiện qua Agent / Lệnh

Khi người dùng gọi `/build-release-apk`, Agent sẽ thực hiện tuần tự 4 bước:

### 🔹 Bước 1: Build APK ARM64 & Đổi tên kèm Version
1. Lấy version hiện tại từ `pubspec.yaml` (ví dụ: `1.0.53` -> tag `v1.0.53`).
2. Chạy lệnh Flutter chỉ biên dịch kiến trúc ARM64:
```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi
```
3. Đổi tên file APK đầu ra sang tên có kèm version:
   - Từ: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
   - Thành: `build/app/outputs/flutter-apk/app-arm64-v8a-release-v1.0.53.apk` (tương ứng với tag version trong `pubspec.yaml`).

---

### 🔹 Bước 2: Push APK lên GitHub Release
Tạo hoặc cập nhật GitHub Release cho tag version (ví dụ: `v1.0.53`), sau đó upload asset `app-arm64-v8a-release-v1.0.53.apk`.
*(Có thể chạy qua script tự động `python .agents/skills/build-release-apk/scripts/release.py` hoặc REST API GitHub)*.

---

### 🔹 Bước 3: Push code và Tag lên Git
1. Kiểm tra `git status`.
2. Commit toàn bộ thay đổi:
   ```powershell
   git add -A
   git commit -m "build(release): update release APK and latest changes"
   ```
3. Đẩy commit và tag lên remote:
   ```powershell
   git push origin main
   git push origin --tags
   ```

---

### 🔹 Bước 4: Chạy Full Index Sync Codebase MCP
Gọi công cụ MCP `codebase-memory-mcp` để index toàn bộ mã nguồn với chế độ `full`:
```json
Tool: call_mcp_tool
ServerName: codebase-memory-mcp
ToolName: index_repository
Arguments: {
  "repo_path": "D:/Project/SummaryStory",
  "mode": "full"
}
```

---

## 🛠️ Chạy nhanh tự động các bước build & git:

```powershell
python .agents/skills/build-release-apk/scripts/release.py
```

### Các tùy chọn script nâng cao:
- **Chỉ định tag và ghi chú release:**
  ```powershell
  python .agents/skills/build-release-apk/scripts/release.py --tag v1.0.53 --title "Release v1.0.53" --notes "Ghi chú cập nhật..."
  ```
- **Tùy chỉnh commit message:**
  ```powershell
  python .agents/skills/build-release-apk/scripts/release.py --commit-msg "feat: cập nhật tính năng mới"
  ```
- **Bỏ qua bước build nếu APK đã có sẵn (sẽ tự động đổi tên APK hiện có sang tên kèm version):**
  ```powershell
  python .agents/skills/build-release-apk/scripts/release.py --skip-build
  ```

---

## ⚠️ Lưu ý quan trọng
- **Cập nhật version**: Trước khi tạo release mới, hãy tăng phiên bản trong `pubspec.yaml` (ví dụ `version: 1.0.53+54`).
- **File APK kèm Version**: File APK sau khi build sẽ tự động được đổi tên thành `app-arm64-v8a-release-<version>.apk` (ví dụ: `app-arm64-v8a-release-v1.0.53.apk`) trước khi upload lên GitHub Release.
- **Codebase Memory Index**: Luôn gọi `index_repository` ở Bước 4 để đảm bảo đồ thị tri thức kiến trúc dự án luôn phản ánh chính xác nhất trạng thái commit mới nhất.
