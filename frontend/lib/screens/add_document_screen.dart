import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vault_collaborator.dart';
import '../models/secure_document.dart';
import '../services/vault_service.dart';

class AddDocumentScreen extends StatefulWidget {
  final SecureDocument? documentToEdit;
  final DecryptedDocument? decryptedDocToEdit;

  const AddDocumentScreen({
    super.key,
    this.documentToEdit,
    this.decryptedDocToEdit,
  });

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final VaultService _vaultService = VaultService();
  final ImagePicker _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();

  String? _selectedMemberId;

  // List of custom field controllers
  final List<Map<String, TextEditingController>> _fieldControllers = [];

  // Attachment files (newly picked)
  final List<Uint8List> _newAttachmentsBytes = [];
  final List<String> _newAttachmentsNames = [];

  // Attachments fetched (existing if editing)
  List<String> _existingAttachmentPaths = [];

  bool _isSaving = false;
  String _savingStatus = '';

  @override
  void initState() {
    super.initState();
    if (widget.documentToEdit != null && widget.decryptedDocToEdit != null) {
      final doc = widget.documentToEdit!;
      final decDoc = widget.decryptedDocToEdit!;

      _titleController.text = decDoc.title;
      _categoryController.text = doc.category;
      _selectedMemberId = doc.memberId;
      _existingAttachmentPaths = List.from(doc.encryptedAttachmentPaths);

      // Populating custom fields
      decDoc.fields.forEach((key, val) {
        _fieldControllers.add({
          'key': TextEditingController(text: key),
          'value': TextEditingController(text: val),
        });
      });
    } else {
      _addCustomField();
      _selectedMemberId = FirebaseAuth.instance.currentUser?.uid;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    for (var controllerMap in _fieldControllers) {
      controllerMap['key']?.dispose();
      controllerMap['value']?.dispose();
    }
    super.dispose();
  }

  void _addCustomField({String label = '', String value = ''}) {
    setState(() {
      _fieldControllers.add({
        'key': TextEditingController(text: label),
        'value': TextEditingController(text: value),
      });
    });
  }

  void _removeCustomField(int index) {
    setState(() {
      final removed = _fieldControllers.removeAt(index);
      removed['key']?.dispose();
      removed['value']?.dispose();
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _newAttachmentsBytes.add(bytes);
          _newAttachmentsNames.add(pickedFile.name);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _pickPDF() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        setState(() {
          _newAttachmentsBytes.add(file.bytes!);
          _newAttachmentsNames.add(file.name);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking PDF: $e')),
        );
      }
    }
  }

  void _removeNewAttachment(int index) {
    setState(() {
      _newAttachmentsBytes.removeAt(index);
      _newAttachmentsNames.removeAt(index);
    });
  }

  void _removeExistingAttachment(int index) {
    setState(() {
      _existingAttachmentPaths.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final targetMemberId = _selectedMemberId ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a member owner.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _savingStatus = 'Encrypting document data locally...';
    });

    try {
      // Look up member username
      String ownerName = 'Me';
      final collaborators = await _vaultService.getVaultCollaborators().first;
      final matchedCollab = collaborators.firstWhere(
        (c) => c.uid == targetMemberId,
        orElse: () => VaultCollaborator(
          uid: targetMemberId,
          username: 'Me',
          email: '',
          collaborationId: '',
          isSelf: true,
          avatarColorValue: 0xFF3F51B5,
        ),
      );
      ownerName = matchedCollab.username;

      // Build custom fields map
      final Map<String, String> fields = {};
      for (var controllerMap in _fieldControllers) {
        final key = controllerMap['key']!.text.trim();
        final val = controllerMap['value']!.text.trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          fields[key] = val;
        }
      }

      setState(() {
        _savingStatus = _newAttachmentsBytes.isNotEmpty
            ? 'Encrypting and uploading attachments safely...'
            : 'Saving document record...';
      });

      final categoryToSave = _categoryController.text.trim();

      await _vaultService.saveDocument(
        id: widget.documentToEdit?.id,
        memberId: targetMemberId,
        ownerName: ownerName,
        category: categoryToSave.isNotEmpty ? categoryToSave : 'General',
        title: _titleController.text.trim(),
        fields: fields,
        rawImagesToUpload: _newAttachmentsBytes,
        newAttachmentsNames: _newAttachmentsNames,
        existingAttachmentPaths: _existingAttachmentPaths,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔒 Document encrypted and saved securely!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error saving document: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                '🔒 Zero-Knowledge Cryptography active',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
              ),
              const SizedBox(height: 8),
              Text(
                _savingStatus,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentToEdit != null ? 'Edit Document' : 'Secure New Document'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 28),
            onPressed: _save,
            tooltip: 'Save',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 1. Vault Collaborator / Owner Selection Card
            StreamBuilder<List<VaultCollaborator>>(
              stream: _vaultService.getVaultCollaborators(),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                final activeValue = _selectedMemberId ?? currentUid;

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: members.any((m) => m.uid == activeValue) ? activeValue : null,
                        decoration: const InputDecoration(
                          labelText: 'Belongs to Member',
                          border: InputBorder.none,
                          icon: Icon(Icons.person),
                        ),
                        validator: (val) => val == null ? 'Please select a member owner' : null,
                        items: members.map((m) {
                          return DropdownMenuItem(
                            value: m.uid,
                            child: Text(m.isSelf ? 'Myself (@${m.username})' : '@${m.username}'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() => _selectedMemberId = val);
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // 2. Document Identity & Dynamic Category Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Document Name',
                        hintText: 'e.g. Aadhar Card, SBI Savings account',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? 'Please enter a name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _categoryController,
                      decoration: InputDecoration(
                        labelText: 'Category Name',
                        hintText: 'e.g. Identity Cards, Financial, Medical...',
                        suffixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) => (val == null || val.trim().isEmpty)
                          ? 'Please enter or select a category'
                          : null,
                    ),
                    const SizedBox(height: 10),

                    // Choice chips of existing user/collaborator categories
                    StreamBuilder<List<String>>(
                      stream: _vaultService.getExistingCategories(),
                      builder: (context, catSnapshot) {
                        final existingCategories = catSnapshot.data ?? [];
                        if (existingCategories.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Existing Categories (Tap to Select):',
                              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: existingCategories.map((cat) {
                                final isSelected =
                                    _categoryController.text.trim().toLowerCase() == cat.toLowerCase();
                                return ChoiceChip(
                                  label: Text(cat),
                                  selected: isSelected,
                                  selectedColor: Colors.blue.shade100,
                                  onSelected: (selected) {
                                    setState(() {
                                      _categoryController.text = cat;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 3. Custom / Important Fields Section
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Important Fields (Encrypted)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
                          onPressed: () => _addCustomField(),
                          tooltip: 'Add custom field',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add confidential numbers, passwords, IDs, or account details. All values are client-side encrypted.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const Divider(height: 24),
                    _fieldControllers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: Text(
                                'No fields added yet. Tap "+ Add Field" below to add details.',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _fieldControllers.length,
                            itemBuilder: (context, index) {
                              final controllers = _fieldControllers[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16.0),
                                padding: const EdgeInsets.all(14.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Field #${index + 1}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.blueGrey.shade700,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          onPressed: () => _removeCustomField(index),
                                          tooltip: 'Remove Field',
                                          constraints: const BoxConstraints(),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    // 1. Label Field (Full Width)
                                    TextField(
                                      controller: controllers['key'],
                                      decoration: InputDecoration(
                                        labelText: 'Field Label / Name',
                                        hintText: 'e.g. Account Number, Password, Policy ID',
                                        prefixIcon: const Icon(Icons.label_outlined, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        filled: true,
                                        fillColor: Colors.white,
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // 2. Value Field (Full Width & Multi-line)
                                    TextField(
                                      controller: controllers['value'],
                                      maxLines: null,
                                      minLines: 2,
                                      keyboardType: TextInputType.multiline,
                                      decoration: InputDecoration(
                                        labelText: 'Field Value / Secret Content',
                                        hintText: 'Enter secret value or details...',
                                        prefixIcon: const Icon(Icons.key_outlined, size: 20),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _addCustomField(),
                        icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                        label: const Text('Add Another Important Field'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 4. Attachments (Photos) Section
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Photos / Scans / PDF Documents (End-to-End Encrypted)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _pickPDF,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Existing attachment paths (If editing)
                    if (_existingAttachmentPaths.isNotEmpty) ...[
                      const Text(
                        'Existing Attachments',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _existingAttachmentPaths.length,
                        itemBuilder: (context, index) {
                          final path = _existingAttachmentPaths[index];
                          final isPdf = path.toLowerCase().endsWith('.pdf');
                          return ListTile(
                            leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.lock, color: isPdf ? Colors.red : Colors.green),
                            title: Text(isPdf ? 'Encrypted PDF ${index + 1}' : 'Encrypted Photo ${index + 1}'),
                            subtitle: const Text('Stored securely in Cloud Storage'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeExistingAttachment(index),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Newly picked files preview
                    _newAttachmentsBytes.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: Text(
                                'No new files selected.',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ),
                          )
                        : GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _newAttachmentsBytes.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemBuilder: (context, index) {
                              final name = _newAttachmentsNames[index];
                              final isPdf = name.toLowerCase().endsWith('.pdf');
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: isPdf
                                        ? Container(
                                            color: Colors.red.shade50,
                                            width: double.infinity,
                                            height: double.infinity,
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.picture_as_pdf, color: Colors.red, size: 36),
                                                const SizedBox(height: 4),
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : Image.memory(
                                            _newAttachmentsBytes[index],
                                            width: double.infinity,
                                            height: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: GestureDetector(
                                      onTap: () => _removeNewAttachment(index),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
      ),
    );
  }
}
