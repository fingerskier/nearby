import 'dart:convert';
import 'dart:io';

/// Named JSON documents.
abstract interface class Store {
  /// The decoded document, or null if it is missing or unreadable.
  Future<Object?> read(String name);

  Future<void> write(String name, Object? json);
}

class JsonFileStore implements Store {
  JsonFileStore(this.directory);

  final Directory directory;

  @override
  Future<Object?> read(String name) async {
    try {
      return jsonDecode(await File('${directory.path}/$name').readAsString());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Writes a temporary file and renames it over the old one, so a crash never leaves half a file.
  @override
  Future<void> write(String name, Object? json) async {
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/$name.tmp');
    await temporary.writeAsString(const JsonEncoder.withIndent('  ').convert(json), flush: true);
    await temporary.rename('${directory.path}/$name');
  }
}

class MemoryStore implements Store {
  MemoryStore([Map<String, Object?>? documents]) : documents = documents ?? {};

  final Map<String, Object?> documents;

  @override
  Future<Object?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, Object? json) async => documents[name] = jsonDecode(jsonEncode(json));
}
