#!/usr/bin/env python3
"""Run asc using the existing local Apple API config, without copying credentials."""
import json, os, pathlib, shutil, sys
config = json.loads((pathlib.Path.home()/'.appstoreconnect/config.json').read_text())
env = dict(os.environ, ASC_KEY_ID=config['key_id'], ASC_ISSUER_ID=config['issuer_id'], ASC_PRIVATE_KEY_PATH=os.path.expanduser(config['key_filepath']), ASC_TELEMETRY_DISABLED='1')
os.execve(shutil.which('asc'), ['asc', *sys.argv[1:]], env)
