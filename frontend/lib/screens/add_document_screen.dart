import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/family_member.dart';
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
  
  String? _selectedMemberId;
  String _selectedCategory = 'Identity Cards';
  
  final List<String> _categories = [
    'Identity Cards',
    'Financial',
    'Health & Medical',
    'Insurance',
    'Others'
  ];

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
      _selectedMemberId = doc.memberId;
      _selectedCategory = doc.category;
      _existingAttachmentPaths = List.from(doc.encryptedAttachmentPaths);

      // Populating custom fields
      decDoc.fields.forEach((key, val) {
        _fieldControllers.add({
          'key': TextEditingController(text: key),
          'value': TextEditingController(text: val),
        });
      });
    } else {
      // Add one default custom field empty
      _addCustomField(label: 'Document Number');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
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
    if (_selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a family member.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _savingStatus = 'Encrypting document data locally...';
    });

    try {
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

      await _vaultService.saveDocument(
        id: widget.documentToEdit?.id,
        memberId: _selectedMemberId!,
        category: _selectedCategory,
        title: _titleController.text.trim(),
        fields: fields,
        rawImagesToUpload: _newAttachmentsBytes,
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
            // 1. Family Member Selection Card
            StreamBuilder<List<FamilyMember>>(
              stream: _vaultService.getFamilyMembers(),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                
                // If memberId was preselected but no longer in list, handle it
                if (members.isNotEmpty && _selectedMemberId == null) {
                  _selectedMemberId = members.first.id;
                }

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: _selectedMemberId,
                        decoration: const InputDecoration(
                          labelText: 'Belongs to Member',
                          border: InputBorder.none,
                          icon: Icon(Icons.person),
                        ),
                        items: members.map((m) {
                          return DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name),
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

            // 2. Document Identity Information Card
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
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _categories.map((c) {
                        return DropdownMenuItem(value: c, child: Text(c));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                        }
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
                          icon: const Icon(Icons.add_circle, color: Colors.blue),
                          onPressed: () => _addCustomField(),
                          tooltip: 'Add custom field',
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _fieldControllers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: Text(
                                'No fields added. Click + to add details like Card number, account password, etc.',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
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
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: controllers['key'],
                                        decoration: InputDecoration(
                                          labelText: 'Label',
                                          hintText: 'e.g. Account Number',
                                          isDense: true,
                                          border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 4,
                                      child: TextField(
                                        controller: controllers['value'],
                                        decoration: InputDecoration(
                                          labelText: 'Value',
                                          hintText: 'Secret value',
                                          isDense: true,
                                          border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => _removeCustomField(index),
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

            // 4. Attachments (Photos) Section
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Photos / Scans (End-to-End Encrypted)',
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
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
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
                          return ListTile(
                            leading: const Icon(Icons.lock, color: Colors.green),
                            title: Text('Encrypted Photo ${index + 1}'),
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
                                'No new photos selected.',
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
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
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
