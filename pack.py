#!/usr/bin/env python3
# file: release.py
# Create a zip of the factorio mod, excluding hidden files [only in the top level currently] and python scripts.

import json
import os
import zipfile


ignored_file_endings = [".py", ".svg"]
ignored_files = ["todo.md"]

mod_dir = os.path.dirname(os.path.abspath(__file__))
os.chdir(mod_dir)

with open('info.json') as f:
    mod_info = json.load(f)

mod_name = mod_info["name"]
version = mod_info["version"]

mod_file_name = mod_name + '_' + version

with zipfile.ZipFile(os.path.join('..', mod_file_name + '.zip'), 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk('.'):
        if root[2:].startswith("."):   # strip './'
            continue
        for file in files:
            path = os.path.join(mod_file_name, root[2:], file)
            ends_with_any = lambda suffixes: any(file.endswith(ending) for ending in suffixes)
            if file.startswith('.') or ends_with_any(ignored_file_endings) or ends_with_any(ignored_files):
                continue
            zipf.write(os.path.join(root, file), path)
