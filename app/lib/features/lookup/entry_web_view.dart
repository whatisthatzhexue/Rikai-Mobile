import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/theme/app_tokens.dart';

/// Offline MDict entry renderer.
///
/// JavaScript and network loads are disabled; only local file resources are
/// allowed. `entry://` links are handed back to the app for lookup, external
/// URLs are blocked.
class EntryWebView extends StatefulWidget {
  const EntryWebView({
    super.key,
    required this.html,
    required this.baseUrl,
    required this.onEntryLink,
    required this.onExternalLink,
  });

  final String html;
  final String baseUrl;
  final ValueChanged<String> onEntryLink;
  final ValueChanged<String> onExternalLink;

  @override
  State<EntryWebView> createState() => _EntryWebViewState();
}

class _EntryWebViewState extends State<EntryWebView> {
  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: false,
            blockNetworkLoads: true,
            allowFileAccess: true,
            // Local MDD audio is loaded from file:// subresources. JavaScript
            // stays disabled, so allowing file access from file URLs cannot
            // turn into scripted file exfiltration.
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: false,
            useShouldOverrideUrlLoading: true,
            supportZoom: true,
            mediaPlaybackRequiresUserGesture: true,
            disableContextMenu: true,
          ),
          initialData: InAppWebViewInitialData(
            data: widget.html,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri(widget.baseUrl),
          ),
          onLoadStop: (controller, url) {
            if (mounted) setState(() => _loading = false);
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url;
            if (url == null) return NavigationActionPolicy.ALLOW;
            final raw = url.toString();

            if (raw.toLowerCase().startsWith('entry://')) {
              final word = _entryWord(raw);
              if (word.isNotEmpty) widget.onEntryLink(word);
              return NavigationActionPolicy.CANCEL;
            }

            final scheme = url.scheme.toLowerCase();
            if (scheme == 'file' || scheme == 'about' || scheme == 'data') {
              return NavigationActionPolicy.ALLOW;
            }

            widget.onExternalLink(raw);
            return NavigationActionPolicy.CANCEL;
          },
        ),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_loading)
          Positioned(
            top: AppSpacing.md,
            right: AppSpacing.md,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _entryWord(String raw) {
    var value = raw.substring('entry://'.length);
    final hash = value.indexOf('#');
    if (hash >= 0) value = value.substring(0, hash);
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {
      // Keep the raw value when the dictionary emitted malformed escapes.
    }
    return value.trim();
  }
}
