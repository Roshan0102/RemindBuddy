import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/secure_document.dart';
import '../services/vault_service.dart';
import 'add_document_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  final SecureDocument document;
  final DecryptedDocument decryptedDocument;

  const DocumentDetailScreen({
    super.key,
    required this.document,
    required this.decryptedDocument,
  });

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final VaultService _vaultService = VaultService();
  late DecryptedDocument _decDoc;
  late SecureDocument _rawDoc;

  // Track hidden state of each field by key
  final Map<String, bool> _fieldVisibility = {};

  @override
  void initState() {
    super.initState();
    _decDoc = widget.decryptedDocument;
    _rawDoc = widget.document;
    
    // Default all fields to visible for easier readability by elderly parents
    for (var key in _decDoc.fields.keys) {
      _fieldVisibility[key] = true;
    }
  }

  void _toggleVisibility(String key) {
    setState(() {
      _fieldVisibility[key] = !(_fieldVisibility[key] ?? true);
    });
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label to clipboard!'),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareField(String label, String value) {
    Share.share('$label: $value', subject: 'Secure Document Detail');
  }

  void _showFullscreenImage(Uint8List imageBytes, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenImageViewer(
          imageBytes: imageBytes,
          title: '${_decDoc.title}_Attachment_${index + 1}',
        ),
      ),
    );
  }

  void _editDocument() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDocumentScreen(
          documentToEdit: _rawDoc,
          decryptedDocToEdit: _decDoc,
        ),
      ),
    );
    _refreshDocument();
  }

  Future<void> _refreshDocument() async {
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document?'),
        content: const Text(
          'This will permanently delete this document and all its encrypted attachments. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await _vaultService.deleteDocument(_rawDoc);

      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        Navigator.pop(context); // Pop detail screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document deleted successfully.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_decDoc.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editDocument,
            tooltip: 'Edit Document',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: _deleteDocument,
            tooltip: 'Delete Document',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. Info Card (Category & Last Updated)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock, color: Colors.blue, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _rawDoc.category,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last updated: ${_rawDoc.lastUpdated.day}/${_rawDoc.lastUpdated.month}/${_rawDoc.lastUpdated.year}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. Custom Fields Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Document Credentials',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Divider(height: 24),
                  _decDoc.fields.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'No credential fields saved for this document.',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _decDoc.fields.length,
                          itemBuilder: (context, index) {
                            final key = _decDoc.fields.keys.elementAt(index);
                            final val = _decDoc.fields[key]!;
                            final isVisible = _fieldVisibility[key] ?? true;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    key,
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: SelectableText(
                                            isVisible ? val : '••••••••••••••••',
                                            style: TextStyle(
                                              fontSize: 20, // Large text for elderly parents
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                              fontFamily: isVisible ? null : 'monospace',
                                              letterSpacing: isVisible ? null : 2.0,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off,
                                              color: Colors.grey),
                                          onPressed: () => _toggleVisibility(key),
                                          tooltip: 'Toggle Visibility',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.copy, color: Colors.blueAccent),
                                          onPressed: () => _copyToClipboard(key, val),
                                          tooltip: 'Copy to Clipboard',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.share, color: Colors.teal),
                                          onPressed: () => _shareField(key, val),
                                          tooltip: 'Share Field',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 3. Encrypted Attachments Section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attachments (Decrypted in Memory)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Divider(height: 24),
                  _rawDoc.encryptedAttachmentPaths.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'No image scans attached.',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _rawDoc.encryptedAttachmentPaths.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.3,
                          ),
                          itemBuilder: (context, index) {
                            final storagePath = _rawDoc.encryptedAttachmentPaths[index];
                            return FutureBuilder<Uint8List?>(
                              future: _vaultService.downloadAndDecryptAttachment(storagePath),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }

                                final bytes = snapshot.data;
                                if (bytes == null || bytes.isEmpty) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.broken_image, color: Colors.red),
                                    ),
                                  );
                                }

                                return GestureDetector(
                                  onTap: () => _showFullscreenImage(bytes, index),
                                  child: Hero(
                                    tag: storagePath,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.memory(
                                            bytes,
                                            fit: BoxFit.cover,
                                          ),
                                          Positioned(
                                            bottom: 4,
                                            right: 4,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class FullscreenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;

  const FullscreenImageViewer({
    super.key,
    required this.imageBytes,
    required this.title,
  });

  Future<void> _shareImage() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$title.jpg';
      final file = File(tempPath);
      await file.writeAsBytes(imageBytes);
      
      await Share.shareXFiles([XFile(tempPath)], text: title);
    } catch (_) {}
  }

  Future<void> _downloadImage(BuildContext context) async {
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to locate download directory.')),
        );
        return;
      }

      final fileName = '${title.replaceAll(RegExp(r'[^\w\-_]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${downloadsDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Downloads folder: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save image: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareImage,
            tooltip: 'Share Image',
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () => _downloadImage(context),
            tooltip: 'Save to Gallery/Downloads',
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(imageBytes),
        ),
      ),
    );
  }
}
