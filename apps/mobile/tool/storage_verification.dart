import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/settings/settings_api.dart';
import 'package:song_record/features/settings/storage_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const first = '11111111-1111-4111-8111-111111111111';
  const second = '22222222-2222-4222-8222-222222222222';
  Map<String,dynamic>? slot = {'slot_no':1,'revision':1,
    'current_recording_id':first,'pending_recording_id':second};
  final receipts = <String,Map<String,dynamic>>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  server.listen((r) async {
    r.response.headers.contentType=ContentType.json;
    if (r.headers.value('Authorization') != 'Bearer synthetic' ||
        r.headers.value('X-Device-Id') != first) { r.response.statusCode=401; }
    else if(r.method == 'GET' && r.uri.path == '/v1/storage') {
      r.response.write(jsonEncode({for(final k in StorageView.labels.keys) k:0,
        'used_bytes':197,'quota_bytes':1000,'pinned_limit':10,
        'pinned_used':slot==null?0:1,'pinned_pending':slot?['pending_recording_id']==null?0:1,
        'entitlement_revision':1}));
    } else if(r.method=='GET' && r.uri.path=='/v1/pins') {
      r.response.write(jsonEncode({'items':[?slot]}));
    } else {
      final op=r.headers.value('Idempotency-Key');
      final body=jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      if(op==null || slot==null || body['base_revision']!=slot!['revision']) {
        r.response.statusCode=409;
      } else if(receipts.containsKey(op)) { r.response.write(jsonEncode(receipts[op])); }
      else if(r.method=='POST' && r.uri.path=='/v1/pins/1/replacement/cancel') {
        slot={...slot!,'revision':(slot!['revision'] as int)+1,'pending_recording_id':null};
        receipts[op]=slot!; r.response.write(jsonEncode(slot));
      } else if(r.method=='DELETE' && r.uri.path=='/v1/pins/1') {
        final answer={'slot_no':1,'revision':(slot!['revision'] as int)+1,'current_recording_id':null,'pending_recording_id':null};
        receipts[op]=answer;slot=null;r.response.write(jsonEncode(answer));
      } else {r.response.statusCode=400;}
    }
    await r.response.close();
  });
  final api=SettingsApi(Uri.parse('http://localhost:${server.port}'),() async => AuthSession(
    userId:first,deviceId:first,accessToken:'synthetic',refreshToken:'synthetic',
    accessExpiresAt:DateTime.now().add(const Duration(hours:1)),
    refreshExpiresAt:DateTime.now().add(const Duration(days:1))),(){},local:true);
  runApp(MaterialApp(theme:AppTheme.dark(),home:Scaffold(
    appBar:AppBar(title:const Text('P23-02 합성 보관·고정 검증')),
    body:Column(children:[const Text('합성 HTTP · 개인 DB/서버 파일 변경 없음'),Expanded(child:
      StorageScreen(requireCurrent:(){},load:() async => StorageView(
        await api.get('/v1/storage') as Map<String,dynamic>,
        ((await api.get('/v1/pins'))['items'] as List).cast<Map<String,dynamic>>(),
        [{'id':first,'title':'기존 합성 녹음'},{'id':second,'title':'교체 합성 녹음'}]),
        command:(m,p,b,id) async {await api.pinCommand(m,p,b,id);}))]))));
}
