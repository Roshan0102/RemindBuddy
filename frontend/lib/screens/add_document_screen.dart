import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  final _customCategoryController = TextEditingController();
  bool _isCustomCategory = false;

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
      _existingAttachmentPaths = List.from(doc.encryptedAttachmentPaths);

      final defaultCategories = ['Identity Cards', 'Financial', 'Health & Medical', 'Insurance'];
      if (!defaultCategories.contains(doc.category) && doc.category.isNotEmpty) {
        _selectedCategory = 'Others';
        _isCustomCategory = true;
        _customCategoryController.text = doc.category;
      } else {
        _selectedCategory = doc.category.isNotEmpty ? doc.category : 'Identity Cards';
        _isCustomCategory = _selectedCategory == 'Others';
      }

      // Populating custom fields
      decDoc.fields.forEach((key, val) {
        _fieldControllers.add({
          'key': TextEditingController(text: key),
          'value': TextEditingController(text: val),
        });
      });
    } else {
      // Add one default custom field empty
      _addCustomField();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customCategoryController.dispose();
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
      // Look up family member's name
      String ownerName = 'Unknown';
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final memberDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('family_members')
            .doc(_selectedMemberId)
            .get();
        if (memberDoc.exists) {
          ownerName = memberDoc.data()?['name'] ?? 'Unknown';
        }
      }

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

      final categoryToSave = _selectedCategory == 'Others'
          ? _customCategoryController.text.trim()
          : _selectedCategory;

      await _vaultService.saveDocument(
        id: widget.documentToEdit?.id,
        memberId: _selectedMemberId!,
        ownerName: ownerName,
        category: categoryToSave,
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
            // 1. Family Member Selection Card
            StreamBuilder<List<FamilyMember>>(
              stream: _vaultService.getFamilyMembers(),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                
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
                        validator: (val) => val == null ? 'Please select a member' : null,
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
                          setState(() {
                            _selectedCategory = val;
                            _isCustomCategory = val == 'Others';
                          });
                        }
                      },
                    ),
                    if (_isCustomCategory) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _customCategoryController,
                        decoration: InputDecoration(
                          labelText: 'Custom Category Name',
                          hintText: 'e.g. Vehicle, Work, Education',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (_isCustomCategory && (val == null || val.trim().isEmpty)) {
                            return 'Please enter a custom category';
                          }
                          return null;
                        },
                      ),
                    ],
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
