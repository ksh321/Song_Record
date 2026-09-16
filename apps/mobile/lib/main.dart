import 'package:flutter/widgets.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SongRecordApp(config: AppConfig.fromEnvironment()));
}
