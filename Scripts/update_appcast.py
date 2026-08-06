#!/usr/bin/env python3
"""Prepend a release to appcast.xml, the feed Sparkle reads.

Kept as a small script rather than Sparkle's `generate_appcast` because that
tool wants a directory containing every past DMG. CI only has the one it just
built, and re-downloading the whole release history on every tag to regenerate
a file we already have is wasted work.

Usage: see Scripts/update_appcast.py --help
"""

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

EMPTY_FEED = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Ration</title>
    <link>https://raw.githubusercontent.com/mcpeixoto/ration/main/appcast.xml</link>
    <description>Updates for Ration, a menu bar meter for Claude usage.</description>
    <language>en</language>
  </channel>
</rss>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Marketing version, e.g. 0.2.0")
    parser.add_argument("--build", required=True, help="Monotonic build number")
    parser.add_argument("--url", required=True, help="Download URL for the DMG")
    parser.add_argument("--length", required=True, help="DMG size in bytes")
    parser.add_argument("--signature", required=True, help="EdDSA signature from sign_update")
    parser.add_argument("--pubdate", required=True, help="RFC 822 publication date")
    parser.add_argument("--feed", default="appcast.xml")
    parser.add_argument(
        "--minimum-system-version", default="14.0", help="Oldest macOS this build supports"
    )
    args = parser.parse_args()

    feed = Path(args.feed)
    if not feed.exists():
        feed.write_text(EMPTY_FEED)

    tree = ET.parse(feed)
    channel = tree.getroot().find("channel")
    if channel is None:
        raise SystemExit("appcast.xml has no <channel>")

    # Replacing rather than appending keeps a re-run of the same tag idempotent.
    for existing in channel.findall("item"):
        version = existing.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if version is not None and version.text == args.version:
            channel.remove(existing)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = args.pubdate
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = args.build
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = args.version
    ET.SubElement(
        item, f"{{{SPARKLE_NS}}}minimumSystemVersion"
    ).text = args.minimum_system_version
    ET.SubElement(item, "link").text = (
        f"https://github.com/mcpeixoto/ration/releases/tag/v{args.version}"
    )

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", args.url)
    enclosure.set("length", str(args.length))
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", args.signature)

    # Newest first — Sparkle picks the highest version, but humans read top-down.
    channel.insert(len(list(channel.findall("*"))) - len(channel.findall("item")), item)

    ET.indent(tree, space="  ")
    tree.write(feed, encoding="utf-8", xml_declaration=True)
    print(f"appcast.xml now advertises {args.version} (build {args.build})")


if __name__ == "__main__":
    main()
