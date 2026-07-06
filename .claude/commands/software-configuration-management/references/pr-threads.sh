#!/usr/bin/env bash
# pr-threads — show all PR comment threads with full bodies.
#
# Usage: pr-threads <PR_NUMBER>
#
# Fetches and formats:
#   1. Submitted inline review comment threads  (/pulls/{pr}/comments)
#   2. Submitted reviews with a non-empty review body  (/pulls/{pr}/reviews)
#   3. PR-level issue comments  (/issues/{pr}/comments)
#   4. The AUTHENTICATED user's own pending review, if any, including
#      its inline comments  (/pulls/{pr}/reviews/{id}/comments)
#
# Limitation: pending reviews by OTHER users are not exposed by the GitHub
# API and will not appear here.  To see a reviewer's pending threads, the
# reviewer must either submit the review or run this script while authenticated
# as themselves (gh auth switch --user <reviewer-login>).

set -euo pipefail

PR="${1:?Usage: pr-threads <PR_NUMBER>}"
OWNER_REPO="$(gh repo view --json owner,name -q '.owner.login + "/" + .name')"
ME="$(gh api user --jq '.login')"

python3 - "$OWNER_REPO" "$PR" "$ME" <<'PYEOF'
import subprocess, json, sys, textwrap

owner_repo, pr, me = sys.argv[1], sys.argv[2], sys.argv[3]

SEP  = '-' * 72
DSEP = '=' * 72
W    = 72

def fetch(path):
    """Fetch one page (up to 100 items) from the GitHub API."""
    sep = '&' if '?' in path else '?'
    r = subprocess.run(
        ['gh', 'api', f'{path}{sep}per_page=100'],
        capture_output=True, text=True, check=True,
    )
    return json.loads(r.stdout)

def fetch_all(path):
    """Fetch all pages via gh --paginate; returns a flat list."""
    sep = '&' if '?' in path else '?'
    r = subprocess.run(
        ['gh', 'api', '--paginate', f'{path}{sep}per_page=100'],
        capture_output=True, text=True, check=True,
    )
    # gh --paginate concatenates JSON arrays without a separator.
    # Replace '][' boundaries so we can parse as one array.
    text = r.stdout.strip()
    text = text.replace('][', ',')
    return json.loads(text)

def fmt_body(body, indent=''):
    """Wrap and indent a comment body."""
    lines = body.splitlines()
    out = []
    for line in lines:
        if line.strip() == '':
            out.append('')
        else:
            wrapped = textwrap.wrap(line, width=W - len(indent)) or ['']
            out.extend(indent + l for l in wrapped)
    return '\n'.join(out)

# ── 1. Submitted inline review comments ──────────────────────────────────────
inline = fetch_all(f'repos/{owner_repo}/pulls/{pr}/comments')

roots = {}
for c in inline:
    if not c.get('in_reply_to_id'):
        roots[c['id']] = {'root': c, 'replies': []}
for c in inline:
    pid = c.get('in_reply_to_id')
    if pid and pid in roots:
        roots[pid]['replies'].append(c)

# ── 2. Submitted reviews ──────────────────────────────────────────────────────
reviews = fetch_all(f'repos/{owner_repo}/pulls/{pr}/reviews')
submitted  = [rv for rv in reviews if rv.get('state') != 'PENDING']
pending_me = [rv for rv in reviews if rv.get('state') == 'PENDING'
              and rv.get('user', {}).get('login') == me]
pending_others_count = sum(
    1 for rv in reviews
    if rv.get('state') == 'PENDING' and rv.get('user', {}).get('login') != me
)
reviews_with_body = [rv for rv in submitted if rv.get('body', '').strip()]

# ── 3. PR-level issue comments ────────────────────────────────────────────────
issue_comments = fetch_all(f'repos/{owner_repo}/issues/{pr}/comments')

# ── 4. Authenticated user's pending review inline comments ───────────────────
pending_inline = []
for rv in pending_me:
    items = fetch_all(f'repos/{owner_repo}/pulls/{pr}/reviews/{rv["id"]}/comments')
    pending_inline.extend(items)
pending_roots = {}
for c in pending_inline:
    if not c.get('in_reply_to_id'):
        pending_roots[c['id']] = {'root': c, 'replies': []}
for c in pending_inline:
    pid = c.get('in_reply_to_id')
    if pid and pid in pending_roots:
        pending_roots[pid]['replies'].append(c)

# ── Summary ───────────────────────────────────────────────────────────────────
total_visible = len(roots) + len(pending_roots)
print(f'PR #{pr}  authenticated as: {me}')
print(f'Submitted inline threads : {len(roots)}')
if pending_roots:
    print(f'Your pending threads     : {len(pending_roots)}  (not yet submitted)')
if pending_others_count:
    print(f'Other pending reviews    : {pending_others_count}  (NOT VISIBLE via API — '
          f'reviewer must submit or authenticate as themselves)')
print(f'PR-level comments        : {len(issue_comments)}')
print(f'Review bodies            : {len(reviews_with_body)}')
print(f'Total visible threads    : {total_visible}')
print()

def print_thread(i, total, t, label='Thread'):
    r = t['root']
    line = r.get('line') or r.get('original_line', '?')
    print(SEP)
    print(f'{label} {i}/{total}  {r["path"]}:{line}  [{r["created_at"][:10]}]')
    print(f'Author: {r["user"]["login"]}')
    print()
    print(fmt_body(r['body']))
    for rep in t['replies']:
        print()
        print(f'  >> {rep["user"]["login"]}  [{rep["created_at"][:10]}]')
        print(fmt_body(rep['body'], indent='  '))
    print()

for i, (tid, t) in enumerate(roots.items(), 1):
    print_thread(i, len(roots), t)

if pending_roots:
    print(DSEP)
    print(f'YOUR PENDING REVIEW (not yet submitted)')
    print(DSEP)
    print()
    for rv in pending_me:
        if rv.get('body', '').strip():
            print(f'Review body:')
            print(fmt_body(rv['body']))
            print()
    for i, (tid, t) in enumerate(pending_roots.items(), 1):
        print_thread(i, len(pending_roots), t, label='Pending thread')

if reviews_with_body:
    print(DSEP)
    print('Submitted review bodies')
    print(DSEP)
    print()
    for rv in reviews_with_body:
        print(f'{rv["user"]["login"]}  [{rv.get("submitted_at","?")[:10]}]  state={rv["state"]}')
        print(fmt_body(rv['body']))
        print()

if issue_comments:
    print(DSEP)
    print('PR-level comments')
    print(DSEP)
    print()
    for c in issue_comments:
        print(f'{c["user"]["login"]}  [{c["created_at"][:10]}]')
        print(fmt_body(c['body']))
        print()

if pending_others_count:
    print(SEP)
    print(f'NOTE: {pending_others_count} pending review(s) by other user(s) are not accessible '
          f'via the API until submitted.')
    print('To read them: ask the reviewer to submit, or switch gh auth:')
    print('  gh auth switch --user <reviewer-login>')
    print()

PYEOF
