"""Optional, pinned GigaAM download. No pip, administrator rights or system changes."""
import argparse, hashlib, json, os, shutil, subprocess, sys, time, urllib.request, zipfile
from pathlib import Path

def install(root, manifest_path, cache=None):
    root=Path(root); root.mkdir(parents=True,exist_ok=True)
    # A second GUI instance must never extract into a running installation.
    lock=(root/'installation.lock').open('a+b');lock.seek(0);lock.write(b'0');lock.flush();lock.seek(0)
    if os.name=='nt':
        import msvcrt
        try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:return
    manifest=json.loads(Path(manifest_path).read_text(encoding='utf-8'))
    def progress(phase,done=0,error=''):
        data=dict(phase=phase,downloaded=done,total=manifest['total_bytes'],error=error)
        temp=root/'progress.tmp';temp.write_text(json.dumps(data),encoding='utf-8');os.replace(temp,root/'progress.json')
    done=0
    try:
        progress('downloading')
        for entry in manifest['files']:
            folder=root/('wheels' if entry['kind']=='wheel' else 'model');folder.mkdir(exist_ok=True)
            target=folder/entry['name']
            def valid(p):
                if not p.is_file() or p.stat().st_size!=entry['size']:return False
                with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()==entry['sha256']
            if not valid(target):
                temp=target.with_suffix(target.suffix+'.part')
                cached=Path(cache)/entry['name'] if cache else None
                if cached and valid(cached):shutil.copyfile(cached,temp)
                else:
                    request=urllib.request.Request(entry['url'],headers={'User-Agent':'Jarvis-GigaAM/1.0'})
                    with urllib.request.urlopen(request,timeout=30) as source,temp.open('wb') as dest:
                        count=0;last=0.
                        while chunk:=source.read(512*1024):
                            dest.write(chunk);count+=len(chunk)
                            if count>entry['size']:raise ValueError('Unexpected download size')
                            if time.monotonic()-last>.25:progress('downloading',done+count);last=time.monotonic()
                if not valid(temp):raise ValueError('Downloaded file verification failed: '+entry['name'])
                os.replace(temp,target)
            done+=entry['size'];progress('downloading',done)
        progress('installing',done)
        packages=root/'packages';packages.mkdir(exist_ok=True)
        for entry in manifest['files']:
            if entry['kind']!='wheel':continue
            with zipfile.ZipFile(root/'wheels'/entry['name']) as archive:
                for item in archive.infolist():
                    path=(packages/item.filename).resolve()
                    if not path.is_relative_to(packages.resolve()):raise ValueError('Invalid archive path')
                archive.extractall(packages)
        progress('checking',done)
        subprocess.run([sys.executable,str(Path(__file__).with_name('worker.py')),'--root',str(root),'--probe'],check=True,timeout=60,stdout=subprocess.PIPE)
        marker=root/'installed.tmp';marker.write_text(json.dumps(dict(version=1,revision=manifest['revision'])),encoding='utf-8');os.replace(marker,root/'installed.json')
        progress('ready',done)
    except Exception as error:
        progress('error',done,str(error));raise

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--manifest',required=True);p.add_argument('--cache')
    a=p.parse_args();install(a.root,a.manifest,a.cache)
