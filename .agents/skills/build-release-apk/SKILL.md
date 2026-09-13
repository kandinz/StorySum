---
name: build-release-apk
description: Tự động tăng version trong pubspec.yaml, commit và push Git Tag lên GitHub để GitHub Actions CI/CD tự build release APK ARM64 (StorySum-v<version>.apk) và tạo GitHub Release, sau đó chạy full index sync với Codebase Memory MCP.
---

# Flutter Release via GitHub Actions CI/CD + Codebase Memory Sync

Skill này tự động hóa toàn diện quy trình phát hành phiên bản mới qua **GitHub Actions CI/CD**: máy local không cần tốn CPU/thời gian build Gradle, GitHub runner sẽ tự động build và upload file APK ARM64 lên GitHub Release.

### 🚀 Quy trình thực hiện khi gọi `/build-release-apk`:

1. **Tăng Version & Git Commit**:
   - Tự động tăng patch version trong `pubspec.yaml` (ví dụ: `1.0.77+78` -> `1.0.78+79`).
   - Tạo Git commit chứa các thay đổi mã nguồn mới nhất:
     ```powershell
     git add -A
     git commit -m "chore(release): bump version to v<version>"
     ```

2. **Tạo Git Tag & Push lên GitHub**:
   - Tạo Git Tag tương ứng (ví dụ: `v1.0.78`):
     ```powershell
     git tag -a v1.0.78 -m "Release v1.0.78"
     ```
   - Push commit và tag lên GitHub `origin`:
     ```powershell
     git push origin main
     git push origin v1.0.78
     ```
   - **GitHub Actions CI/CD tự động kích hoạt ngay lập tức**:
     - Máy chủ GitHub (Ubuntu runner) tự động cài đặt Java 17 + Flutter stable.
     - Biên dịch release APK kiến trúc ARM64:
       `flutter build apk --release --target-platform android-arm64 --split-per-abi`
     - Đổi tên thành `StorySum-v<version>.apk`.
     - Tạo GitHub Release và upload APK kèm link download trực tiếp.
     - Theo dõi tiến trình tại: `https://github.com/kandinz/StorySum/actions`

3. **Chạy Full Index Sync Codebase MCP**:
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

## 🛠️ Chạy nhanh tự động qua Script:

```powershell
python .agents/skills/build-release-apk/scripts/release.py
```

### Các tùy chọn script:
- **Chỉ định tag cụ thể:**
  ```powershell
  python .agents/skills/build-release-apk/scripts/release.py --tag v1.0.78
  ```
- **Không tự động tăng version trong pubspec.yaml:**
  ```powershell
  python .agents/skills/build-release-apk/scripts/release.py --no-bump
  ```
- **Tùy chọn build local (nếu muốn build trực tiếp trên máy thay vì CI/CD):**
  ```powershell
  python .agents/skills/build-release-apk/scripts/release.py --build-local
  ```
