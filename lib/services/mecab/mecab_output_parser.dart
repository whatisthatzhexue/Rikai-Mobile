/// Parsing of `mecab_sparse_tostr` output.
///
/// UniDic feature rows are comma separated, but some fields contain commas
/// inside double quotes, for example:
///
/// ```text
/// た	助動詞,*,*,*,助動詞-タ,連体形-一般,タ,た,た,タ,た,タ,和,*,*,*,*,*,*,助動,タ,タ,タ,タ,*,"動詞%F2@1,形容詞%F4@-2",*,5948916285711041,21642
/// ```
///
/// Splitting on every comma yields 30+ fields and breaks the 29-field layout.
/// [splitMecabFeatures] keeps quoted fields intact (and unquotes them) so the
/// documented UniDic indices stay valid.
library;

class MecabParsedNode {
  const MecabParsedNode({required this.surface, required this.features});

  final String surface;
  final List<String> features;
}

/// Splits a MeCab feature row, honouring double-quoted fields.
///
/// Double quotes inside a quoted field are escaped as `""`.
List<String> splitMecabFeatures(String input) {
  if (input.isEmpty) return const <String>[];

  final fields = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    if (inQuotes) {
      if (char == '"') {
        if (index + 1 < input.length && input[index + 1] == '"') {
          buffer.write('"');
          index++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
    } else if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  fields.add(buffer.toString());
  return fields;
}

/// Parses the raw output for one analysed line into nodes.
///
/// Each token line is `surface<TAB>feature1,feature2,...`; `EOS`, empty lines
/// and lines without a tab are ignored.
List<MecabParsedNode> parseMecabOutput(String output) {
  final nodes = <MecabParsedNode>[];
  for (final line in output.split('\n')) {
    if (line.isEmpty || line == 'EOS') continue;
    final tabIndex = line.indexOf('\t');
    if (tabIndex <= 0) continue;
    final surface = line.substring(0, tabIndex);
    if (surface.isEmpty) continue;
    nodes.add(
      MecabParsedNode(
        surface: surface,
        features: splitMecabFeatures(line.substring(tabIndex + 1)),
      ),
    );
  }
  return nodes;
}
