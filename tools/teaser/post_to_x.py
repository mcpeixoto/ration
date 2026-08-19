"""Post the teaser to X. Needs OAuth 1.0a user keys with write access.

  export X_CONSUMER_KEY=... X_CONSUMER_SECRET=... X_ACCESS_TOKEN=... X_ACCESS_SECRET=...
  .venv/bin/python post_to_x.py --dry-run      # checks auth + prints the tweet
  .venv/bin/python post_to_x.py                # actually posts

Chunked upload (v1.1 media/upload) then POST /2/tweets with the media id.
"""
import argparse
import os
import sys
import time

import requests
from requests_oauthlib import OAuth1

VIDEO = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'ration-teaser-1x1.mp4')
TEXT = (
    "Your AI coding usage is now a Pokédex.\n\n"
    "Ration puts live plan limits for Claude Code, Codex and Cursor in the macOS menu bar — "
    "and every token you burn unlocks one of 50 collectible creature cards. "
    "Native SwiftUI, ~5MB, all local, no telemetry.\n\n"
    "Free · open source: github.com/mcpeixoto/ration"
)
UPLOAD = 'https://upload.twitter.com/1.1/media/upload.json'
TWEETS = 'https://api.twitter.com/2/tweets'
CHUNK = 4 * 1024 * 1024


def auth():
    keys = [os.environ.get(k) for k in
            ('X_CONSUMER_KEY', 'X_CONSUMER_SECRET', 'X_ACCESS_TOKEN', 'X_ACCESS_SECRET')]
    if not all(keys):
        sys.exit('missing X_CONSUMER_KEY / X_CONSUMER_SECRET / X_ACCESS_TOKEN / X_ACCESS_SECRET')
    return OAuth1(*keys)


def upload_video(a, path):
    size = os.path.getsize(path)
    r = requests.post(UPLOAD, auth=a, data={
        'command': 'INIT', 'total_bytes': size,
        'media_type': 'video/mp4', 'media_category': 'tweet_video'})
    r.raise_for_status()
    mid = r.json()['media_id_string']
    with open(path, 'rb') as f:
        i = 0
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                break
            requests.post(UPLOAD, auth=a,
                          data={'command': 'APPEND', 'media_id': mid, 'segment_index': i},
                          files={'media': chunk}).raise_for_status()
            print(f'  chunk {i} ({(i + 1) * CHUNK / 1e6:.0f}/{size / 1e6:.0f} MB)')
            i += 1
    r = requests.post(UPLOAD, auth=a, data={'command': 'FINALIZE', 'media_id': mid})
    r.raise_for_status()
    info = r.json().get('processing_info', {})
    while info.get('state') in ('pending', 'in_progress'):
        time.sleep(info.get('check_after_secs', 5))
        r = requests.get(UPLOAD, auth=a, params={'command': 'STATUS', 'media_id': mid})
        r.raise_for_status()
        info = r.json().get('processing_info', {})
        print('  transcoding:', info.get('state'), info.get('progress_percent', ''))
    if info.get('state') == 'failed':
        sys.exit(f'X rejected the video: {info}')
    return mid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--text', default=TEXT)
    args = ap.parse_args()
    a = auth()
    me = requests.get('https://api.twitter.com/2/users/me', auth=a)
    print('account:', me.status_code, me.text[:200])
    print('---- tweet text ----')
    print(args.text)
    print('--------------------')
    if args.dry_run:
        return
    print('uploading', VIDEO)
    mid = upload_video(a, VIDEO)
    r = requests.post(TWEETS, auth=a,
                      json={'text': args.text, 'media': {'media_ids': [mid]}})
    print(r.status_code, r.text)
    r.raise_for_status()


if __name__ == '__main__':
    main()
