#!/usr/bin/env python3
"""TuridaTunnel Xray quota and source-IP lease enforcement.

Quota counters are persisted locally across Xray restarts. IP leases are derived
from successful Xray access-log entries and expire after 180 seconds; this is a
conservative rolling source-IP guard, not a kernel-level live socket counter.
"""
import datetime, json, os, re, subprocess, tempfile, time
from pathlib import Path

ROOT=Path('/etc/turidatunnel')
DB=ROOT/'users.tsv'
STATE=ROOT/'limits-state.json'
CONFIG=Path('/etc/xray/config.json')
LOG=Path('/var/log/xray/access.log')
XRAY='/usr/local/bin/xray'
LOCK=Path('/run/lock/turidatunnel-limits.lock')
GIB=1024**3
TTL=180


def run(cmd, **kw):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)


def stats_for(username):
    p=run([XRAY,'api','statsquery','--server=127.0.0.1:10085','-pattern',f'user>>>{username}>>>traffic>>>'])
    if p.returncode:
        return None
    try:
        obj=json.loads(p.stdout)
    except Exception:
        return None
    total=0
    for item in obj.get('stat',[]):
        try: total += int(item.get('value',0))
        except (TypeError,ValueError): pass
    return total


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix=path.name+'.', dir=path.parent)
    with os.fdopen(fd,'w') as f: json.dump(data,f)
    os.chmod(tmp,0o600); os.replace(tmp,path)


def disable_xray_user(username):
    # Remove the identity from every matching protocol inbound, keep DB for audit.
    p=run(['jq','--arg u',username,
           '(.inbounds[] | select(.settings.clients != null) | .settings.clients) |= (map(select(.email != $u)))',
           str(CONFIG)])
    if p.returncode: return False
    fd,tmp=tempfile.mkstemp(prefix='config.json.',dir=str(CONFIG.parent))
    with os.fdopen(fd,'w') as f: f.write(p.stdout)
    os.chmod(tmp,0o640); os.chown(tmp,0,33); os.replace(tmp,CONFIG)
    return run(['systemctl','restart','xray']).returncode==0


def main():
    ROOT.mkdir(mode=0o750,parents=True,exist_ok=True)
    LOCK.parent.mkdir(parents=True,exist_ok=True)
    with open(LOCK,'w') as lock:
        import fcntl; fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        users=[]
        if DB.exists():
            for line in DB.read_text().splitlines():
                cols=line.split('\t')
                if len(cols)>=4:
                    proto,user,credential,expiry=cols[:4]
                    quota=float(cols[4]) if len(cols)>4 and cols[4] else 0
                    maxip=int(cols[5]) if len(cols)>5 and cols[5].isdigit() else 1
                    users.append((user,expiry,quota,maxip))
        state=json.loads(STATE.read_text()) if STATE.exists() else {'prev':{},'total':{},'leases':{},'disabled':{},'log_offset':0}
        now=int(time.time()); changed=False
        # Xray API usage accounting. Store deltas so Xray restarts do not reset quota.
        for user,expiry,quota,maxip in users:
            if quota<=0 or user in state['disabled']: continue
            current=stats_for(user)
            if current is None: continue
            prev=int(state['prev'].get(user,0)); total=int(state['total'].get(user,0))
            total += current-prev if current>=prev else current
            state['prev'][user]=current; state['total'][user]=total
            if total >= quota*GIB:
                if disable_xray_user(user):
                    state['disabled'][user]={'reason':'quota','at':now,'bytes':total}; changed=True
        # Access log entries record authenticated account + source address.
        if LOG.exists():
            try:
                with LOG.open('r',errors='replace') as fh:
                    size=LOG.stat().st_size
                    offset=int(state.get('log_offset',0))
                    if size < offset: offset=0  # log was rotated/truncated
                    fh.seek(offset)
                    new_lines=fh.readlines()
                    state['log_offset']=fh.tell()
            except OSError: new_lines=[]
            for line in new_lines:
                m=re.search(r'from\s+\[?([0-9a-fA-F:.]+)\]?:\d+.*?email:\s*([A-Za-z0-9_.-]{1,32})',line)
                if m:
                    ip,user=m.group(1),m.group(2)
                    state['leases'].setdefault(user,{})[ip]=now
        # Keep only recent IP leases; on excess, revoke the account's Xray access.
        by_user={u:(q,mi) for u,exp,q,mi in users}
        for user, leases in list(state['leases'].items()):
            fresh={ip:ts for ip,ts in leases.items() if now-int(ts)<=TTL}
            state['leases'][user]=fresh
            q,limit=by_user.get(user,(0,1))
            if len(fresh)>limit and user not in state['disabled']:
                if disable_xray_user(user):
                    state['disabled'][user]={'reason':'ip_limit','at':now,'ips':sorted(fresh)}; changed=True
        atomic_json(STATE,state)

if __name__=='__main__':
    try: main()
    except BlockingIOError: pass
