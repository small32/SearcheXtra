#!/usr/bin/env python3
"""A link's right-click menu, in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/link_menu.py`. The right
button is pressed on a link through the page's own view, and the item is
chosen as the menu comes up (the bench's linkmenu), so WebKit makes the tab
as it does for a hand; no window is made or shown.
"""
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

# Its own world, apart from the split suite's in this checkout (see use()).
sv.use("link-menu")

LINK = ("document.body.innerHTML = '<a href=\"{}\" style=\"display:block;"
        "font-size:60px;line-height:120px;padding:0 20px\">a link</a>'; true")

# A link whose whole face is a picture, as a grid of posts has: the picture
# drawn here, so it is a real one, wrapped as such a grid wraps it.
PICTURE = """(function () {{
  var c = document.createElement('canvas'); c.width = 200; c.height = 200;
  c.getContext('2d').fillRect(0, 0, 200, 200);
  document.body.innerHTML = '<a href="{}"><div><picture><img style="display:block;width:200px;height:200px" src="'
    + c.toDataURL() + '"></picture></div></a>';
  return true;
}})()"""


def menu(tab, pick):
    sv.ev(tab, LINK.format(f"{sv.BASE}/{pick[1]}")); time.sleep(0.3)
    return sv.cmd({"do": "linkmenu", "id": tab, "x": 60, "y": 60, "pick": pick[0]})


def setup(language="en", **prefs):
    sv.setup(**prefs)
    subprocess.run(["defaults", "write", sv.SUITE, "interface.language", "-string", language], check=True)
    sv.launch()


def main():
    t = sv.T()
    try:
        setup()
        a = sv.page("a"); b = sv.page("b")
        sv.sp("select", id=a); time.sleep(0.4)
        r = menu(a, ("Open Link in New Tab", "behind"))
        new = [x for x, u in zip(r["tabs"], r["urls"]) if u.endswith("/behind")]
        t.ok("Open Link in New Tab: a new tab for the link", len(new) == 1, r)
        t.ok("it stays behind: the tab you were on is still in front", r["active"] == a, r)
        t.ok("it goes just after the tab it came from, as a ⌘-click's does",
             bool(new) and r["tabs"].index(new[0]) == r["tabs"].index(a) + 1, r["tabs"])
        r = menu(a, ("Open Link in New Tab and Go to It", "front"))
        new = [x for x, u in zip(r["tabs"], r["urls"]) if u.endswith("/front")]
        t.ok("with ⌥, Open Link in New Tab and Go to It: the new tab is in front",
             len(new) == 1 and r["active"] == new[0], r)
        t.ok("b is untouched", b in r["tabs"], r["tabs"])
        # The picture's own menu stands in for WebKit's only where there is
        # no link: on a link's picture, the link's items are there too.
        sv.sp("select", id=a); time.sleep(0.4)
        sv.ev(a, PICTURE.format(f"{sv.BASE}/pictured")); time.sleep(0.3)
        r = sv.cmd({"do": "linkmenu", "id": a, "x": 60, "y": 60, "pick": "Open Link in New Tab"})
        t.ok("a link's picture: Open Link in New Tab opens the link",
             any(u.endswith("/pictured") for u in r["urls"]), r["urls"])
    finally:
        sv.finish()
    try:
        setup(splitView=True)
        a = sv.page("a"); b = sv.page("b")
        sv.sp("select", id=a); time.sleep(0.4)
        menu(a, ("Open Link in Split View", "beside")); time.sleep(0.5)
        st = sv.sp("state")
        new = [x["id"] for x in st["tabs"] if x["url"].endswith("/beside")]
        t.ok("split opens a tab for the link", len(new) == 1, st["tabs"])
        t.ok("split opens on the right of the source", bool(new) and any(s["tabs"] == [a, new[0]] for s in st["splits"]), st["splits"])
        t.ok("the opened page has focus", bool(new) and st["activeID"] == new[0], st["activeID"])
        sv.sp("select", id=b); time.sleep(0.4)
        front = menu(b, ("Open Link in New Tab and Go to It", "front"))
        front_ids = [x for x, u in zip(front["tabs"], front["urls"]) if u.endswith("/front")]
        t.ok("foreground alternate still works", len(front_ids) == 1 and front["active"] == front_ids[0], front)
        sv.sp("select", id=a); time.sleep(0.4)
        menu(a, ("Open Link in Split View", "again")); time.sleep(0.5)
        st = sv.sp("state")
        again = [x["id"] for x in st["tabs"] if x["url"].endswith("/again")]
        t.ok("opening from a pair replaces its other side", bool(again) and any(s["tabs"] == [a, again[0]] for s in st["splits"]), st["splits"])
        t.ok("the replaced page stays open", bool(new) and new[0] in [x["id"] for x in st["tabs"]] and not any(new[0] in s["tabs"] for s in st["splits"]), st)
        p = sv.page("pinned"); sv.cmd({"do": "pin", "id": p}); sv.sp("select", id=p); time.sleep(0.4)
        menu(p, ("Open Link in Split View", "frompin")); time.sleep(0.8)
        st = sv.sp("state")
        frompin = [x["id"] for x in st["tabs"] if x["url"].endswith("/frompin")]
        pair = next((s for s in st["splits"] if frompin and frompin[0] in s["tabs"]), None)
        t.ok("a pinned page keeps its pin while the link opens in a pair", pair is not None and p not in pair["tabs"], st["splits"])
        sv.sp("enabled", on=False); time.sleep(0.3)
        result = menu(b, ("Open Link in Split View", "nowhere"))
        t.ok("the split action is unavailable when split view is off", not any(u.endswith("/nowhere") for u in result["urls"]), result["urls"])
    finally:
        sv.finish()
    try:
        setup(language="zh-Hans", splitView=True)
        a = sv.page("zh"); sv.sp("select", id=a); time.sleep(0.4)
        menu(a, ("在分屏中打开链接", "zh-split")); time.sleep(0.5)
        st = sv.sp("state")
        result = [x["id"] for x in st["tabs"] if x["url"].endswith("/zh-split")]
        t.ok("Chinese menu opens the link in split view", bool(result) and any(s["tabs"] == [a, result[0]] for s in st["splits"]), st["splits"])
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
