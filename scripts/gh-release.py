#!/usr/bin/env python3
"""创建 GitHub Release 并上传附件。

不依赖 gh CLI，直接走 GitHub REST API。凭据从 git 的 credential helper 取
（macOS 上就是 Keychain），也可以传环境变量 GITHUB_TOKEN。

用法：
    python3 scripts/gh-release.py <tag> <name> <notes-file> <zip> [repo]

repo 形如 owner/repo；不传则从 origin remote 推断。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"


def token() -> str:
    t = os.environ.get("GITHUB_TOKEN")
    if t:
        return t.strip()
    out = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        capture_output=True, text=True,
    ).stdout
    m = re.search(r"^password=(.*)$", out, re.M)
    if not m:
        sys.exit("error: 取不到 GitHub 凭据（试过 GITHUB_TOKEN 与 git credential）")
    return m.group(1).strip()


def repo() -> str:
    if len(sys.argv) > 5 and sys.argv[5]:
        return sys.argv[5]
    url = subprocess.run(["git", "remote", "get-url", "origin"],
                         capture_output=True, text=True).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    if not m:
        sys.exit(f"error: 无法从 origin 推断仓库：{url}")
    return m.group(1)


def request(method: str, url: str, tok: str, **kw):
    req = urllib.request.Request(url, method=method, **kw)
    req.add_header("Authorization", f"Bearer {tok}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__)
        return 2

    tag, name, notes_file, zip_path = sys.argv[1:5]
    tok = token()
    slug = repo()

    # 已存在就直接用（重复发版时不用先删）
    status, body = request("GET", f"{API}/repos/{slug}/releases/tags/{tag}", tok)
    if status == 200:
        rel = json.loads(body)
        print(f"Release {tag} 已存在，直接上传附件")
    else:
        payload = json.dumps({
            "tag_name": tag,
            "name": name,
            "body": open(notes_file, encoding="utf-8").read(),
            "draft": False,
            "prerelease": False,
        }, ensure_ascii=False).encode()
        status, body = request(
            "POST", f"{API}/repos/{slug}/releases", tok,
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        if status != 201:
            print(f"error: 创建 Release 失败 HTTP {status}\n{body.decode()[:400]}")
            return 1
        rel = json.loads(body)
        print(f"已创建 Release：{rel['html_url']}")

    upload_url = rel["upload_url"].split("{")[0]
    fname = os.path.basename(zip_path)
    with open(zip_path, "rb") as f:
        data = f.read()
    status, body = request(
        "POST", f"{upload_url}?name={fname}", tok, data=data,
        headers={"Content-Type": "application/zip"},
    )
    if status != 201:
        print(f"error: 上传附件失败 HTTP {status}\n{body.decode()[:400]}")
        return 1
    asset = json.loads(body)
    print(f"已上传 {asset['name']}（{asset['size'] / 1048576:.2f} MB）")
    print(f"下载：{asset['browser_download_url']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
