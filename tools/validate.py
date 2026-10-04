import yaml, crypt, os, subprocess, shutil

d = yaml.safe_load(open('user-data'))
a = d['autoinstall']
assert a['version'] == 1
assert a['identity']['username'] == 'local_user'
h = a['identity']['password']
assert h.startswith('$6$') and crypt.crypt('159753', h) == h, 'hash roundtrip failed'
assert a['storage']['layout']['name'] == 'direct'
assert a['shutdown'] == 'poweroff'
assert a['locale'] == 'en_US.UTF-8'
lc = a['late-commands']
assert any("favorite-apps=['google-chrome.desktop']" in c for c in lc), 'dock favorites missing'
print('YAML_OK; late_commands =', len(lc))

base = '/tmp/aiverify'
shutil.rmtree(base, ignore_errors=True)
os.makedirs(base)
for c in lc:
    c2 = c.replace('/target', base)
    body = c2.lstrip()
    if body.startswith('printf'):
        out = c2.split('> ', 1)[1].strip()
        os.makedirs(os.path.dirname(out), exist_ok=True)
        subprocess.run(['sh', '-c', c2], check=True)
    elif body.startswith('mkdir') or '\n' in c2.rstrip():
        subprocess.run(['sh', '-c', c2], check=True)

print('--- rendered files ---')
for root, dirs, files in os.walk(base):
    for f in sorted(files):
        p = os.path.join(root, f)
        print('==', p)
        print(open(p).read())
print('ALL_CHECKS_PASSED')