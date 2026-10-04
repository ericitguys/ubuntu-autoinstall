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
print('YAML_OK; late_commands =', len(a['late-commands']))

base = '/tmp/aiverify'
shutil.rmtree(base, ignore_errors=True)
os.makedirs(base)
for c in a['late-commands']:
    if c.lstrip().startswith('printf'):
        c2 = c.replace('/target', base)
        out = c2.split('> ', 1)[1].strip()
        os.makedirs(os.path.dirname(out), exist_ok=True)
        subprocess.run(['sh', '-c', c2], check=True)
        print('--- rendered:', out)
        print(open(out).read())

print('ALL_CHECKS_PASSED')