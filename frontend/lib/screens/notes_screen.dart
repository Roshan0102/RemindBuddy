import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../services/storage_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final StorageService _storageService = StorageService();

  Future<void> _addOrEditNote({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    bool isLocked = note?.isLocked ?? false;

    // Check Lock
    if (note != null && note.isLocked) {
      bool authenticated = await _showPinDialog();
      if (!authenticated) return;
    }

    bool _isSaving = false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => Scaffold(
            appBar: AppBar(
              title: Text(note == null ? 'New Note' : 'Edit Note'),
              actions: [
                IconButton(
                  icon: Icon(isLocked ? Icons.lock : Icons.lock_open, 
                    color: isLocked ? Colors.red : Colors.green),
                  onPressed: () {
                    setDialogState(() {
                      isLocked = !isLocked;
                    });
                  },
                  tooltip: isLocked ? 'Unlock Note' : 'Lock Note (PIN: 0000)',
                ),
                _isSaving 
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(
                      onPressed: () async {
                        if (titleController.text.isNotEmpty || contentController.text.isNotEmpty) {
                          setDialogState(() => _isSaving = true);
                          final newNote = Note(
                            id: note?.id,
                            title: titleController.text,
                            content: contentController.text,
                            date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                            isLocked: isLocked,
                          );
                          try {
                            if (note == null) {
                              await _storageService.insertNote(newNote);
                            } else {
                              await _storageService.updateNote(newNote);
                            }
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            setDialogState(() => _isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error saving note: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
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

  final List<Color> _aestheticColors = [
    const Color(0xFFFFE5E5), // Soft Pink
    const Color(0xFFE5FFEB), // Mint
    const Color(0xFFE5F6FF), // Soft Blue
    const Color(0xFFFFF9E5), // Soft Yellow
    const Color(0xFFF3E5FF), // Lavender
    const Color(0xFFFFECE5), // Peach
    const Color(0xFFE5FFF9), // Aqua
  ];

  Color _getNoteColor(String id, String content) {
    int hash = id.hashCode + content.hashCode;
    return _aestheticColors[hash.abs() % _aestheticColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Note>>(
        stream: _storageService.getNotesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final notes = snapshot.data ?? [];
          
          if (notes.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 50),
              Center(child: Text('No notes yet. Tap + to add one.\nUpdates are synced in real-time.', textAlign: TextAlign.center))
            ]);
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final Color noteColor = _getNoteColor(note.id ?? '', note.title + note.content);
              
              return Card(
                elevation: 0,
                color: noteColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  onTap: () => _addOrEditNote(note: note),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (note.title.isNotEmpty)
                              Expanded(
                                child: Text(
                                  note.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (note.isLocked) const Icon(Icons.lock, size: 14, color: Colors.black54),
                          ],
                        ),
                        if (note.title.isNotEmpty) const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            note.isLocked ? 'Locked Content' : note.content,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              color: Colors.black54, 
                              fontSize: 13,
                              fontStyle: note.isLocked ? FontStyle.italic : FontStyle.normal
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('MMM d').format(DateFormat('yyyy-MM-dd HH:mm').parse(note.date)),
                              style: const TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.bold),
                            ),
                            GestureDetector(
                              onTap: () async {
                                if (note.isLocked) {
                                  bool auth = await _showPinDialog();
                                  if (!auth) return;
                                }
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Note'),
                                    content: const Text('Are you sure?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true), 
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text('Delete')
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm != true) return;
                                await _storageService.deleteNote(note.id!);
                              },
                              child: const Icon(Icons.delete_outline, size: 18, color: Colors.black38),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditNote(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
