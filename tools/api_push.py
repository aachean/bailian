#!/usr/bin/env python3
"""走 GitHub API 推送本地 main（git 传输被墙时的备用通道）。

    <python> tools/api_push.py

## 什么时候要用它

本机到 `github.com:443` 的 git 传输**时通时断**（`Recv failure: Connection was reset`
或直接连不上），而 `git push` 撞上就是白跑一趟。`api.github.com` 则是通的。
本仓库历史上靠一个叫 `github-api-push` 的技能做这件事 —— 那是别的工作台的东西，
在标准 Claude Code 里没有。这个脚本就是它的替代。

判断顺序：**先试 `git push`，失败了再跑这个**（git 传输通了就没必要绕）。

## 为什么要「忠实复刻」而不是重建

朴素做法是「用 API 建一个新提交」，那条路的代价是：远端会得到一个**内容相同但 SHA
不同**的提交。于是本地与远端**分叉**了，之后再想 `git push` / `git pull` 就要先
`reset` 或 `merge`，还容易在历史上留下两个一模一样的提交。

所以要**照抄**本地 commit 对象的每一个字节：tree、parent、author、committer
（含时间戳与时区）、message（含结尾换行）。这样复刻出的 SHA 与本地**逐位相同**，
本地和远端不分叉。

**复刻不成功就立刻停，一个字都不动 ref** —— 宁可这次没推成，也不要在远端留下
一个和本地不一样的影子提交。收尾打印的「SHA 对齐」就是这个自检的结论。

## 已验证的前提

- `gh` 已认证（脚本用 `gh auth token` 取令牌，读 `repo` 权限）
- `api.github.com` 可达
- 本仓库是**公开**的（读取无需凭据，写入才要 —— 所以 `git ls-remote` 通不代表能 push）

一次可以推多个提交（`远端..本地` 全部），逐个复刻、逐个校验。
"""

from __future__ import annotations

import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
SLUG = "aachean/bailian"
BRANCH = "main"
API = "https://api.github.com"

# 输出里有中文和 ✅ —— 控制台默认 GBK 会直接崩在最后一行 print 上
# （而且那是最气人的位置：推送已经成功、ref 已经动了，只是打印挂了）
sys.stdout.reconfigure(encoding="utf-8")


def git(*args: str, binary: bool = False):
    """跑 git。**一律按 UTF-8 解码** —— Windows 默认按 GBK 读会把中文提交消息弄坏"""
    out = subprocess.check_output(["git", *args], cwd=REPO_DIR)
    return out if binary else out.decode("utf-8")


def api(method: str, path: str, payload: dict | None = None) -> dict:
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(
        API + path,
        method=method,
        data=body,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "bailian-api-push",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        raise SystemExit("API %s %s -> %d\n%s"
                         % (method, path, exc.code, exc.read().decode("utf-8", "replace"))) from exc


def meta(rev: str) -> dict:
    """一个提交的「照抄件」：消息 + 作者 + 提交者。全从 git 里取，不自己拼"""
    return {
        # 消息**原样取**（裸 commit 对象里第一个空行之后的全部，含结尾换行）——
        # 用 %B 或 log 会被 git 顺一遍格式，差一个字节 SHA 就不一样
        "message": git("cat-file", "commit", rev).partition("\n\n")[2],
        "author": {
            "name": git("log", "-1", "--format=%an", rev).strip(),
            "email": git("log", "-1", "--format=%ae", rev).strip(),
            "date": git("log", "-1", "--format=%aI", rev).strip(),   # ISO 8601 严格格式，带时区
        },
        "committer": {
            "name": git("log", "-1", "--format=%cn", rev).strip(),
            "email": git("log", "-1", "--format=%ce", rev).strip(),
            "date": git("log", "-1", "--format=%cI", rev).strip(),
        },
    }


token = subprocess.check_output(["gh", "auth", "token"]).decode("utf-8").strip()

local = git("rev-parse", "HEAD").strip()
remote = api("GET", "/repos/%s/git/ref/heads/%s" % (SLUG, BRANCH))["object"]["sha"]
print("本地 HEAD        :", local)
print("远端 %-11s: %s" % (BRANCH, remote))

if remote == local:
    print(">>> 已经对齐，无需推送")
    sys.exit(0)

try:
    todo = git("rev-list", "--reverse", "%s..%s" % (remote, local)).split()
except subprocess.CalledProcessError:
    raise SystemExit("远端不是本地的祖先（远端=%s）—— 本地可能落后或已分叉，先人工核对"
                     % remote[:8])
if not todo:
    raise SystemExit("本地没有领先远端的提交，但对不上 —— 状态可疑，先人工核对")
print("要推的提交        : %d 个" % len(todo))

# 逐个复刻；**全部成功之前不动 ref**，中途任何一步对不上就整个停下
head = remote
for rev in todo:
    parent = git("rev-parse", "%s^" % rev).strip()
    if parent != head:
        raise SystemExit("链条断了：%s 的父提交是 %s，但上一个复刻出来的是 %s —— 已停止，ref 未改动"
                         % (rev[:8], parent[:8], head[:8]))

    changed = [p for p in git("diff", "--name-only", parent, rev).splitlines() if p]
    if not changed:
        raise SystemExit("%s 与父提交没有文件差异，构造不出提交树 —— 已停止" % rev[:8])

    base_tree = api("GET", "/repos/%s/git/commits/%s" % (SLUG, head))["tree"]["sha"]
    blobs = {}
    for path in changed:
        data = git("show", "%s:%s" % (rev, path), binary=True)
        blobs[path] = api("POST", "/repos/%s/git/blobs" % SLUG, {
            "content": base64.b64encode(data).decode("ascii"),
            "encoding": "base64",
        })["sha"]

    tree = api("POST", "/repos/%s/git/trees" % SLUG, {
        "base_tree": base_tree,
        "tree": [{"path": p, "mode": "100644", "type": "blob", "sha": blobs[p]} for p in changed],
    })["sha"]

    info = meta(rev)
    made = api("POST", "/repos/%s/git/commits" % SLUG, {
        "message": info["message"],
        "tree": tree,
        "parents": [head],
        "author": info["author"],
        "committer": info["committer"],
    })["sha"]

    # 这一条是整套做法成立的前提：复刻必须逐位一致，否则远端就多了一个影子提交
    if made != rev:
        raise SystemExit("复刻 %s 得到的却是 %s —— 已停止，ref 未改动" % (rev[:8], made[:8]))
    print("  复刻 %s  %s" % (rev[:8], info["message"].splitlines()[0]))
    head = made

api("PATCH", "/repos/%s/git/refs/heads/%s" % (SLUG, BRANCH), {"sha": head, "force": False})

after = api("GET", "/repos/%s/git/ref/heads/%s" % (SLUG, BRANCH))["object"]["sha"]
print("推送后远端        :", after)
print(">>> SHA 对齐: %s" % ("全部一致 ✅" if after == local else "不一致 ❌"))
sys.exit(0 if after == local else 1)
