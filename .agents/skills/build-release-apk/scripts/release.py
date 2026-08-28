"""
Helper script to automate Flutter ARM64 Release Build, GitHub Release Upload, and Git Push.
"""

import argparse
import os
import re
import subprocess
import sys
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
    
    # Pattern: https://<token>@github.com/<owner>/<repo>.git or git@github.com:<owner>/<repo>.git or https://github.com/<owner>/<repo>.git
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
            
    # Check env var for token if not in URL
    if not token or token == "git":
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        
    branch_res = run_cmd("git rev-parse --abbrev-ref HEAD", cwd=cwd)
    branch = branch_res.stdout.strip() or "main"
    
    return {"url": url, "token": token, "owner": owner, "repo": repo, "branch": branch}


def get_pubspec_version(cwd):
    pubspec_path = os.path.join(cwd, "pubspec.yaml")
    if not os.path.exists(pubspec_path):
        return "1.0.0"
    with open(pubspec_path, "r", encoding="utf-8") as f:
        content = f.read()
    match = re.search(r"^version:\s*([^\s\r\n]+)", content, re.MULTILINE)
    if match:
        full_ver = match.group(1)
        # 1.0.2+3 -> ver_name=1.0.2
        ver_name = full_ver.split("+")[0]
        return ver_name, full_ver
    return "1.0.0", "1.0.0+1"


def step1_build_apk(cwd):
    print("\n==========================================")
    print("STEP 1: Building Release APK (ARM64 only)")
    print("==========================================")
    
    built_apks = []
    
    # Build Split ARM64 APK (Tối ưu riêng cho máy Android ARM64 64-bit)
    print("\n[INFO] Building ARM64-v8a Split APK...")
    build_arm64_cmd = "flutter build apk --release --target-platform android-arm64 --split-per-abi"
    run_cmd(build_arm64_cmd, cwd=cwd)
    
    arm64_apk = os.path.join(cwd, "build", "app", "outputs", "flutter-apk", "app-arm64-v8a-release.apk")
    if os.path.exists(arm64_apk):
        size_mb = os.path.getsize(arm64_apk) / (1024 * 1024)
        print(f"[SUCCESS] ARM64 APK: {arm64_apk} ({size_mb:.2f} MB)")
        built_apks.append(arm64_apk)

    if not built_apks:
        raise FileNotFoundError("Cannot find built ARM64 APK in build/app/outputs/flutter-apk")
        
    return built_apks


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
    
    # 1. Check if release exists
    rel_url = f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{tag}"
    res = requests.get(rel_url, headers=headers)
    
    if res.status_code == 200:
        release_data = res.json()
        release_id = release_data["id"]
        print(f"[INFO] Found existing release for tag {tag} (ID: {release_id})")
    elif res.status_code == 404:
        # Create release
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
        create_res = requests.post(create_url, headers=headers, json=payload)
        if create_res.status_code not in (200, 201):
            raise RuntimeError(f"Failed to create release: {create_res.status_code} - {create_res.text}")
        release_data = create_res.json()
        release_id = release_data["id"]
        print(f"[SUCCESS] Created release {tag} (ID: {release_id})")
    else:
        raise RuntimeError(f"Error querying release: {res.status_code} - {res.text}")
        
    # 2. Upload each asset
    existing_assets = {a["name"]: a["id"] for a in release_data.get("assets", [])}
    
    for apk_path in apk_paths:
        asset_name = os.path.basename(apk_path)
        if asset_name in existing_assets:
            print(f"[INFO] Asset {asset_name} already exists (ID: {existing_assets[asset_name]}). Deleting old asset...")
            del_url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{existing_assets[asset_name]}"
            del_res = requests.delete(del_url, headers=headers)
            if del_res.status_code == 204:
                print(f"[INFO] Deleted old {asset_name} successfully.")
            else:
                print(f"[WARN] Failed to delete old {asset_name}: {del_res.status_code}")
                    
        upload_url = f"https://uploads.github.com/repos/{owner}/{repo}/releases/{release_id}/assets?name={asset_name}"
        upload_headers = {
            "Authorization": f"token {token}",
            "Content-Type": "application/vnd.android.package-archive",
            "User-Agent": "SummaryStory-ReleaseScript"
        }
        
        print(f"[INFO] Uploading {asset_name} to release...")
        with open(apk_path, "rb") as f:
            upload_res = requests.post(upload_url, headers=upload_headers, data=f)
            
        if upload_res.status_code in (200, 201):
            asset_info = upload_res.json()
            print(f"[SUCCESS] Uploaded {asset_name} successfully!")
            print(f"[DOWNLOAD URL] {asset_info.get('browser_download_url')}")
        else:
            raise RuntimeError(f"Failed to upload asset {asset_name}: {upload_res.status_code} - {upload_res.text}")


def step3_push_git(cwd, branch, commit_msg, tag=None):
    print("\n==========================================")
    print(f"STEP 3: Pushing code changes to Git ({branch})")
    print("==========================================")
    
    status_res = run_cmd("git status --porcelain", cwd=cwd, check=False)
    has_changes = bool(status_res.stdout.strip())
    
    if has_changes:
        print("[INFO] Staging modified files...")
        run_cmd("git add -A", cwd=cwd)
        msg = commit_msg or "build(release): update release build and code changes"
        print(f"[INFO] Committing with message: {msg}")
        run_cmd(f'git commit -m "{msg}"', cwd=cwd)
    else:
        print("[INFO] No working tree changes to commit.")
        
    print(f"[INFO] Pushing commits to origin/{branch}...")
    run_cmd(f"git push origin {branch}", cwd=cwd)
    
    if tag:
        # Check if local tag exists
        tag_check = run_cmd(f"git tag -l {tag}", cwd=cwd, check=False)
        if not tag_check.stdout.strip():
            print(f"[INFO] Creating local git tag {tag}...")
            run_cmd(f'git tag -a {tag} -m "Release {tag}"', cwd=cwd)
        print(f"[INFO] Pushing tag {tag} to origin...")
        run_cmd(f"git push origin {tag}", cwd=cwd, check=False)
        
    print("[SUCCESS] Git push completed successfully.")


def main():
    parser = argparse.ArgumentParser(description="Build Flutter Release APKs, publish GitHub Release, and push Git changes.")
    parser.add_argument("--cwd", default=os.getcwd(), help="Workspace directory")
    parser.add_argument("--tag", default=None, help="Release tag name (e.g. v1.0.3)")
    parser.add_argument("--title", default=None, help="Release title")
    parser.add_argument("--notes", default=None, help="Release notes")
    parser.add_argument("--commit-msg", default=None, help="Git commit message")
    parser.add_argument("--token", default=None, help="GitHub token")
    parser.add_argument("--skip-build", action="store_true", help="Skip APK build step")
    parser.add_argument("--skip-release", action="store_true", help="Skip GitHub release upload")
    parser.add_argument("--skip-git", action="store_true", help="Skip Git commit & push")
    
    args = parser.parse_args()
    cwd = os.path.abspath(args.cwd)
    
    ver_name, full_ver = get_pubspec_version(cwd)
    tag = args.tag or f"v{ver_name}"
    
    git_info = get_git_info(cwd)
    token = args.token or git_info["token"]
    owner = git_info["owner"]
    repo = git_info["repo"]
    branch = git_info["branch"]
    
    print(f"Target Repo: {owner}/{repo}")
    print(f"Target Branch: {branch}")
    print(f"Target Tag: {tag}")
    
    apk_paths = []
    if not args.skip_build:
        apk_paths = step1_build_apk(cwd)
    else:
        apk_dir = os.path.join(cwd, "build", "app", "outputs", "flutter-apk")
        for f in os.listdir(apk_dir) if os.path.exists(apk_dir) else []:
            if f.endswith("-release.apk") or f == "app-release.apk":
                apk_paths.append(os.path.join(apk_dir, f))
        print(f"[INFO] Skipping build. Found existing APKs: {apk_paths}")
        
    if not args.skip_release:
        step2_push_github_release(
            cwd=cwd,
            apk_paths=apk_paths,
            tag=tag,
            title=args.title or f"Release {tag}",
            notes=args.notes or f"Release {tag} - Universal APK (cho mọi loại máy) & ARM64 APK",
            token=token,
            owner=owner,
            repo=repo
        )
        
    if not args.skip_git:
        commit_msg = args.commit_msg or f"release: {tag} - update release APKs and code changes"
        step3_push_git(cwd=cwd, branch=branch, commit_msg=commit_msg, tag=tag)
        
    print("\n==========================================")
    print("🎉 ALL STEPS COMPLETED SUCCESSFULLY!")
    print("==========================================")


if __name__ == "__main__":
    main()
