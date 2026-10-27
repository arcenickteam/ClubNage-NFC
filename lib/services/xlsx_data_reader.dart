import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Lecture des seules valeurs d'un XLSX (OOXML), sans décoder styles.xml.
/// Les classeurs issus d'Excel, de LibreOffice ou d'openpyxl peuvent contenir
/// des styles que certains décodeurs Dart refusent à tort.
/// Aucune écriture dans le classeur, aucun traitement des badges ou présences.
class XlsxDataReader {
  static Iterable<XmlElement> _children(XmlElement parent, String name) =>
      parent.childElements.where((element) => element.name.local == name);

  static XmlElement? _first(XmlElement parent, String name) {
    for (final element in _children(parent, name)) {
      return element;
    }
    return null;
  }

  static String? _attribute(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String _text(XmlElement element) => element.descendants
      .whereType<XmlElement>()
      .where((child) => child.name.local == 't')
      .map((child) => child.innerText)
      .join();

  static int _column(String reference) {
    var column = 0;
    for (final code in reference.codeUnits) {
      if (code >= 65 && code <= 90) {
        column = column * 26 + code - 64;
      } else if (code >= 97 && code <= 122) {
        column = column * 26 + code - 96;
      } else {
        break;
      }
    }
    return column - 1;
  }

  static String _normalizeTarget(String target) {
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final segments = <String>[];
    for (final part in path.split('/')) {
      if (part == '.' || part.isEmpty) continue;
      if (part == '..') {
        if (segments.isEmpty) throw const FormatException('Chemin XLSX invalide.');
        segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    return segments.join('/');
  }

  static List<List<String>> readSheet(Uint8List bytes, String sheetName) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw FormatException('Archive XLSX illisible : $error');
    }

    String readXml(String path) {
      final file = archive.findFile(path);
      if (file == null) throw FormatException('Élément XLSX absent : $path');
      return utf8.decode(file.content as List<int>);
    }

    final workbook = XmlDocument.parse(readXml('xl/workbook.xml'));
    final sheets = workbook.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'sheet' &&
          _attribute(element, 'name') == sheetName,
    );
    if (sheets.isEmpty) {
      throw FormatException('Onglet « $sheetName » absent du classeur.');
    }
    final relationId = _attribute(sheets.first, 'id');
    if (relationId == null) {
      throw FormatException('Référence de l’onglet « $sheetName » absente.');
    }

    final relationships =
        XmlDocument.parse(readXml('xl/_rels/workbook.xml.rels'));
    final matching = relationships.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'Relationship' &&
          _attribute(element, 'Id') == relationId,
    );
    if (matching.isEmpty) {
      throw FormatException('Fichier de l’onglet « $sheetName » introuvable.');
    }
    final target = _attribute(matching.first, 'Target');
    if (target == null) throw const FormatException('Cible XLSX absente.');

    final sharedStrings = <String>[];
    if (archive.findFile('xl/sharedStrings.xml') != null) {
      final strings = XmlDocument.parse(readXml('xl/sharedStrings.xml'));
      for (final item in strings.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'si',
      )) {
        sharedStrings.add(_text(item));
      }
    }

    final worksheet = XmlDocument.parse(readXml(_normalizeTarget(target)));
    final data = worksheet.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'sheetData',
    );
    if (data.isEmpty) return <List<String>>[];

    final rows = <List<String>>[];
    for (final row in _children(data.first, 'row')) {
      final number = int.tryParse(_attribute(row, 'r') ?? '');
      final rowIndex = (number ?? (rows.length + 1)) - 1;
      if (rowIndex < 0 || rowIndex > 100000) {
        throw const FormatException('Numéro de ligne XLSX invalide.');
      }
      while (rows.length <= rowIndex) {
        rows.add(<String>[]);
      }
      final values = rows[rowIndex];
      var nextColumn = 0;
      for (final cell in _children(row, 'c')) {
        final ref = _attribute(cell, 'r');
        final column = ref == null ? nextColumn : _column(ref);
        if (column < 0 || column > 1023) {
          throw const FormatException('Colonne XLSX invalide.');
        }
        nextColumn = column + 1;
        final type = _attribute(cell, 't') ?? '';
        String value;
        if (type == 'inlineStr') {
          final inline = _first(cell, 'is');
          value = inline == null ? '' : _text(inline);
        } else {
          final raw = _first(cell, 'v')?.innerText ?? '';
          if (type == 's' && raw.isNotEmpty) {
            final index = int.tryParse(raw);
            if (index == null || index < 0 || index >= sharedStrings.length) {
              throw const FormatException('Index de texte XLSX invalide.');
            }
            value = sharedStrings[index];
          } else if (type == 'b') {
            value = raw == '1' ? '1' : '0';
          } else {
            value = raw;
          }
        }
        while (values.length <= column) {
          values.add('');
        }
        values[column] = value;
      }
    }
    return rows;
  }
}
