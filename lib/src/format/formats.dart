import 'output_format.dart';
import 'properties_format.dart';

/// Every format an output can name, by id.
final Map<String, OutputFormat<Object?>> formats = <String, OutputFormat<Object?>>{
  for (final format in const <OutputFormat<Object?>>[PropertiesFormat()]) format.id: format,
};

/// Format of an output that names none.
const defaultFormatId = 'properties';
