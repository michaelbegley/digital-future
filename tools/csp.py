"""Re-stamp the page security rule (Content-Security-Policy meta tag) on each page.
Inline scripts are allowed by their sha256 hash, so run this after ANY edit to an
inline <script>:  python3 tools/csp.py"""
import base64, hashlib, re, sys, os

API = "https://michbegl-digital-future.hf.space"
COUNTER = "https://cpzhsztczixiidxypvmb.supabase.co"
BEACON_JS = "https://static.cloudflareinsights.com"   # Cloudflare Web Analytics (console Sites board)
BEACON_POST = "https://cloudflareinsights.com"
# Google AdSense (ads script, ad frames, ad images and reporting)
ADS = "https://*.googlesyndication.com https://*.doubleclick.net https://*.google.com https://*.gstatic.com https://*.googletagservices.com https://*.adtrafficquality.google https://*.googleadservices.com"
PAGES = {
    "index.html": f"img-src 'self' data: blob: {API} {ADS}; media-src 'self' blob: {API}; connect-src 'self' {API} {COUNTER} {BEACON_POST} {ADS}; frame-src {ADS}",
    "privacy/index.html": "img-src 'self'",
    "stats/index.html": f"img-src 'self' data:; connect-src {COUNTER} {API}",
    "removal/index.html": "img-src 'self'",
    "archive/index.html": f"img-src 'self' data:; media-src 'self'; connect-src {API}",
}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

for page, extra in PAGES.items():
    path = os.path.join(ROOT, page)
    s = open(path).read()
    s = re.sub(r'\n?<meta http-equiv="Content-Security-Policy"[^>]*>', "", s)
    s = re.sub(r'\n?<meta name="referrer"[^>]*>', "", s)
    hashes = " ".join("'sha256-" + base64.b64encode(hashlib.sha256(m.encode()).digest()).decode() + "'"
                      for m in re.findall(r"<script>(.*?)</script>", s, re.S))
    beacon = f" {BEACON_JS}" if BEACON_JS in s else ""
    if "adsbygoogle.js" in s:
        beacon += " " + ADS
    policy = (f"default-src 'none'; script-src 'self' {hashes}{beacon}; style-src 'self' 'unsafe-inline'; {extra}; "
              "base-uri 'none'; form-action 'none'; object-src 'none'")
    tags = f'<meta http-equiv="Content-Security-Policy" content="{policy}">\n<meta name="referrer" content="strict-origin-when-cross-origin">'
    s = s.replace('<meta charset="utf-8">', '<meta charset="utf-8">\n' + tags, 1)
    open(path, "w").write(s)
    print(page, "ok", hashes.count("sha256"), "inline scripts")
