import '../../core/models/token.dart';

class ReaderLine {
  const ReaderLine({required this.tokens});

  final List<Token> tokens;
}

/// Groups tokens into the source text's lines so the reader can preserve
/// paragraph breaks.
List<ReaderLine> buildReaderLines(String text, List<Token> tokens) {
  final lines = <ReaderLine>[];
  var offset = 0;
  var tokenIndex = 0;
  for (final rawLine in text.split('\n')) {
    final lineEnd = offset + rawLine.length;
    final lineTokens = <Token>[];
    while (tokenIndex < tokens.length && tokens[tokenIndex].start < lineEnd) {
      final token = tokens[tokenIndex];
      if (token.start >= offset) lineTokens.add(token);
      tokenIndex++;
    }
    lines.add(ReaderLine(tokens: lineTokens));
    offset = lineEnd + 1;
  }
  return lines;
}
