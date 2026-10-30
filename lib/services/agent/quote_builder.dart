import '../../core/models/agent/agent_quote.dart';

/// Splits a source into sentence/clause quotes with UTF-16 spans.
List<AgentQuoteRef> buildSourceQuotes({
  required String sourceId,
  required String text,
  required AgentQuoteOrigin origin,
  int maxQuotes = 40,
}) {
  final quotes = <AgentQuoteRef>[];
  var start = 0;
  var index = 0;
  while (index < text.length && quotes.length < maxQuotes) {
    final char = text[index];
    final isEnd =
        char == '。' ||
        char == '！' ||
        char == '？' ||
        char == '!' ||
        char == '?' ||
        char == '…' ||
        char == '\n';
    index++;
    if (!isEnd && index < text.length) continue;
    _appendQuote(
      quotes: quotes,
      sourceId: sourceId,
      text: text,
      start: start,
      end: index,
      origin: origin,
    );
    start = index;
  }
  if (start < text.length && quotes.length < maxQuotes) {
    _appendQuote(
      quotes: quotes,
      sourceId: sourceId,
      text: text,
      start: start,
      end: text.length,
      origin: origin,
    );
  }
  if (quotes.isEmpty && text.trim().isNotEmpty) {
    _appendQuote(
      quotes: quotes,
      sourceId: sourceId,
      text: text,
      start: 0,
      end: text.length,
      origin: origin,
    );
  }
  return quotes;
}

void _appendQuote({
  required List<AgentQuoteRef> quotes,
  required String sourceId,
  required String text,
  required int start,
  required int end,
  required AgentQuoteOrigin origin,
}) {
  var quoteStart = start;
  var quoteEnd = end;
  while (quoteStart < quoteEnd && text[quoteStart].trim().isEmpty) {
    quoteStart++;
  }
  while (quoteEnd > quoteStart && text[quoteEnd - 1].trim().isEmpty) {
    quoteEnd--;
  }
  if (quoteEnd <= quoteStart) return;
  quotes.add(
    AgentQuoteRef(
      id: 'q${quotes.length + 1}',
      sourceId: sourceId,
      start: quoteStart,
      end: quoteEnd,
      text: text.substring(quoteStart, quoteEnd),
      origin: origin,
    ),
  );
}
