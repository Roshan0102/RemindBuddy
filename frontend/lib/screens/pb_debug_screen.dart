import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pb_debug_logger.dart';

class PBDebugScreen extends StatefulWidget {
  const PBDebugScreen({super.key});

  @override
  State<PBDebugScreen> createState() => _PBDebugScreenState();
}

class _PBDebugScreenState extends State<PBDebugScreen> {
  final PBDebugLogger _logger = PBDebugLogger();
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _logs = _logger.logs;
    _logger.logStream.listen((logs) {
      if (mounted) {
        setState(() {
          _logs = logs;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PB Debug Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
            tooltip: 'Copy Logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              _logger.clear();
              setState(() {
                _logs = _logger.logs;
              });
            },
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: _logs.isEmpty
          ? const Center(child: Text('No logs yet. Sync some data to see output.'))
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final isError = log.contains('❌') || log.toLowerCase().contains('error');
                final isSuccess = log.contains('✅');
                
                Color? textColor;
                if (isError) textColor = Colors.red;
                else if (isSuccess) textColor = Colors.green;
                
                return ListTile(
                  dense: true,
                  title: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: textColor,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
