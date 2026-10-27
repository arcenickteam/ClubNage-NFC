import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'xlsx_data_reader.dart';

/// Modifie seulement les éléments OOXML nécessaires à l'onglet Pointages NFC.
/// Les autres feuilles, formules, styles et relations sont recopiés tels quels.
class XlsxPointageWriter {
  static const sheetName = 'Pointages NFC';
  static const headers = <String>[
    'ID_Pointage', 'Date', 'Heure', 'Licencie_ID', 'Nom', 'Prénom',
    'Activité', 'Groupe', 'Séance', 'Type_badge', 'Appareil_ID',
    'Date_synchronisation',
  ];
  static const _mainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static String _esc(String value) => const HtmlEscape(HtmlEscapeMode.element).convert(value)
      .replaceAll('"', '&quot;');

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) { n--; s = String.fromCharCode(65 + n % 26) + s; n ~/= 26; }
    return s;
  }

  static Uint8List merge(Uint8List bytes, List<List<String>> additions) {
    final source = ZipDecoder().decodeBytes(bytes, verify: true);
    final parts = <String, List<int>>{};
    for (final file in source.files) {
      if (!file.isFile) continue;
      parts[file.name] = List<int>.from(file.content as List<int>);
    }
    String read(String path) {
      final b = parts[path];
      if (b == null) throw FormatException('Composant XLSX absent : $path');
      return utf8.decode(b);
    }
    final workbook = XmlDocument.parse(read('xl/workbook.xml'));
    final rels = XmlDocument.parse(read('xl/_rels/workbook.xml.rels'));
    final contentTypes = XmlDocument.parse(read('[Content_Types].xml'));
    final existing = workbook.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'sheet' && e.getAttribute('name') == sheetName,
    ).toList();
    final existingRows = existing.isEmpty ? <List<String>>[] : XlsxDataReader.readSheet(bytes, sheetName);
    if (existingRows.isNotEmpty && !_sameHeader(existingRows.first)) {
      throw StateError('Onglet Pointages NFC existant avec colonnes incompatibles. Aucun fichier modifié.');
    }
    final ids = <String>{};
    for (final row in existingRows.skip(1)) {
      if (row.isNotEmpty && row.first.trim().isNotEmpty) ids.add(row.first.trim());
    }
    final newRows = <List<String>>[];
    for (final row in additions) {
      if (row.length != headers.length || row.first.trim().isEmpty) {
        throw ArgumentError('Pointage invalide : 12 colonnes et ID requis.');
      }
      if (ids.add(row.first.trim())) newRows.add(row);
    }
    if (newRows.isEmpty) return bytes;
    final rows = <List<String>>[
      if (existingRows.isEmpty) headers,
      ...existingRows,
      ...newRows,
    ];
    // Si l'onglet existait déjà, les anciennes lignes sont reconstruites
    // exclusivement avec leurs valeurs (la feuille Pointages NFC nous appartient).
    final xmlRows = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      xmlRows.write('<row r="${r + 1}">');
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        if (row[c].isEmpty) continue;
        xmlRows.write('<c r="${_col(c)}${r + 1}" t="inlineStr"><is><t xml:space="preserve">${_esc(row[c])}</t></is></c>');
      }
      xmlRows.write('</row>');
    }
    final sheetXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="$_mainNs"><sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews><sheetData>$xmlRows</sheetData></worksheet>';
    String sheetPath;
    if (existing.isEmpty) {
      final sheets = workbook.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'sheets');
      final maxSheetId = workbook.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sheet')
          .map((e) => int.tryParse(e.getAttribute('sheetId') ?? '') ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
      final relIds = rels.descendants.whereType<XmlElement>()
          .map((e) => e.getAttribute('Id') ?? '').toSet();
      var nextRel = 1;
      while (relIds.contains('rId$nextRel')) { nextRel++; }
      var index = 1;
      while (parts.containsKey('xl/worksheets/sheet$index.xml')) { index++; }
      sheetPath = 'xl/worksheets/sheet$index.xml';
      sheets.children.add(XmlElement(XmlName('sheet'), [
        XmlAttribute(XmlName('name'), sheetName),
        XmlAttribute(XmlName('sheetId'), '${maxSheetId + 1}'),
        XmlAttribute(XmlName('id', 'r'), 'rId$nextRel'),
      ]));
      rels.rootElement.children.add(XmlElement(XmlName('Relationship'), [
        XmlAttribute(XmlName('Id'), 'rId$nextRel'),
        XmlAttribute(XmlName('Type'), '$_relNs/worksheet'),
        XmlAttribute(XmlName('Target'), 'worksheets/sheet$index.xml'),
      ]));
      contentTypes.rootElement.children.add(XmlElement(XmlName('Override'), [
        XmlAttribute(XmlName('PartName'), '/$sheetPath'),
        XmlAttribute(XmlName('ContentType'), 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'),
      ]));
      // Garantit le préfixe r utilisé dans le nouvel élément sheet.
      var workText = workbook.toXmlString();
      if (!workText.contains('xmlns:r=')) {
        workText = workText.replaceFirst('<workbook ', '<workbook xmlns:r="$_relNs" ');
      }
      parts['xl/workbook.xml'] = utf8.encode(workText);
      parts['xl/_rels/workbook.xml.rels'] = utf8.encode(rels.toXmlString());
      parts['[Content_Types].xml'] = utf8.encode(contentTypes.toXmlString());
    } else {
      final relationId = existing.first.attributes.firstWhere((a) => a.name.local == 'id').value;
      final rel = rels.descendants.whereType<XmlElement>().firstWhere((e) => e.getAttribute('Id') == relationId);
      final target = rel.getAttribute('Target')!;
      sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      if (sheetPath.contains('..')) throw const FormatException('Chemin feuille non pris en charge.');
    }
    parts[sheetPath] = utf8.encode(sheetXml);
    final result = Archive();
    for (final entry in parts.entries) {
      result.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(result)!);
  }

  static bool _sameHeader(List<String> row) => row.length >= headers.length &&
      List.generate(headers.length, (i) => row[i].trim() == headers[i]).every((x) => x);
}
