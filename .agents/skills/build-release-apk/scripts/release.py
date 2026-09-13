"""
Helper script to automate Git Tagging & Pushing for GitHub Actions CI/CD Release (StorySum).
Can also optionally build locally if --build-local is specified.
"""

import argparse
import os
import re
import subprocess
import sys
import time
import requests

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def run_cmd(cmd, cwd=None, check=True):
    print(f"[EXEC] {cmd}")
    res = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if res.stdout:
        try:
            print(res.stdout.strip())
        except Exception:
            try:
                sys.stdout.buffer.write(res.stdout.encode("utf-8", errors="replace") + b"\n")
            except Exception:
                pass
    if res.stderr and res.returncode != 0:
        try:
            print(f"[STDERR] {res.stderr.strip()}", file=sys.stderr)
        except Exception:
            pass
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed with code {res.returncode}: {cmd}")
    return res


def get_git_info(cwd):
    res = run_cmd("git remote get-url origin", cwd=cwd)
    url = res.stdout.strip()
    
    token = None
    owner = None
    repo = None

    token_match = re.search(r"https://([^@:]+)@github\.com/([^/]+)/([^/\.]+)(?:\.git)?", url)
    if token_match:
        token = token_match.group(1)
        owner = token_match.group(2)
        repo = token_match.group(3)
    else:
        norm_match = re.search(r"github\.com[:/]([^/]+)/([^/\.]+)(?:\.git)?", url)
        if norm_match:
            owner = norm_match.group(1)
            repo = norm_match.group(2)
            
    if not token or token == "git":
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        
    branch_res = run_cmd("git rev-parse --abbrev-ref HEAD", cwd=cwd)
    branch = branch_res.stdout.strip() or "main"
    
    return {"url": url, "token": token, "owner": owner, "repo": repo, "branch": branch}


def get_pubspec_version(cwd):
    pubspec_path = os.path.join(cwd, "pubspec.yaml")
    if not os.path.exists(pubspec_path):
        return "1.0.0", "1.0.0+1"
    with open(pubspec_path, "r", encoding="utf-8") as f:
        content = f.read()
    match = re.search(r"^version:\s*([^\s\r\n]+)", content, re.MULTILINE)
    if match:
        full_ver = match.group(1)
        ver_name = full_ver.split("+")[0]
        return ver_name, full_ver
    return "1.0.0", "1.0.0+1"


def bump_pubspec_version(cwd, new_version=None):
    pubspec_path = os.path.join(cwd, "pubspec.yaml")
    if not os.path.exists(pubspec_path):
        return "1.0.0", "v1.0.0"
        
    with open(pubspec_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    match = re.search(r"^version:\s*([^\s\r\n]+)", content, re.MULTILINE)
    if not match:
        return "1.0.0", "v1.0.0"
        
    full_ver = match.group(1)
    if "+" in full_ver:
        ver_name, build_num_str = full_ver.split("+", 1)
        try:
            build_num = int(build_num_str) + 1
        except ValueError:
            build_num = 1
    else:
        ver_name = full_ver
        build_num = 1
        
    if new_version:
        clean_ver = new_version.lstrip("v")
        ver_name = clean_ver
        updated_full = f"{clean_ver}+{build_num}"
    else:
        parts = ver_name.split(".")
        if len(parts) == 3 and parts[2].isdigit():
            parts[2] = str(int(parts[2]) + 1)
            ver_name = ".".join(parts)
        updated_full = f"{ver_name}+{build_num}"
        
    new_content = re.sub(r"^version:\s*[^\s\r\n]+", f"version: {updated_full}", content, count=1, flags=re.MULTILINE)
    with open(pubspec_path, "w", encoding="utf-8") as f:
        f.write(new_content)
        
    print(f"[INFO] Bumped pubspec.yaml version: {full_ver} -> {updated_full}")
    return ver_name, f"v{ver_name}"


def step1_build_apk(cwd, tag):
    print("\n==========================================")
    print("STEP 1: Building Release APK (ARM64 only - Local)")
    print("==========================================")
    
    built_apks = []
    print("\n[INFO] Building ARM64-v8a Split APK...")
    build_arm64_cmd = "flutter build apk --release --target-platform android-arm64 --split-per-abi"
    run_cmd(build_arm64_cmd, cwd=cwd)
    
    apk_dir = os.path.join(cwd, "build", "app", "outputs", "flutter-apk")
    raw_arm64_apk = os.path.join(apk_dir, "app-arm64-v8a-release.apk")
    
    version_tag = tag if tag.startswith("v") else f"v{tag}"
    target_name = f"StorySum-{version_tag}.apk"
    target_apk = os.path.join(apk_dir, target_name)
    
    if os.path.exists(raw_arm64_apk):
        if os.path.exists(target_apk) and os.path.abspath(target_apk) != os.path.abspath(raw_arm64_apk):
            os.remove(target_apk)
        os.rename(raw_arm64_apk, target_apk)
        
        raw_sha1 = raw_arm64_apk + ".sha1"
        target_sha1 = target_apk + ".sha1"
        if os.path.exists(raw_sha1):
            if os.path.exists(target_sha1):
                os.remove(target_sha1)
            os.rename(raw_sha1, target_sha1)
            
        size_mb = os.path.getsize(target_apk) / (1024 * 1024)
        print(f"[SUCCESS] ARM64 APK (renamed to app & version): {target_apk} ({size_mb:.2f} MB)")
        built_apks.append(target_apk)
    elif os.path.exists(target_apk):
        size_mb = os.path.getsize(target_apk) / (1024 * 1024)
        print(f"[SUCCESS] APK already exists with target name: {target_apk} ({size_mb:.2f} MB)")
        built_apks.append(target_apk)

    if not built_apks:
        for f in os.listdir(apk_dir) if os.path.exists(apk_dir) else []:
            if f.endswith(".apk") and (version_tag in f or "StorySum" in f or "arm64" in f or "release" in f):
                built_apks.append(os.path.join(apk_dir, f))

    if not built_apks:
        raise FileNotFoundError(f"Cannot find built APK in {apk_dir}")
        
    return built_apks


def safe_request(method, url, max_retries=5, delay=2, **kwargs):
    kwargs.setdefault("timeout", (60, 900))
    for attempt in range(1, max_retries + 1):
        try:
            res = requests.request(method, url, **kwargs)
            return res
        except Exception as e:
            print(f"[RETRY {attempt}/{max_retries}] Request failed ({e}). Waiting {delay}s...")
            time.sleep(delay)
            if attempt == max_retries:
                raise


def step2_push_github_release(cwd, apk_paths, tag, title, notes, token, owner, repo):
    print("\n==========================================")
    print(f"STEP 2: Uploading APKs to GitHub Release ({tag})")
    print("==========================================")
    
    if not token:
        raise ValueError("GitHub token not found. Please provide token or ensure git remote has token.")
    if not owner or not repo:
        raise ValueError("GitHub repository owner/repo could not be determined.")
        
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "SummaryStory-ReleaseScript"
    }
    
    rel_url = f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
    res = safe_request("GET", rel_url, headers=headers)
    
    if res.status_code == 200:
        release_data = res.json()
        release_id = release_data["id"]
        print(f"[INFO] Found existing release for tag {tag} (ID: {release_id})")
    elif res.status_code == 404:
        print(f"[INFO] Release {tag} not found. Creating new release...")
        create_url = f"https://api.github.com/repos/{owner}/{repo}/releases"
        payload = {
            "tag_name": tag,
            "target_commitish": "main",
            "name": title or f"Release {tag}",
            "body": notes or f"Release {tag}",
            "draft": False,
            "prerelease": False
        }
        create_res = safe_request("POST", create_url, headers=headers, json=payload)
        if create_res.status_code not in (200, 201):
            raise RuntimeError(f"Failed to create release: {create_res.status_code} - {create_res.text}")
        release_data = create_res.json()
        release_id = release_data["id"]
        print(f"[SUCCESS] Created release {tag} (ID: {release_id})")
    else:
        raise RuntimeError(f"Error querying release: {res.status_code} - {res.text}")
        
    existing_assets = {a["name"]: a["id"] for a in release_data.get("assets", [])}
    
    for apk_path in apk_paths:
        asset_name = os.path.basename(apk_path)
        if asset_name in existing_assets:
            print(f"[INFO] Asset {asset_name} already exists (ID: {existing_assets[asset_name]}). Deleting old asset...")
            del_url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{existing_assets[asset_name]}"
            del_res = safe_request("DELETE", del_url, headers=headers)
            if del_res.status_code == 204:
                print(f"[INFO] Deleted old {asset_name} successfully.")
            else:
                print(f"[WARN] Failed to delete old {asset_name}: {del_res.status_code}")
                    
        raw_upload_url = release_data.get("upload_url", "").split("{")[0]
        if raw_upload_url:
            upload_url = f"{raw_upload_url}?name={asset_name}"
        else:
            upload_url = f"https://uploads.github.com/repos/{owner}/{repo}/releases/{release_id}/assets?name={asset_name}"
            
        file_size = os.path.getsize(apk_path)
        upload_headers = {
            "Authorization": f"token {token}",
            "Content-Type": "application/vnd.android.package-archive",
            "Content-Length": str(file_size),
            "User-Agent": "SummaryStory-ReleaseScript"
        }
        
        print(f"[INFO] Uploading {asset_name} ({file_size / (1024*1024):.2f} MB) to release...")
        target_url = upload_url
        current_headers = dict(upload_headers)
        
        while True:
            with open(apk_path, "rb") as f:
                upload_res = safe_request("POST", target_url, headers=current_headers, data=f, allow_redirects=False)
            if upload_res.status_code in (301, 302, 307, 308):
                loc = upload_res.headers.get("Location") or upload_res.headers.get("location")
                if not loc:
                    print(f"[WARN] Redirect response {upload_res.status_code} without Location header: {upload_res.headers}")
                    break
                target_url = loc
                print(f"[INFO] Following redirect ({upload_res.status_code}) to storage...")
                if "objects.githubusercontent.com" in target_url or "amazonaws.com" in target_url or "s3" in target_url:
                    current_headers.pop("Authorization", None)
                continue
            break
            
        if upload_res.status_code in (200, 201):
            asset_info = upload_res.json() if upload_res.text else {}
            print(f"[SUCCESS] Uploaded {asset_name} successfully!")
            if asset_info.get('browser_download_url'):
                print(f"[DOWNLOAD URL] {asset_info.get('browser_download_url')}")
        else:
            raise RuntimeError(f"Failed to upload asset {asset_name}: {upload_res.status_code} - {upload_res.text}")


def step_push_git_tag(cwd, branch, commit_msg, tag):
    print("\n==========================================")
    print(f"Pushing Git changes & Tag {tag} to ({branch})")
    print("==========================================")
    
    status_res = run_cmd("git status --porcelain", cwd=cwd, check=False)
    has_changes = bool(status_res.stdout.strip())
    
    if has_changes:
        print("[INFO] Staging modified files...")
        run_cmd("git add -A", cwd=cwd)
        msg = commit_msg or f"chore(release): {tag}"
        print(f"[INFO] Committing with message: {msg}")
        run_cmd(f'git commit -m "{msg}"', cwd=cwd)
    else:
        print("[INFO] No working tree changes to commit.")
        
    print(f"[INFO] Pushing commits to origin/{branch}...")
    run_cmd(f"git push origin {branch}", cwd=cwd)
    
    if tag:
        tag_check = run_cmd(f"git tag -l {tag}", cwd=cwd, check=False)
        if not tag_check.stdout.strip():
            print(f"[INFO] Creating local git tag {tag}...")
            run_cmd(f'git tag -a {tag} -m "Release {tag}"', cwd=cwd)
        print(f"[INFO] Pushing tag {tag} to origin...")
        run_cmd(f"git push origin {tag}", cwd=cwd, check=False)
        
    print("[SUCCESS] Git commit & tag pushed successfully.")


def main():
    parser = argparse.ArgumentParser(description="Automate Git tagging to trigger GitHub Actions CI/CD Release.")
    parser.add_argument("--cwd", default=os.getcwd(), help="Workspace directory")
    parser.add_argument("--tag", default=None, help="Release tag name (e.g. v1.0.78)")
    parser.add_argument("--commit-msg", default=None, help="Git commit message")
    parser.add_argument("--no-bump", action="store_true", help="Do not bump pubspec.yaml version")
    parser.add_argument("--build-local", action="store_true", help="Perform build locally instead of delegating to GitHub Actions")
    parser.add_argument("--title", default=None, help="Release title (for local build)")
    parser.add_argument("--notes", default=None, help="Release notes (for local build)")
    parser.add_argument("--token", default=None, help="GitHub token (for local build)")
    
    args = parser.parse_args()
    cwd = os.path.abspath(args.cwd)
    
    # 1. Quản lý version
    if not args.no_bump:
        ver_name, tag = bump_pubspec_version(cwd, args.tag)
    else:
        ver_name, _ = get_pubspec_version(cwd)
        tag = args.tag or f"v{ver_name}"
        
    git_info = get_git_info(cwd)
    owner = git_info["owner"]
    repo = git_info["repo"]
    branch = git_info["branch"]
    
    print(f"Target Repo: {owner}/{repo}")
    print(f"Target Branch: {branch}")
    print(f"Release Tag: {tag} (Version: {ver_name})")
    
    # 2. Nếu không yêu cầu build local -> Phương thức 1: Git push & Tag để GitHub Actions tự build CI/CD
    if not args.build_local:
        commit_msg = args.commit_msg or f"chore(release): bump version to {tag}"
        step_push_git_tag(cwd=cwd, branch=branch, commit_msg=commit_msg, tag=tag)
        
        print("\n=======================================================")
        print(f"🚀 GITHUB ACTIONS CI/CD ĐÃ ĐƯỢC KÍCH HOẠT TỰ ĐỘNG!")
        print("=======================================================")
        print(f"Tag {tag} đã được push lên GitHub.")
        print(f"GitHub Actions runner sẽ tự động biên dịch APK ARM64 release và tạo GitHub Release:")
        print(f"👉 Theo dõi tiến trình tại: https://github.com/{owner}/{repo}/actions")
        print(f"👉 Link Release sau khi build xong: https://github.com/{owner}/{repo}/releases/tag/{tag}")
        print("=======================================================")
        return

    # 3. Chế độ Build Local (nếu truyền flag --build-local)
    token = args.token or git_info["token"]
    apk_paths = step1_build_apk(cwd, tag)
    step2_push_github_release(
        cwd=cwd,
        apk_paths=apk_paths,
        tag=tag,
        title=args.title or f"Release {tag}",
        notes=args.notes or f"Release {tag} - StorySum Android ARM64 Release",
        token=token,
        owner=owner,
        repo=repo
    )
    commit_msg = args.commit_msg or f"release: {tag} - update release APKs and code changes"
    step_push_git_tag(cwd=cwd, branch=branch, commit_msg=commit_msg, tag=tag)
    
    print("\n==========================================")
    print("🎉 ALL STEPS COMPLETED SUCCESSFULLY (LOCAL BUILD)!")
    print("==========================================")


if __name__ == "__main__":
    main()
