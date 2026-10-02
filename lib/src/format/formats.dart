import 'dart_format.dart';
import 'env_format.dart';
import 'json_format.dart';
import 'kotlin_format.dart';
import 'output_format.dart';
import 'properties_format.dart';
import 'xcconfig_format.dart';

/// Every format an output can name, by id.
final Map<String, OutputFormat<Object?>> formats = <String, OutputFormat<Object?>>{
  for (final format in const <OutputFormat<Object?>>[
    PropertiesFormat(),
    XcconfigFormat(),
    EnvFormat(),
    JsonFormat(),
    DartFormat(),
    KotlinFormat(),
  ])
    format.id: format,
};

/// Format of an output that names none.
const defaultFormatId = 'properties';
