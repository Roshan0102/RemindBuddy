import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

  void _shareField(String docCategory, String profileName, String value) {
    final String cleanCat = docCategory.trim().isNotEmpty ? docCategory.trim() : 'Document';
    final String cleanProf = profileName.trim().isNotEmpty ? profileName.trim() : 'Myself';
    // ignore: deprecated_member_use
    Share.share('$cleanCat\n$cleanProf: $value', subject: '$cleanCat Details');
  }

  void _showFullscreenFile(
    Uint8List fileBytes,
    String storagePath,
    bool isPdf,
    String profileName,
    String docCategory,
    int imgIdx,
  ) {
    final ext = storagePath.contains('.')
        ? storagePath.substring(storagePath.lastIndexOf('.'))
        : (isPdf ? '.pdf' : '.jpg');
    final cleanProfile = profileName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
    final cleanCategory = docCategory.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
    final indexSuffix = imgIdx > 0 ? '_${imgIdx + 1}' : '';
    final cleanName = '$cleanProfile-$cleanCategory$indexSuffix$ext';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenFileViewer(
          fileBytes: fileBytes,
          title: cleanName,
          isPdf: isPdf,
        ),
      ),
    );
  }

  void _shareFileDirectly(
    Uint8List fileBytes,
    String storagePath,
    bool isPdf,
    String profileName,
    String docCategory,
    int imgIdx,
  ) async {
    try {
      final ext = storagePath.contains('.')
          ? storagePath.substring(storagePath.lastIndexOf('.'))
          : (isPdf ? '.pdf' : '.jpg');
      final cleanProfile = profileName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
      final cleanCategory = docCategory.replaceAll(RegExp(r'[^\w\s\-]'), '').trim();
      final indexSuffix = imgIdx > 0 ? '_${imgIdx + 1}' : '';
      final cleanName = '$cleanProfile-$cleanCategory$indexSuffix$ext';

      if (kIsWeb) {
        final mime = isPdf ? 'application/pdf' : 'image/jpeg';
        final base64Data = base64Encode(fileBytes);
        final url = 'data:$mime;base64,$base64Data';
        await launchUrl(Uri.parse(url));
        return;
      }
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$cleanName';
      final file = File(tempPath);
      await file.writeAsBytes(fileBytes);
      
      await Share.shareXFiles([XFile(tempPath)], text: cleanName);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing: $e')),
      );
    }
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
    return StreamBuilder<List<VaultMemberProfile>>(
      stream: _vaultService.getMemberProfilesStream(),
      builder: (context, profilesSnap) {
        final profiles = profilesSnap.data ?? [];
        final profilesMap = {for (var p in profiles) p.id: p};
        final profile = profilesMap[_rawDoc.memberId];
        final profileName = (profile != null && profile.rawName.isNotEmpty) ? profile.rawName : 'Myself';
        final docCategory = _decDoc.original.category.isNotEmpty ? _decDoc.original.category : _decDoc.title;

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
              // 1. Document Overview Header Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.blueAccent.withOpacity(0.15),
                        child: const Icon(Icons.description, color: Colors.blueAccent, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _decDoc.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Category: ${_decDoc.original.category}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                            ),
                            Text(
                              'Shared Mode: ${_decDoc.original.sharedMode.toUpperCase()}',
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Decrypted Credentials/Fields Section
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Document Fields (Decrypted)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const Divider(height: 24),
                      _decDoc.fields.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('No credential fields available.', style: TextStyle(color: Colors.grey)),
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
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        key.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
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
                                              onPressed: () => _shareField(docCategory, profileName, val),
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
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('No attachments linked to this document.', style: TextStyle(color: Colors.grey)),
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
                                final isPdf = storagePath.toLowerCase().endsWith('.pdf');
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

                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showFullscreenFile(bytes, storagePath, isPdf, profileName, docCategory, index),
                                          child: Hero(
                                            tag: storagePath,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: isPdf
                                                  ? Container(
                                                      color: Colors.red.shade50,
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          const Icon(Icons.picture_as_pdf, color: Colors.red, size: 40),
                                                          const SizedBox(height: 6),
                                                          Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                                            child: Text(
                                                              storagePath.split('/').last.split('_-_').last,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                  : Image.memory(
                                                      bytes,
                                                      fit: BoxFit.cover,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: GestureDetector(
                                            onTap: () => _shareFileDirectly(bytes, storagePath, isPdf, profileName, docCategory, index),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.share, color: Colors.white, size: 16),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.lock, color: Colors.greenAccent, size: 14),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FullscreenFileViewer extends StatelessWidget {
  final Uint8List fileBytes;
  final String title;
  final bool isPdf;

  const FullscreenFileViewer({
    super.key,
    required this.fileBytes,
    required this.title,
    required this.isPdf,
  });

  Future<void> _shareFile() async {
    if (kIsWeb) {
      try {
        final mime = isPdf ? 'application/pdf' : 'image/jpeg';
        final base64Data = base64Encode(fileBytes);
        final url = 'data:$mime;base64,$base64Data';
        await launchUrl(Uri.parse(url));
      } catch (_) {}
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$title';
      final file = File(tempPath);
      await file.writeAsBytes(fileBytes);
      
      await Share.shareXFiles([XFile(tempPath)], text: title);
    } catch (_) {}
  }

  Future<void> _downloadFile(BuildContext context) async {
    if (kIsWeb) {
      try {
        final mime = isPdf ? 'application/pdf' : 'image/jpeg';
        final base64Data = base64Encode(fileBytes);
        final url = 'data:$mime;base64,$base64Data';
        await launchUrl(Uri.parse(url));
      } catch (_) {}
      return;
    }
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to locate download directory.')),
        );
        return;
      }

      final fileName = title.replaceAll(RegExp(r'[^\w\-_.]'), '_');
      final filePath = '${downloadsDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Downloads folder: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isPdf ? Colors.white : Colors.black,
      appBar: AppBar(
        backgroundColor: isPdf ? Colors.blueAccent : Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareFile,
            tooltip: 'Share File',
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () => _downloadFile(context),
            tooltip: 'Save to Gallery/Downloads',
          ),
        ],
      ),
      body: Center(
        child: isPdf
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.picture_as_pdf, color: Colors.red, size: 100),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _shareFile,
                    icon: const Icon(Icons.share),
                    label: const Text('Share PDF Document'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              )
            : Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 0.5,
                  maxScale: 4,
                  child: Image.memory(fileBytes),
                ),
              ),
      ),
    );
  }
}
