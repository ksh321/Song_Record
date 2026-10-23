"""Build one local signed beta APK. No installation, publication or secret output."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import uuid
from urllib.parse import urlsplit
import beta_signing

ROOT=Path(__file__).resolve().parents[1]
MOBILE=ROOT/'apps/mobile'
OUTPUT=ROOT/'.local/workflow/release/artifacts'


class BuildError(Exception):pass


def validate_defines(row):
    expected={'APP_ENV','API_BASE_URL','GOOGLE_SERVER_CLIENT_ID','KAKAO_NATIVE_APP_KEY'}
    if not isinstance(row,dict) or set(row)!=expected or any(not isinstance(v,str) for v in row.values()) or row['APP_ENV']!='staging':
        raise BuildError('EXPLICIT_STAGING_PUBLIC_CONFIGURATION_REQUIRED')
    uri=urlsplit(row['API_BASE_URL'])
    if uri.scheme!='https' or not uri.hostname or uri.hostname in {'localhost','127.0.0.1','::1'} or uri.hostname.endswith('.invalid') or uri.username or uri.password or uri.query or uri.fragment or uri.path not in {'','/'}:
        raise BuildError('EXPLICIT_STAGING_HTTPS_REQUIRED')
    if not re.fullmatch(r'660802266773-[a-z0-9]+\.apps\.googleusercontent\.com',row['GOOGLE_SERVER_CLIENT_ID']) or not re.fullmatch('[a-fA-F0-9]{32}',row['KAKAO_NATIVE_APP_KEY']):
        raise BuildError('PUBLIC_PROVIDER_CONFIGURATION_REQUIRED')


def verify_metadata(signers,badging,expected_sha256):
    certificates=re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})\s*$',signers,re.M)
    package=re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",badging,re.M)
    minimum=re.search(r"^sdkVersion:'(\d+)'",badging,re.M);target=re.search(r"^targetSdkVersion:'(\d+)'",badging,re.M)
    if len(certificates)!=1 or certificates[0].lower()!=expected_sha256 or not package or package[1]!=beta_signing.PACKAGE or not minimum or not target or int(minimum[1])!=24 or int(target[1])<36:
        raise BuildError('BETA_ARTIFACT_IDENTITY_REJECTED')
    return {'application_id':package[1],'version_code':package[2],'version_name':package[3],'min_sdk':int(minimum[1]),'target_sdk':int(target[1]),'certificate_sha256':certificates[0].lower()}


def _command(args,*,cwd=None,env=None,timeout=120):
    result=subprocess.run(args,cwd=cwd,env=env,capture_output=True,timeout=timeout)
    if result.returncode:raise BuildError('LOCAL_ARTIFACT_CHECK_FAILED')
    if len(result.stdout)>1024*1024:raise BuildError('LOCAL_ARTIFACT_REPORT_LIMIT')
    return result.stdout.decode('utf-8',errors='replace')


def _source_hashes():
    sources={}
    for folder in ['lib','android/app/src','assets']:
        for path in sorted((MOBILE/folder).rglob('*')):
            if path.is_file():sources[str(path.relative_to(ROOT)).replace('\\','/')]=hashlib.sha256(path.read_bytes()).hexdigest()
    for relative in ['pubspec.yaml','pubspec.lock','android/app/build.gradle.kts','android/gradle/wrapper/gradle-wrapper.properties']:
        path=MOBILE/relative;sources[str(path.relative_to(ROOT)).replace('\\','/')]=hashlib.sha256(path.read_bytes()).hexdigest()
    return sources


def build(defines,flutter,sdk):
    defines=defines.resolve();raw=defines.read_bytes()
    if len(raw)>8192:raise BuildError('PUBLIC_CONFIGURATION_LIMIT')
    validate_defines(json.loads(raw.decode('utf-8-sig')))
    # Confirm tools exist before creating any temporary secret material.
    tools=sdk/'build-tools/36.1.0';apksigner=tools/'apksigner.bat';aapt=tools/'aapt.exe'
    if not flutter.is_file() or not apksigner.is_file() or not aapt.is_file():raise BuildError('EXISTING_ANDROID_BUILD_TOOLS_REQUIRED')
    OUTPUT.mkdir(parents=True,exist_ok=True)
    stamp=dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8]
    log=OUTPUT/('build-'+stamp+'.log')
    sources=_source_hashes()
    with beta_signing.build_files() as (properties,public):
        environment=os.environ.copy();environment['SONGRECORD_SIGNING_PROPERTIES']=str(properties)
        args=[str(flutter),'build','apk','--flavor','beta','--release','--dart-define-from-file='+str(defines)]
        with log.open('xb') as stream:
            result=subprocess.run(args,cwd=MOBILE,env=environment,stdout=stream,stderr=subprocess.STDOUT,timeout=1800)
        if result.returncode:raise BuildError('BETA_BUILD_FAILED_PRIVATE_LOG_SAVED')
    apk=MOBILE/'build/app/outputs/flutter-apk/app-beta-release.apk'
    if not apk.is_file():raise BuildError('BETA_ARTIFACT_NOT_FOUND')
    signatures=_command([str(apksigner),'verify','--verbose','--print-certs',str(apk)])
    badging=_command([str(aapt),'dump','badging',str(apk)])
    metadata=verify_metadata(signatures,badging,public['certificate_sha256'])
    if _source_hashes()!=sources or defines.read_bytes()!=raw:raise BuildError('SOURCES_CHANGED_DURING_BUILD')
    with apk.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    target=OUTPUT/(digest+'.apk')
    if target.exists():
        with target.open('rb') as stream:
            if hashlib.file_digest(stream,'sha256').hexdigest()!=digest:raise BuildError('EXISTING_ARTIFACT_PRESERVED')
    else:
        with apk.open('rb') as source,target.open('xb') as destination:
            while chunk:=source.read(1024*1024):destination.write(chunk)
    baseline=_command(['git','-c','safe.directory='+str(ROOT),'rev-parse','HEAD'],cwd=ROOT).strip()
    manifest={'status':'SIGNED_BETA_ARTIFACT_VERIFIED','created_utc':dt.datetime.now(dt.timezone.utc).isoformat(),**metadata,
              'apk_sha256':digest,'apk_bytes':apk.stat().st_size,'public_defines_sha256':hashlib.sha256(raw).hexdigest(),
              'git_baseline':baseline,'source_tree_sha256':hashlib.sha256(json.dumps(sources,sort_keys=True).encode()).hexdigest(),
              'source_file_hashes':sources,'signing_temporary_files_removed':True,'installed':False,'published':False}
    manifest_path=OUTPUT/(digest+'-'+stamp+'.json')
    with manifest_path.open('x',encoding='utf-8') as file:json.dump(manifest,file,ensure_ascii=False,indent=2)
    return {'status':manifest['status'],'application_id':metadata['application_id'],'apk_sha256':digest,'manifest':str(manifest_path),'installed':False,'published':False}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--defines',type=Path,required=True)
    parser.add_argument('--flutter',type=Path,default=Path('C:/flutter/bin/flutter.bat'))
    parser.add_argument('--sdk',type=Path,default=Path.home()/'AppData/Local/Android/Sdk')
    args=parser.parse_args()
    try:print(json.dumps(build(args.defines,args.flutter,args.sdk)));return 0
    except Exception:print('BETA_BUILD_UNCONFIRMED: values suppressed; existing apps and signing keys preserved');return 2


if __name__=='__main__':raise SystemExit(main())
