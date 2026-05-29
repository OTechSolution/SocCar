// ============================================================================
// society_search_field.dart
// ============================================================================
// FIX: Flutter Web CORS bypass using a lightweight proxy approach.
//
// ROOT CAUSE:
//   curl on your machine → StatusCode 200 ✅  (works perfectly)
//   Flutter Web browser  → "Could not reach Google Places API" ❌
//
//   The browser enforces CORS (Cross-Origin Resource Sharing).
//   Google's Places Autocomplete API does NOT send the required
//   "Access-Control-Allow-Origin: *" header for REST key-based calls.
//   The browser sees the missing header and throws a CORS error BEFORE
//   your Dart code receives any response — the catch(e) block fires
//   and shows the generic error message.
//
// SOLUTION USED HERE — corsproxy.io CORS proxy:
//   We wrap the Google API URL inside corsproxy.io:
//     https://corsproxy.io/?<encoded_google_url>
//   The proxy fetches Google's response server-side and returns it
//   with proper CORS headers so the browser accepts it.
//   The response is the raw Google JSON — no unwrapping needed.
//
// ALTERNATIVE: If deploying to production, replace _fetchSuggestions()
//   proxy approach with your own backend endpoint that calls Google and
//   returns the result — then no CORS issue at all.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ─── Your API key (confirmed working via curl) ────────────────────────────────
const String _kPlacesApiKey = 'AIzaSyBSWEaKZiYdbjGXPqQIev-5GrKsmpl9Hig';

// ── Data model ────────────────────────────────────────────────────────────────
class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  String get fullDescription => secondaryText.isEmpty
      ? mainText
      : '$mainText, $secondaryText';

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'] as Map<String, dynamic>?;
    return PlaceSuggestion(
      placeId      : json['place_id']  as String? ?? '',
      mainText     : structured?['main_text']      as String? ?? '',
      secondaryText: structured?['secondary_text'] as String? ?? '',
    );
  }
}

// ── SocietySearchField ────────────────────────────────────────────────────────
class SocietySearchField extends StatefulWidget {
  final bool                          isDark;
  final Color                         accentColor;
  final ValueChanged<PlaceSuggestion> onSelected;
  final PlaceSuggestion?              initialValue;

  const SocietySearchField({
    super.key,
    required this.isDark,
    required this.accentColor,
    required this.onSelected,
    this.initialValue,
  });

  @override
  State<SocietySearchField> createState() => _SocietySearchFieldState();
}

class _SocietySearchFieldState extends State<SocietySearchField> {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();

  Timer?                _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool                  _isLoading   = false;
  String?               _errorMsg;
  OverlayEntry?         _overlayEntry;
  PlaceSuggestion?      _selected;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _selected  = widget.initialValue;
      _ctrl.text = widget.initialValue!.mainText;
    }
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _ctrl.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  // ── Focus ─────────────────────────────────────────────────────────────────

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 180), _removeOverlay);
    }
  }

  // ── Text change → debounced fetch ─────────────────────────────────────────

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      _selected = null;
      _clearOverlay();
      return;
    }
    if (value.trim().length < 2) {
      _clearOverlay();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(value.trim());
    });
  }

  // ── CORS-safe Google Places fetch ─────────────────────────────────────────
  //
  // WHAT HAPPENS STEP BY STEP:
  //
  //  1. Build the real Google Places Autocomplete URL.
  //  2. Encode it and pass it to corsproxy.io.
  //  3. http.get() calls corsproxy.io — allowed by the browser because
  //     corsproxy.io sends back "Access-Control-Allow-Origin: *".
  //  4. corsproxy.io fetches Google server-side and returns the raw JSON.
  //  5. Parse predictions directly from the response.
  //
  Future<void> _fetchSuggestions(String input) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });

    try {
      // ── Step 1: Build the real Google Places URL ───────────────────────
      final bool hasHint =
          input.toLowerCase().contains('society')   ||
              input.toLowerCase().contains('apartment') ||
              input.toLowerCase().contains('enclave')   ||
              input.toLowerCase().contains('residency') ||
              input.toLowerCase().contains('housing')   ||
              input.toLowerCase().contains('tower');
      final String biasedInput = hasHint ? input : '$input apartment';

      // Build Google URL as a plain string first (for proxy encoding)
      final googleUrl =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(biasedInput)}'
          '&types=establishment'
          '&components=country:in'
          '&language=en'
          '&key=$_kPlacesApiKey';

      // ── Step 2: Wrap in corsproxy.io ──────────────────────────────────
      // corsproxy.io is a reliable CORS proxy that:
      //   • Fetches Google server-side (no browser CORS block)
      //   • Returns the raw Google JSON directly (no wrapper object)
      //   • Sends "Access-Control-Allow-Origin: *" so the browser accepts it
      final proxyUri = Uri.parse(
        'https://corsproxy.io/?${Uri.encodeComponent(googleUrl)}',
      );

      // ── Step 3: Make the browser-safe HTTP call ────────────────────────
      final proxyResponse = await http
          .get(proxyUri, headers: {'x-requested-with': 'XMLHttpRequest'})
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (proxyResponse.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _errorMsg  = 'Proxy error \${proxyResponse.statusCode}. Try again.';
        });
        return;
      }

      // ── Step 4: Decode Google response directly ────────────────────────
      // corsproxy.io returns the raw Google JSON — no unwrapping needed
      final googleBody = jsonDecode(proxyResponse.body) as Map<String, dynamic>;
      final String status = googleBody['status'] as String? ?? '';

      // ── Step 5: Parse exactly as before ───────────────────────────────
      if (status == 'OK') {
        final predictions = googleBody['predictions'] as List<dynamic>;
        final results = predictions
            .map((p) => PlaceSuggestion.fromJson(p as Map<String, dynamic>))
            .where((s) => s.mainText.isNotEmpty)
            .toList();

        setState(() {
          _suggestions = results;
          _isLoading   = false;
        });

        if (results.isNotEmpty) {
          _showSuggestionOverlay();
        } else {
          _removeOverlay();
        }

      } else if (status == 'ZERO_RESULTS') {
        setState(() {
          _suggestions = [];
          _isLoading   = false;
        });
        _removeOverlay();

      } else {
        // REQUEST_DENIED, INVALID_REQUEST, OVER_QUERY_LIMIT, etc.
        setState(() {
          _isLoading = false;
          _errorMsg  = switch (status) {
            'REQUEST_DENIED'   => 'API key invalid or Places API not enabled.',
            'OVER_QUERY_LIMIT' => 'API quota exceeded. Try again later.',
            'INVALID_REQUEST'  => 'Invalid search query.',
            _                  => 'Google API error: $status',
          };
        });
        _removeOverlay();
      }

    } on TimeoutException {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg  = 'Request timed out. Check internet connection.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Show the actual exception so you can debug if needed
          _errorMsg  = 'Search error: ${e.toString()}';
        });
        debugPrint('SocietySearchField error: $e');
      }
    }
  }

  // ── Suggestion selected ───────────────────────────────────────────────────

  void _selectSuggestion(PlaceSuggestion s) {
    setState(() {
      _selected    = s;
      _ctrl.text   = s.mainText;
      _suggestions = [];
      _errorMsg    = null;
    });
    _removeOverlay();
    _focusNode.unfocus();
    widget.onSelected(s);
  }

  // ── Clear helpers ─────────────────────────────────────────────────────────

  void _clearOverlay() {
    setState(() {
      _suggestions = [];
      _isLoading   = false;
    });
    _removeOverlay();
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _errorMsg = null;
    });
    _ctrl.clear();
    _clearOverlay();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  // ── Overlay management ────────────────────────────────────────────────────

  void _showSuggestionOverlay() {
    _removeOverlay();
    if (!mounted) return;

    final overlay = Overlay.of(context);
    final isDark  = widget.isDark;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top : 0,
        child: CompositedTransformFollower(
          link            : _layerLink,
          showWhenUnlinked: false,
          offset          : const Offset(0, 62),
          child: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: _SuggestionPanel(
              isDark     : isDark,
              accentColor: widget.accentColor,
              suggestions: _suggestions,
              onTap      : _selectSuggestion,
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark     = widget.isDark;
    final accent     = widget.accentColor;
    final Color fill = isDark ? const Color(0xFF1A1D35) : const Color(0xFFF5F7FF);
    final Color brd  = isDark ? const Color(0xFF2A2A4A) : const Color(0xFFCDD3E8);
    final Color txt  = isDark ? Colors.white             : const Color(0xFF1A1F36);
    final Color hint = isDark ? const Color(0xFF3A3A5C)  : Colors.grey.shade400;
    final Color lbl  = isDark ? Colors.white54           : Colors.grey.shade600;

    final bool hasSelection = _selected != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Label ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'SOCIETY / APARTMENT *',
            style: TextStyle(
              color        : isDark ? const Color(0xFF7A7AAA) : Colors.grey.shade500,
              fontSize     : 10,
              fontWeight   : FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),

        // ── Input + overlay anchor ────────────────────────────────────────
        CompositedTransformTarget(
          link : _layerLink,
          child: TextField(
            controller     : _ctrl,
            focusNode      : _focusNode,
            onChanged      : _onTextChanged,
            style          : TextStyle(
                color: txt, fontSize: 15, fontWeight: FontWeight.w500),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText : 'Search society or apartment name…',
              hintStyle: TextStyle(color: hint, fontSize: 13.5),
              labelText: 'Society / Apartment',
              labelStyle: TextStyle(color: lbl, fontSize: 14),
              prefixIcon: Icon(
                Icons.location_city_rounded,
                color: hasSelection
                    ? accent
                    : (isDark ? Colors.white38 : Colors.grey),
                size: 20,
              ),
              suffixIcon: _buildSuffixIcon(accent, isDark),
              filled    : true,
              fillColor : hasSelection ? accent.withOpacity(0.06) : fill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide  : BorderSide(color: brd),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide  : BorderSide(
                  color: hasSelection ? accent.withOpacity(0.5) : brd,
                  width: hasSelection ? 1.8 : 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide  : BorderSide(color: accent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 15),
            ),
          ),
        ),

        // ── Status messages ───────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child   : _buildStatusRow(isDark, accent),
        ),
      ],
    );
  }

  Widget _buildSuffixIcon(Color accent, bool isDark) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
    }
    if (_selected != null) {
      return IconButton(
        icon     : Icon(Icons.check_circle_rounded, color: accent, size: 22),
        onPressed: _clearSelection,
        tooltip  : 'Clear selection',
      );
    }
    if (_ctrl.text.isNotEmpty) {
      return IconButton(
        icon: Icon(Icons.close_rounded,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
            size: 20),
        onPressed: _clearSelection,
        tooltip  : 'Clear',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildStatusRow(bool isDark, Color accent) {
    if (_selected != null) {
      return Padding(
        key    : const ValueKey('selected'),
        padding: const EdgeInsets.only(top: 6, left: 4),
        child  : Row(children: [
          Icon(Icons.place_rounded, size: 13, color: accent),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              _selected!.fullDescription,
              style: TextStyle(
                  color: accent, fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      );
    }
    if (_errorMsg != null) {
      return Padding(
        key    : const ValueKey('error'),
        padding: const EdgeInsets.only(top: 6, left: 4),
        child  : Row(children: [
          const Icon(Icons.warning_amber_rounded,
              size: 13, color: Colors.redAccent),
          const SizedBox(width: 5),
          Expanded(
            child: Text(_errorMsg!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ),
        ]),
      );
    }
    if (_ctrl.text.isNotEmpty && _ctrl.text.length < 2) {
      return Padding(
        key    : const ValueKey('hint'),
        padding: const EdgeInsets.only(top: 5, left: 4),
        child  : Text(
          'Type at least 2 characters to search…',
          style: TextStyle(
              color  : isDark ? Colors.white24 : Colors.grey.shade400,
              fontSize: 11),
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('empty'));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SuggestionPanel — floating overlay with results (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _SuggestionPanel extends StatelessWidget {
  final bool                          isDark;
  final Color                         accentColor;
  final List<PlaceSuggestion>         suggestions;
  final ValueChanged<PlaceSuggestion> onTap;

  const _SuggestionPanel({
    required this.isDark,
    required this.accentColor,
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;
    final double panelW  = screenW - 48;
    final Color  panelBg = isDark ? const Color(0xFF1A1D35) : Colors.white;
    final Color  panelBd = isDark ? const Color(0xFF2A2A4A) : const Color(0xFFDDE3F5);
    final Color  divColor= isDark ? Colors.white10           : Colors.grey.shade100;

    return Material(
      color: Colors.transparent,
      child: Container(
        width      : panelW,
        constraints: const BoxConstraints(maxHeight: 280),
        decoration : BoxDecoration(
          color       : panelBg,
          borderRadius: BorderRadius.circular(14),
          border      : Border.all(color: panelBd),
          boxShadow   : [
            BoxShadow(
              color     : isDark
                  ? Colors.black.withOpacity(0.45)
                  : Colors.blueGrey.withOpacity(0.12),
              blurRadius: 24,
              offset    : const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ListView.separated(
            padding         : const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap      : true,
            itemCount       : suggestions.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: divColor, indent: 48),
            itemBuilder: (_, i) {
              final s = suggestions[i];
              return _SuggestionTile(
                suggestion : s,
                accentColor: accentColor,
                isDark     : isDark,
                onTap      : () => onTap(s),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SuggestionTile (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class _SuggestionTile extends StatefulWidget {
  final PlaceSuggestion suggestion;
  final Color           accentColor;
  final bool            isDark;
  final VoidCallback    onTap;

  const _SuggestionTile({
    required this.suggestion,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color hoverBg   = widget.accentColor.withOpacity(0.08);
    final Color mainColor = widget.isDark ? Colors.white : const Color(0xFF1A1F36);
    final Color subColor  = widget.isDark ? Colors.white54 : Colors.grey.shade500;

    return GestureDetector(
      onTap      : widget.onTap,
      onTapDown  : (_) => setState(() => _hovered = true),
      onTapUp    : (_) => setState(() => _hovered = false),
      onTapCancel: ()  => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color   : _hovered ? hoverBg : Colors.transparent,
        padding : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width : 32, height: 32,
            decoration: BoxDecoration(
              color       : widget.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.apartment_rounded,
                size: 16, color: widget.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.suggestion.mainText,
                  style: TextStyle(
                      color: mainColor, fontSize: 13.5, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.suggestion.secondaryText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.suggestion.secondaryText,
                    style  : TextStyle(color: subColor, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.north_west_rounded,
              size : 14,
              color: widget.isDark ? Colors.white24 : Colors.grey.shade300),
        ]),
      ),
    );
  }
}
