#!/usr/bin/env python3
"""Rename the app everywhere: python3 rename.py "New Name" ["Short"]"""
import sys, re, json
new = sys.argv[1]; short = sys.argv[2] if len(sys.argv) > 2 else new[:12]
c = open("config.js").read()
c = re.sub(r'APP_NAME: ".*?"', 'APP_NAME: ' + json.dumps(new), c); open("config.js", "w").write(c)
m = json.load(open("manifest.webmanifest")); m["name"] = new; m["short_name"] = short
json.dump(m, open("manifest.webmanifest", "w"), indent=2)
h = open("index.html").read()
h = re.sub(r"<title>.*?</title>", "<title>" + new.replace("&", "&amp;") + "</title>", h)
h = re.sub(r'name="apple-mobile-web-app-title" content=".*?"', 'name="apple-mobile-web-app-title" content="' + short.replace("&", "&amp;") + '"', h)
open("index.html", "w").write(h)
print("Renamed to", new, "- bump CACHE in sw.js and redeploy. The iPhone project is separate and was not renamed.")
