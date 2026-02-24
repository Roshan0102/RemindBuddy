import 'dart:async';

class PBDebugLogger {
  // Singleton pattern
  static final PBDebugLogger _instance = PBDebugLogger._internal();

  factory PBDebugLogger() {
    return _instance;
  }

  PBDebugLogger._internal();

  final List<String> _logs = [];
  final _logStreamController = StreamController<List<String>>.broadcast();

  Stream<List<String>> get logStream => _logStreamController.stream;

  List<String> get logs => List.unmodifiable(_logs);

  void log(String message) {
    print(message); // Still print to regular console
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _logs.insert(0, '[$timestamp] $message');
    // Keep reasonable max size
    if (_logs.length > 500) {
      _logs.removeLast();
    }
    _logStreamController.add(_logs);
  }

  void clear() {
    _logs.clear();
    _logStreamController.add(_logs);
  }
}

// Global convenience method
void pbLog(String message) {
  PBDebugLogger().log(message);
}
