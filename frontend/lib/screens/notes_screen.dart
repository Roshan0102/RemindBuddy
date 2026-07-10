import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/note.dart';
import '../services/storage_service.dart';
import '../widgets/collaboration_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final StorageService _storageService = StorageService();
  List<String> _customOrderIds = [];

  @override
  void initState() {
    super.initState();
    _loadCustomOrder();
  }

  Future<void> _loadCustomOrder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customOrderIds = prefs.getStringList('notes_custom_order_$uid') ?? [];
    });
  }

  Future<void> _saveCustomOrder(List<String> order) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notes_custom_order_$uid', order);
  }

  List<Note> _sortNotesWithCustomOrder(List<Note> notes) {
    if (_customOrderIds.isEmpty) return List<Note>.from(notes);
    
    final sorted = List<Note>.from(notes);
    sorted.sort((a, b) {
      final aIndex = _customOrderIds.indexOf(a.id ?? '');
      final bIndex = _customOrderIds.indexOf(b.id ?? '');
      
      if (aIndex != -1 && bIndex != -1) {
        return aIndex.compareTo(bIndex);
      }
      if (aIndex != -1) return 1;
      if (bIndex != -1) return -1;
      return b.date.compareTo(a.date);
    });
    return sorted;
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

    bool isSaving = false;
    bool hasSaved = false;

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: true,
            onPopInvokedWithResult: (bool didPop, Object? result) async {
              if (didPop && !hasSaved) {
                final title = titleController.text;
                final content = contentController.text;
                if (note == null) {
                  if (title.isNotEmpty || content.isNotEmpty) {
                    hasSaved = true;
                    final newNote = Note(
                      title: title,
                      content: content,
                      date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      isLocked: isLocked,
                      sharedWith: [],
                    );
                    try {
                      await _storageService.insertNote(newNote);
                    } catch (e) {
                      debugPrint("Error auto-saving new note: $e");
                    }
                  }
                } else {
                  if (title != note.title || content != note.content || isLocked != note.isLocked) {
                    hasSaved = true;
                    final updatedNote = Note(
                      id: note.id,
                      title: title,
                      content: content,
                      date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      isLocked: isLocked,
                      ownerUid: note.ownerUid,
                      sharedWith: note.sharedWith,
                    );
                    try {
                      await _storageService.updateNote(updatedNote);
                    } catch (e) {
                      debugPrint("Error auto-saving updated note: $e");
                    }
                  }
                }
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(note == null ? 'New Note' : 'Edit Note'),
                actions: [
                  IconButton(
                    icon: Icon(isLocked ? Icons.lock : Icons.lock_open, 
                      color: isLocked ? Colors.red : Colors.green),
                    onPressed: () async {
                      if (!isLocked) {
                        bool hasPin = await _ensureNotesPin(context);
                        if (!hasPin) return;
                      }
                      setDialogState(() {
                        isLocked = !isLocked;
                      });
                    },
                    tooltip: isLocked ? 'Unlock Note' : 'Lock Note',
                  ),
                  isSaving 
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton(
                        onPressed: () async {
                          if (titleController.text.isNotEmpty || contentController.text.isNotEmpty) {
                            setDialogState(() {
                              isSaving = true;
                              hasSaved = true;
                            });
                            final newNote = Note(
                              id: note?.id,
                              title: titleController.text,
                              content: contentController.text,
                              date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                              isLocked: isLocked,
                              ownerUid: note?.ownerUid,
                              sharedWith: note?.sharedWith ?? [],
                            );
                            try {
                              if (note == null) {
                                await _storageService.insertNote(newNote);
                              } else {
                                await _storageService.updateNote(newNote);
                              }
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              setDialogState(() {
                                isSaving = false;
                                hasSaved = false;
                              });
                              if (context.mounted) {
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
      ),
    );
  }

  Future<bool> _ensureNotesPin(BuildContext context) async {
    final currentPin = await _storageService.getNotesPin();
    if (currentPin != null && currentPin.isNotEmpty) {
      return true;
    }

    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    if (!context.mounted) return false;

    final pinSetUpResult = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Set up Notes PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You need to set up a 4-digit PIN to lock your notes.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                hintText: 'Enter 4-digit PIN',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmPinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                hintText: 'Re-enter 4-digit PIN',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final p1 = newPinController.text;
              final p2 = confirmPinController.text;
              if (p1.length != 4) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(content: Text('PIN must be 4 digits.')),
                );
                return;
              }
              if (p1 != p2) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(content: Text('PINs do not match.')),
                );
                return;
              }
              await _storageService.setNotesPin(p1);
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx, true);
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
    return pinSetUpResult ?? false;
  }

  Future<bool> _showPinDialog() async {
    final pinController = TextEditingController();
    final correctPin = await _storageService.getNotesPin() ?? '0000';
    if (!mounted) return false;
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
              if (pinController.text == correctPin) {
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

  static const List<Color> _lightAestheticColors = [
    Color(0xFFFFE5E5), // Soft Pink
    Color(0xFFE5FFEB), // Mint
    Color(0xFFE5F6FF), // Soft Blue
    Color(0xFFFFF9E5), // Soft Yellow
    Color(0xFFF3E5FF), // Lavender
    Color(0xFFFFECE5), // Peach
    Color(0xFFE5FFF9), // Aqua
  ];

  static const List<Color> _darkAestheticColors = [
    Color(0xFF352222), // Soft Pink (Dark)
    Color(0xFF223525), // Mint (Dark)
    Color(0xFF222B35), // Soft Blue (Dark)
    Color(0xFF353022), // Soft Yellow (Dark)
    Color(0xFF2B2235), // Lavender (Dark)
    Color(0xFF352622), // Peach (Dark)
    Color(0xFF223530), // Aqua (Dark)
  ];

  Color _getNoteColor(BuildContext context, String id, String content) {
    int hash = id.hashCode + content.hashCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? _darkAestheticColors : _lightAestheticColors;
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _storageService.getIncomingRequestsStream('note'),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              final hasRequests = requests.isNotEmpty;
              return IconButton(
                icon: hasRequests
                    ? Badge(
                        backgroundColor: Colors.red,
                        label: Text(
                          requests.length.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        child: const Icon(Icons.people_outline),
                      )
                    : const Icon(Icons.people_outline),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    builder: (context) => CollaborationRequestsSheet(type: 'note'),
                  );
                },
                tooltip: 'Collaboration Requests',
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Note>>(
        stream: _storageService.getNotesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final notes = snapshot.data ?? [];
          final orderedNotes = _sortNotesWithCustomOrder(notes);
          
          if (orderedNotes.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 50),
              Center(child: Text('No notes yet. Tap + to add one.\nUpdates are synced in real-time.', textAlign: TextAlign.center))
            ]);
          }

          final currentUser = FirebaseAuth.instance.currentUser;

          return LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              int crossAxisCount = 2;
              if (width > 1200) {
                crossAxisCount = 5;
              } else if (width > 900) {
                crossAxisCount = 4;
              } else if (width > 600) {
                crossAxisCount = 3;
              }
              
              final double cardWidth = (width - (crossAxisCount - 1) * 10 - 24) / crossAxisCount;
              final double childAspectRatio = cardWidth / 180.0; // Keeping card height around 180px

              return GridView.builder(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 88),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: orderedNotes.length,
                itemBuilder: (context, index) {
                  final note = orderedNotes[index];
                  final Color noteColor = _getNoteColor(context, note.id ?? '', note.title + note.content);
                  final isShared = note.sharedWith.isNotEmpty || (note.ownerUid != null && note.ownerUid != currentUser?.uid);
                  final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
                  final titleColor = isDarkTheme ? Colors.white.withValues(alpha: 0.9) : Colors.black87;
                  final subtitleColor = isDarkTheme ? Colors.white.withValues(alpha: 0.7) : Colors.black54;
                  final hintIconColor = isDarkTheme ? Colors.white.withValues(alpha: 0.5) : Colors.black38;
                  
                  final card = _buildNoteCard(
                    note: note,
                    currentUser: currentUser,
                    noteColor: noteColor,
                    isShared: isShared,
                    titleColor: titleColor,
                    subtitleColor: subtitleColor,
                    hintIconColor: hintIconColor,
                  );

                  return DragTarget<int>(
                    onWillAcceptWithDetails: (details) => details.data != index,
                    onAcceptWithDetails: (details) {
                      final fromIndex = details.data;
                      setState(() {
                        final currentIds = orderedNotes.map((n) => n.id ?? '').toList();
                        final draggedId = currentIds.removeAt(fromIndex);
                        currentIds.insert(index, draggedId);
                        _customOrderIds = currentIds;
                        _saveCustomOrder(_customOrderIds);
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return LongPressDraggable<int>(
                        data: index,
                        feedback: SizedBox(
                          width: cardWidth,
                          height: 180.0,
                          child: Material(
                            color: Colors.transparent,
                            child: Transform.scale(
                              scale: 1.05,
                              child: card,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.4,
                          child: card,
                        ),
                        child: card,
                      );
                    },
                  );
                },
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

  Widget _buildNoteCard({
    required Note note,
    required User? currentUser,
    required Color noteColor,
    required bool isShared,
    required Color titleColor,
    required Color subtitleColor,
    required Color hintIconColor,
  }) {
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isShared)
                        Icon(Icons.people_outline, size: 16, color: subtitleColor),
                      if (note.isLocked) ...[
                        if (isShared) const SizedBox(width: 4),
                        Icon(Icons.lock, size: 14, color: subtitleColor),
                      ],
                    ],
                  ),
                ],
              ),
              if (note.title.isNotEmpty) const SizedBox(height: 8),
              Expanded(
                child: Text(
                  note.isLocked ? 'Locked Content' : note.content,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: subtitleColor, 
                    fontSize: 13,
                    fontStyle: note.isLocked ? FontStyle.italic : FontStyle.normal
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('MMM d').format(DateFormat('yyyy-MM-dd HH:mm').parse(note.date)),
                      style: TextStyle(fontSize: 10, color: hintIconColor, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (note.ownerUid == null || note.ownerUid == currentUser?.uid) ...[
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => CollaboratorSelectionDialog(
                                itemId: note.id!,
                                itemTitle: note.title.isNotEmpty ? note.title : 'Untitled Note',
                                type: 'note',
                              ),
                            );
                          },
                          child: Icon(Icons.person_add_alt_1_outlined, size: 18, color: hintIconColor),
                        ),
                        const SizedBox(width: 12),
                      ],
                      GestureDetector(
                        onTap: () async {
                          if (note.isLocked) {
                            bool auth = await _showPinDialog();
                            if (!auth) return;
                          }
                          if (!context.mounted) return;
                          final isOwn = note.ownerUid == null || note.ownerUid == currentUser?.uid;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(isOwn ? 'Delete Note' : 'Leave Shared Note'),
                              content: Text(isOwn ? 'Are you sure you want to delete this note?' : 'Are you sure you want to stop collaborating on this note?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true), 
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: Text(isOwn ? 'Delete' : 'Leave')
                                ),
                              ],
                            ),
                          );

                          if (confirm != true) return;
                          await _storageService.deleteNote(note.id!, ownerUid: note.ownerUid);
                        },
                        child: Icon(Icons.delete_outline, size: 18, color: hintIconColor),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
