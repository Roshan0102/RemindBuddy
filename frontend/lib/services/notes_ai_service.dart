import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class MathResult {
  final String expression;
  final String result;
  final int matchStartIndex;
  final int matchEndIndex;

  MathResult({
    required this.expression,
    required this.result,
    required this.matchStartIndex,
    required this.matchEndIndex,
  });
}

class NotesAiService {
  /// Evaluates an arithmetic expression ending with '=' near the cursor or end of line.
  /// Examples:
  /// - "100 + 30 =" -> "130"
  /// - "15 * 24 =" -> "360"
  /// - "15% of 2400 =" -> "360"
  /// - "1200 / 4 =" -> "300"
  static MathResult? findLastMathExpression(String text, int cursorPosition) {
    if (text.isEmpty) return null;

    final safePos = cursorPosition.clamp(0, text.length);
    // Examine text up to cursor position
    final textBeforeCursor = text.substring(0, safePos);

    // Look for the last line or clause ending with '='
    final lineStart = textBeforeCursor.lastIndexOf('\n');
    final currentLine = lineStart >= 0 ? textBeforeCursor.substring(lineStart + 1) : textBeforeCursor;

    // Pattern matching arithmetic expressions followed by '='
    // Supports +, -, *, /, x, X, ÷, and "X% of Y"
    final percentagePattern = RegExp(r'([0-9.,]+)\s*%\s*of\s*([0-9.,]+)\s*=\s*$', caseSensitive: false);
    final pctMatch = percentagePattern.firstMatch(currentLine);
    if (pctMatch != null) {
      final pStr = pctMatch.group(1)!.replaceAll(',', '');
      final totalStr = pctMatch.group(2)!.replaceAll(',', '');
      final p = double.tryParse(pStr);
      final total = double.tryParse(totalStr);
      if (p != null && total != null) {
        final res = (p / 100.0) * total;
        final resStr = _formatNumber(res);
        final fullMatch = pctMatch.group(0)!;
        final matchStart = safePos - fullMatch.length;
        return MathResult(
          expression: '${pctMatch.group(1)}% of ${pctMatch.group(2)}',
          result: resStr,
          matchStartIndex: matchStart,
          matchEndIndex: safePos,
        );
      }
    }

    // Standard math expression ending with '='
    final mathPattern = RegExp(r'((?:\(?[0-9.,]+\)?\s*[\+\-\*\/xX÷]\s*)+[0-9.,]+\)?)\s*=\s*$', caseSensitive: false);
    final mathMatch = mathPattern.firstMatch(currentLine);
    if (mathMatch != null) {
      final expr = mathMatch.group(1)!;
      final evaluated = evaluateExpression(expr);
      if (evaluated != null) {
        final resStr = _formatNumber(evaluated);
        final fullMatch = mathMatch.group(0)!;
        final matchStart = safePos - fullMatch.length;
        return MathResult(
          expression: expr.trim(),
          result: resStr,
          matchStartIndex: matchStart,
          matchEndIndex: safePos,
        );
      }
    }

    return null;
  }

  /// Scans entire text for any math expression ending with '=' and computes all missing answers
  static String solveAllMathInText(String text) {
    if (text.isEmpty) return text;

    // Replace "X% of Y =" with result
    var updated = text.replaceAllMapped(
      RegExp(r'([0-9.,]+)\s*%\s*of\s*([0-9.,]+)\s*=\s*(?![0-9])', caseSensitive: false),
      (match) {
        final p = double.tryParse(match.group(1)!.replaceAll(',', ''));
        final total = double.tryParse(match.group(2)!.replaceAll(',', ''));
        if (p != null && total != null) {
          final res = (p / 100.0) * total;
          return '${match.group(0)!.trim()} ${_formatNumber(res)}';
        }
        return match.group(0)!;
      },
    );

    // Replace standard math expressions "A + B =" with result
    updated = updated.replaceAllMapped(
      RegExp(r'((?:\(?[0-9.,]+\)?\s*[\+\-\*\/xX÷]\s*)+[0-9.,]+\)?)\s*=\s*(?![0-9])', caseSensitive: false),
      (match) {
        final expr = match.group(1)!;
        final res = evaluateExpression(expr);
        if (res != null) {
          return '${match.group(0)!.trim()} ${_formatNumber(res)}';
        }
        return match.group(0)!;
      },
    );

    return updated;
  }

  /// Safe, zero-dependency arithmetic expression evaluator with operator precedence
  static double? evaluateExpression(String rawExpr) {
    try {
      var sanitized = rawExpr
          .replaceAll('x', '*')
          .replaceAll('X', '*')
          .replaceAll('÷', '/')
          .replaceAll(',', '')
          .trim();

      // Tokenize numbers and operators
      final tokens = <String>[];
      var currentNumber = '';

      for (int i = 0; i < sanitized.length; i++) {
        final char = sanitized[i];
        if ('0123456789.'.contains(char)) {
          currentNumber += char;
        } else if ('+-*/()'.contains(char)) {
          if (currentNumber.isNotEmpty) {
            tokens.add(currentNumber);
            currentNumber = '';
          }
          // Support unary minus at start or after operator
          if (char == '-' && (tokens.isEmpty || '+-*/('.contains(tokens.last))) {
            currentNumber = '-';
          } else {
            tokens.add(char);
          }
        }
      }
      if (currentNumber.isNotEmpty) {
        tokens.add(currentNumber);
      }

      if (tokens.isEmpty) return null;

      return _parseCalculation(tokens);
    } catch (_) {
      return null;
    }
  }

  static double? _parseCalculation(List<String> tokens) {
    try {
      // 1. Process parentheses first
      while (tokens.contains('(')) {
        final openIdx = tokens.lastIndexOf('(');
        final closeIdx = tokens.indexOf(')', openIdx);
        if (closeIdx == -1) break;

        final subTokens = tokens.sublist(openIdx + 1, closeIdx);
        final subRes = _evalSimpleTokens(subTokens);
        if (subRes == null) return null;

        tokens.replaceRange(openIdx, closeIdx + 1, [subRes.toString()]);
      }

      return _evalSimpleTokens(tokens);
    } catch (_) {
      return null;
    }
  }

  static double? _evalSimpleTokens(List<String> tokens) {
    if (tokens.isEmpty) return null;
    final working = List<String>.from(tokens);

    // Pass 1: Multiplication and Division
    int i = 0;
    while (i < working.length) {
      if (working[i] == '*' || working[i] == '/') {
        if (i == 0 || i + 1 >= working.length) return null;
        final op = working[i];
        final left = double.tryParse(working[i - 1]);
        final right = double.tryParse(working[i + 1]);
        if (left == null || right == null) return null;

        if (op == '/' && right == 0) return null; // Avoid division by zero
        final res = op == '*' ? left * right : left / right;

        working.replaceRange(i - 1, i + 2, [res.toString()]);
        i--;
      } else {
        i++;
      }
    }

    // Pass 2: Addition and Subtraction
    i = 0;
    while (i < working.length) {
      if (working[i] == '+' || working[i] == '-') {
        if (i == 0 || i + 1 >= working.length) return null;
        final op = working[i];
        final left = double.tryParse(working[i - 1]);
        final right = double.tryParse(working[i + 1]);
        if (left == null || right == null) return null;

        final res = op == '+' ? left + right : left - right;
        working.replaceRange(i - 1, i + 2, [res.toString()]);
        i--;
      } else {
        i++;
      }
    }

    if (working.length == 1) {
      return double.tryParse(working[0]);
    }
    return null;
  }

  static String _formatNumber(double num) {
    if (num.isInfinite || num.isNaN) return 'Error';
    if (num == num.roundToDouble()) {
      return num.toInt().toString();
    }
    // Clean trailing zeros
    var s = num.toStringAsFixed(2);
    if (s.endsWith('.00')) {
      s = s.substring(0, s.length - 3);
    } else if (s.endsWith('0') && s.contains('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ============================================================================
  // CLOUD FUNCTION AI CALLER (Grammar Fix, Polish, Summarize, To Checklist)
  // ============================================================================

  static Future<String> callNotesAI({
    required String action,
    required String text,
    String? title,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'processNoteWithAI',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      final resp = await callable.call({
        'action': action,
        'text': text,
        'title': title ?? '',
      });

      final data = resp.data;
      if (data is Map && data['result'] != null) {
        return data['result'].toString();
      }
      return text;
    } catch (e) {
      debugPrint('[NotesAiService] Error calling processNoteWithAI: $e');
      rethrow;
    }
  }
}
