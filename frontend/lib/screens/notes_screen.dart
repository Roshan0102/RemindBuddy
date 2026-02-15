import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final StorageService _storageService = StorageService();
  List<Note> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final notes = await _storageService.getNotes();
    setState(() {
      _notes = notes;
    });
  }

  Future<void> _addOrEditNote({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    bool isLocked = note?.isLocked ?? false;

    // Check Lock
    if (note != null && note.isLocked) {
      bool authenticated = await _showPinDialog();
      if (!authenticated) return;
    }

    // Use full screen dialog instead of bottom sheet
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(note == null ? 'New Note' : 'Edit Note'),
            actions: [
              IconButton(
                icon: Icon(isLocked ? Icons.lock : Icons.lock_open, 
                  color: isLocked ? Colors.red : Colors.green),
                onPressed: () {
                  setState(() {
                    isLocked = !isLocked;
                  });
                },
                tooltip: isLocked ? 'Unlock Note' : 'Lock Note (PIN: 0000)',
              ),
              TextButton(
                onPressed: () async {
                  if (titleController.text.isNotEmpty || contentController.text.isNotEmpty) {
                    final newNote = Note(
                      id: note?.id,
                      remoteId: note?.remoteId,
                      title: titleController.text,
                      content: contentController.text,
                      date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      isLocked: isLocked,
                    );
                    if (note == null) {
                      await _storageService.insertNote(newNote);
                    } else {
                      await _storageService.updateNote(newNote);
                    }
                    
                    // Trigger sync
                    try {
                      SyncService(AuthService().pb).syncNotes();
                    } catch (e) { print(e); }

                    _loadNotes();
                    if (mounted) Navigator.pop(context);
                  }
                },
                child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    hintStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  autofocus: note == null,
                ),
                const Divider(),
                Expanded(
                  child: TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      hintText: 'Start typing your note...',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showPinDialog() async {
    final pinController = TextEditingController();
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: const InputDecoration(hintText: 'Enter PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (pinController.text == '0000') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _notes.isEmpty
          ? const Center(child: Text('No notes yet. Tap + to add one.'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _addOrEditNote(note: note),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (note.title.isNotEmpty)
                                Text(
                                  note.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (note.isLocked) const Icon(Icons.lock, size: 16, color: Colors.red),
                            ],
                          ),
                          if (note.title.isNotEmpty) const SizedBox(height: 8),
                          Text(
                            note.isLocked ? 'Locked Content' : note.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[700], fontStyle: note.isLocked ? FontStyle.italic : FontStyle.normal),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                note.date,
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Colors.grey),
                                onPressed: () async {
                                  if (note.isLocked) {
                                    bool auth = await _showPinDialog();
                                    if (!auth) return;
                                  }
                                  await _storageService.deleteNote(note.id!);
                                  try {
                                    SyncService(AuthService().pb).syncNotes();
                                  } catch (e) { print(e); }
                                  _loadNotes();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditNote(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
