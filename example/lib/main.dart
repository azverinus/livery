import 'package:flutter/material.dart';

import 'src/app_config.g.dart';

void main() => runApp(const LiveryExampleApp());

class LiveryExampleApp extends StatelessWidget {
  const LiveryExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppConfig.appName,
    // Decided at compile time: a production build drops the banner code.
    debugShowCheckedModeBanner: EnvDefine.maybeCurrent != EnvDefine.production,
    home: const ConfigPage(),
  );
}

/// Lists the values livery generated, as the running app sees them.
class ConfigPage extends StatelessWidget {
  const ConfigPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppConfig.appName)),
    body: ListView(
      children: [
        ListTile(
          title: const Text('ENV'),
          subtitle: Text(EnvDefine.current.value),
        ),
        ListTile(
          title: const Text('BUILD_TAG'),
          subtitle: Text(
            AppConfig.buildTag.isEmpty ? '(none)' : AppConfig.buildTag,
          ),
        ),
        const ListTile(
          title: Text('API URL'),
          subtitle: Text(AppConfig.apiUrl),
        ),
        ListTile(
          title: const Text('API timeout'),
          subtitle: Text('${AppConfig.apiTimeoutSeconds} s'),
        ),
      ],
    ),
  );
}
