import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker_writable/file_picker_writable.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_json_persistence/simple_json_persistence.dart';
import 'package:convert/convert.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('main');

Future<void> main() async {
  Logger.root.level = Level.ALL;
  PrintAppender().attachToLogger(Logger.root);

  runApp(MyApp());
}

class AppDataBloc {
  final store = SimpleJsonPersistence.getForTypeSync(
    (json) => AppData.fromJson(json),
    defaultCreator: () => AppData(files: []),
  );
}

class AppData implements HasToJson {
  AppData({@required this.files}) : assert(files != null);
  final List<FileInfo> files;

  static AppData fromJson(Map<String, dynamic> json) => AppData(
      files: (json['files'] as List<dynamic>)
          .where((dynamic element) => element != null)
          .map((dynamic e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList());

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'files': files,
      };

  AppData copyWith({List<FileInfo> files}) => AppData(files: files);
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppDataBloc _appDataBloc = AppDataBloc();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('File Picker Example'),
        ),
        body: Container(
          width: double.infinity,
          child: StreamBuilder<AppData>(
            stream: _appDataBloc.store.onValueChangedAndLoad,
            builder: (context, snapshot) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    RaisedButton(
                      child: const Text('Open File Picker'),
                      onPressed: _openFilePicker,
                    ),
                    const SizedBox(width: 32),
                    RaisedButton(
                      child: const Text('Create New File'),
                      onPressed: _openFilePickerForCreate,
                    ),
                  ],
                ),
                ...?(!snapshot.hasData
                    ? null
                    : snapshot.data.files
                        .where((element) => element != null)
                        .map((fileInfo) => FileInfoDisplay(
                              fileInfo: fileInfo,
                              appDataBloc: _appDataBloc,
                            ))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFilePicker() async {
    final fileInfo = await FilePickerWritable().openFilePicker();
    _logger.fine('Got picker result: $fileInfo');
    if (fileInfo == null) {
      _logger.info('User canceled.');
      return;
    }
    final data = await _appDataBloc.store.load();
    await _appDataBloc.store
        .save(data.copyWith(files: data.files + [fileInfo]));
  }

  Future<void> _openFilePickerForCreate() async {
    final tempDirectory = await getTemporaryDirectory();
    final rand = Random().nextInt(10000000);
    final temp = File(p.join(tempDirectory.path, 'newfile.$rand.txt'));
    final content = 'File created at ${DateTime.now()}\n\n';
    await temp.writeAsString(content);
    final fileInfo = await FilePickerWritable().openFilePickerForCreate(temp);
    if (fileInfo == null) {
      _logger.info('User canceled.');
      return;
    }
    final data = await _appDataBloc.store.load();
    await _appDataBloc.store
        .save(data.copyWith(files: data.files + [fileInfo]));
  }
}

class FileInfoDisplay extends StatelessWidget {
  const FileInfoDisplay({
    Key key,
    @required this.fileInfo,
    @required this.appDataBloc,
  })  : assert(fileInfo != null),
        assert(appDataBloc != null),
        super(key: key);

  final AppDataBloc appDataBloc;
  final FileInfo fileInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              const Text('Selected File:'),
              Text(
                fileInfo.file.path,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.caption.apply(fontSizeFactor: 0.75),
              ),
              Text(
                fileInfo.identifier,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'uri:${fileInfo.uri}',
                style: theme.textTheme.bodyText2
                    .apply(fontSizeFactor: 0.7)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              ButtonBar(
                alignment: MainAxisAlignment.end,
                children: <Widget>[
                  FlatButton(
                    onPressed: () async {
                      final fi = fileInfo.file.existsSync()
                          ? fileInfo
                          : await FilePickerWritable()
                              .readFileWithIdentifier(fileInfo.identifier);
                      final dataList = await fi.file.openRead(0, 64).toList();
                      final data =
                          dataList.expand((element) => element).toList();
                      final hexString = hex.encode(data);
                      final utf8String =
                          utf8.decode(data, allowMalformed: true);
                      SimpleAlertDialog(
                        titleText: 'Read first ${data.length} bytes of file',
                        bodyText: 'hexString: $hexString\n\nutf8: $utf8String',
                      ).show(context);
                    },
                    child: const Text('Read'),
                  ),
                  FlatButton(
                    onPressed: () async {
                      final fi = fileInfo.file.existsSync()
                          ? fileInfo
                          : await FilePickerWritable()
                              .readFileWithIdentifier(fileInfo.identifier);
                      final content =
                          'New Content written at ${DateTime.now()}.\n\n';
                      await fi.file.writeAsString(content);
                      await FilePickerWritable()
                          .writeFileWithIdentifier(fi.identifier, fi.file);
                      SimpleAlertDialog(
                        bodyText: 'Wriitten: $content',
                      ).show(context);
                    },
                    child: const Text('Overwrite'),
                  ),
                  IconButton(
                    onPressed: () async {
                      final appData = await appDataBloc.store.load();
                      await appDataBloc.store.save(appData.copyWith(
                          files: appData.files
                              .where((element) => element != fileInfo)
                              .toList()));
                    },
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class SimpleAlertDialog extends StatelessWidget {
  const SimpleAlertDialog({Key key, this.titleText, this.bodyText})
      : super(key: key);
  final String titleText;
  final String bodyText;

  Future<void> show(BuildContext context) =>
      showDialog<void>(context: context, builder: (context) => this);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: titleText == null ? null : Text(titleText),
      content: Text(bodyText),
      actions: <Widget>[
        FlatButton(
            child: const Text('Ok'),
            onPressed: () {
              Navigator.of(context).pop();
            }),
      ],
    );
  }
}
