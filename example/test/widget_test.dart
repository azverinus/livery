import 'package:flutter_test/flutter_test.dart';
import 'package:livery_example/main.dart';
import 'package:livery_example/src/app_config.g.dart';

void main() {
  testWidgets('shows the generated values', (tester) async {
    await tester.pumpWidget(const LiveryExampleApp());

    expect(find.text(EnvDefine.current.value), findsOneWidget);
    expect(find.text(AppConfig.apiUrl), findsOneWidget);
  });
}
