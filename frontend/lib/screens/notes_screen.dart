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
  int? _draggedIndex;

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
    final starredNotes = notes.where((n) => n.isStarred).toList();
    final unstarredNotes = notes.where((n) => !n.isStarred).toList();

    if (_customOrderIds.isNotEmpty) {
      starredNotes.sort((a, b) {
        final aIndex = _customOrderIds.indexOf(a.id ?? '');
        final bIndex = _customOrderIds.indexOf(b.id ?? '');
        if (aIndex != -1 && bIndex != -1) {
          return aIndex.compareTo(bIndex);
        }
        if (aIndex != -1) return 1;
        if (bIndex != -1) return -1;
        return b.date.compareTo(a.date);
      });

      unstarredNotes.sort((a, b) {
        final aIndex = _customOrderIds.indexOf(a.id ?? '');
        final bIndex = _customOrderIds.indexOf(b.id ?? '');
        if (aIndex != -1 && bIndex != -1) {
          return aIndex.compareTo(bIndex);
        }
        if (aIndex != -1) return 1;
        if (bIndex != -1) return -1;
        return b.date.compareTo(a.date);
      });
    } else {
      starredNotes.sort((a, b) => b.date.compareTo(a.date));
      unstarredNotes.sort((a, b) => b.date.compareTo(a.date));
    }

    return [...starredNotes, ...unstarredNotes];
  }

  Future<void> _addOrEditNote({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    bool isLocked = note?.isLocked ?? false;
    bool isChecklist = note?.isChecklist ?? false;
    List<Map<String, dynamic>> checklistItems = List<Map<String, dynamic>>.from(note?.checklistItems ?? []);
    final List<TextEditingController> itemControllers = checklistItems.map((item) => TextEditingController(text: item['text'] as String)).toList();
    final List<FocusNode> itemFocusNodes = checklistItems.map((_) => FocusNode()).toList();

    void reorderChecklist(void Function(void Function()) setDialogState) {
      setDialogState(() {
        List<Map<String, dynamic>> combined = [];
        for (int i = 0; i < checklistItems.length; i++) {
          combined.add({
            'item': checklistItems[i],
            'controller': itemControllers[i],
            'focusNode': itemFocusNodes[i],
          });
        }

        // Sort: unchecked first, checked last
        combined.sort((a, b) {
          bool aChecked = a['item']['isChecked'] == true;
          bool bChecked = b['item']['isChecked'] == true;
          if (aChecked && !bChecked) return 1;
          if (!aChecked && bChecked) return -1;
          return 0;
        });

        checklistItems.clear();
        itemControllers.clear();
        itemFocusNodes.clear();
        for (var pair in combined) {
          checklistItems.add(pair['item'] as Map<String, dynamic>);
          itemControllers.add(pair['controller'] as TextEditingController);
          itemFocusNodes.add(pair['focusNode'] as FocusNode);
        }
      });
    }

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
                if (isChecklist) {
                  for (int i = 0; i < checklistItems.length; i++) {
                    checklistItems[i]['text'] = itemControllers[i].text;
                  }
                }

                final currentUser = FirebaseAuth.instance.currentUser;
                final isShared = note != null && (
                  note.sharedWith.isNotEmpty || 
                  (note.ownerUid != null && note.ownerUid != currentUser?.uid)
                );

                if (isShared) {
                  final currentUsername = currentUser?.displayName ?? currentUser?.email?.split('@').first ?? 'User';
                  if (isChecklist) {
                    checklistItems = _processChecklistWithSignatures(checklistItems, note.checklistItems, currentUsername);
                  } else {
                    contentController.text = _processContentWithSignatures(contentController.text, note.content, currentUsername);
                  }
                }

                if (isChecklist) {
                  contentController.text = checklistItems.map((item) => (item['isChecked'] == true ? '[x] ' : '[ ] ') + (item['text'] as String)).join('\n');
                }
                final content = contentController.text;
                if (note == null) {
                  if (title.isNotEmpty || (isChecklist ? checklistItems.isNotEmpty : content.isNotEmpty)) {
                    hasSaved = true;
                    final newNote = Note(
                      title: title,
                      content: content,
                      date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      isLocked: isLocked,
                      sharedWith: [],
                      isChecklist: isChecklist,
                      checklistItems: checklistItems,
                    );
                    try {
                      await _storageService.insertNote(newNote);
                    } catch (e) {
                      debugPrint("Error auto-saving new note: $e");
                    }
                  }
                } else {
                  bool isChanged = title != note.title || isLocked != note.isLocked || isChecklist != note.isChecklist;
                  if (!isChanged) {
                    if (isChecklist) {
                      if (checklistItems.length != note.checklistItems.length) {
                        isChanged = true;
                      } else {
                        for (int i = 0; i < checklistItems.length; i++) {
                          if (checklistItems[i]['text'] != note.checklistItems[i]['text'] ||
                              checklistItems[i]['isChecked'] != note.checklistItems[i]['isChecked']) {
                            isChanged = true;
                            break;
                          }
                        }
                      }
                    } else {
                      isChanged = content != note.content;
                    }
                  }
                  if (isChanged) {
                    hasSaved = true;
                    final updatedNote = Note(
                      id: note.id,
                      title: title,
                      content: content,
                      date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      isLocked: isLocked,
                      ownerUid: note.ownerUid,
                      sharedWith: note.sharedWith,
                      isChecklist: isChecklist,
                      checklistItems: checklistItems,
                      isStarred: note.isStarred,
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
                    icon: Icon(isChecklist ? Icons.notes : Icons.playlist_add_check),
                    onPressed: () {
                      setDialogState(() {
                        if (isChecklist) {
                          // Switching to normal Note
                          for (int i = 0; i < checklistItems.length; i++) {
                            checklistItems[i]['text'] = itemControllers[i].text;
                          }
                          contentController.text = checklistItems
                              .map((item) => item['text'] as String)
                              .where((text) => text.trim().isNotEmpty)
                              .join('\n');
                          isChecklist = false;
                        } else {
                          // Switching to Checklist
                          final text = contentController.text;
                          checklistItems = text
                              .split('\n')
                              .map((line) {
                                String cleaned = line;
                                bool isChecked = false;
                                if (line.startsWith('[x] ')) {
                                  cleaned = line.substring(4);
                                  isChecked = true;
                                } else if (line.startsWith('[ ] ')) {
                                  cleaned = line.substring(4);
                                }
                                return {'text': cleaned, 'isChecked': isChecked};
                              })
                              .where((item) => (item['text'] as String).trim().isNotEmpty)
                              .toList();
                          if (checklistItems.isEmpty) {
                            checklistItems = [{'text': '', 'isChecked': false}];
                          }
                          itemControllers.clear();
                          itemFocusNodes.forEach((node) => node.dispose());
                          itemFocusNodes.clear();
                          for (var item in checklistItems) {
                            itemControllers.add(TextEditingController(text: item['text'] as String));
                            itemFocusNodes.add(FocusNode());
                          }
                          isChecklist = true;
                        }
                      });
                    },
                    tooltip: isChecklist ? 'Convert to Note' : 'Convert to Checklist',
                  ),
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
                          final title = titleController.text;
                          if (isChecklist) {
                            for (int i = 0; i < checklistItems.length; i++) {
                              checklistItems[i]['text'] = itemControllers[i].text;
                            }
                          }

                          final currentUser = FirebaseAuth.instance.currentUser;
                          final isShared = note != null && (
                            note.sharedWith.isNotEmpty || 
                            (note.ownerUid != null && note.ownerUid != currentUser?.uid)
                          );

                          if (isShared) {
                            final currentUsername = currentUser?.displayName ?? currentUser?.email?.split('@').first ?? 'User';
                            if (isChecklist) {
                              checklistItems = _processChecklistWithSignatures(checklistItems, note.checklistItems, currentUsername);
                            } else {
                              contentController.text = _processContentWithSignatures(contentController.text, note.content, currentUsername);
                            }
                          }

                          if (isChecklist) {
                            contentController.text = checklistItems.map((item) => (item['isChecked'] == true ? '[x] ' : '[ ] ') + (item['text'] as String)).join('\n');
                          }
                          final content = contentController.text;
                          if (title.isNotEmpty || (isChecklist ? checklistItems.isNotEmpty : content.isNotEmpty)) {
                            setDialogState(() {
                              isSaving = true;
                              hasSaved = true;
                            });
                            final newNote = Note(
                              id: note?.id,
                              title: title,
                              content: content,
                              date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                              isLocked: isLocked,
                              ownerUid: note?.ownerUid,
                              sharedWith: note?.sharedWith ?? [],
                              isChecklist: isChecklist,
                              checklistItems: checklistItems,
                              isStarred: note?.isStarred ?? false,
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
                      child: isChecklist
                          ? Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: checklistItems.length,
                                    itemBuilder: (context, index) {
                                      final item = checklistItems[index];
                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Checkbox(
                                            value: item['isChecked'] == true,
                                            onChanged: (val) {
                                              setDialogState(() {
                                                item['isChecked'] = val ?? false;
                                              });
                                              reorderChecklist(setDialogState);
                                            },
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              child: TextField(
                                                controller: itemControllers[index],
                                                focusNode: itemFocusNodes[index],
                                                style: TextStyle(
                                                  decoration: item['isChecked'] == true
                                                      ? TextDecoration.lineThrough
                                                      : null,
                                                  color: item['isChecked'] == true
                                                      ? Colors.grey
                                                      : null,
                                                ),
                                                decoration: const InputDecoration(
                                                  hintText: 'Add item...',
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(vertical: 4.0),
                                                ),
                                                textCapitalization: TextCapitalization.sentences,
                                                maxLines: null,
                                                keyboardType: TextInputType.multiline,
                                                onChanged: (val) {
                                                  item['text'] = val;
                                                },
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.grey),
                                            onPressed: () {
                                              setDialogState(() {
                                                checklistItems.removeAt(index);
                                                itemControllers[index].dispose();
                                                itemControllers.removeAt(index);
                                                itemFocusNodes[index].dispose();
                                                itemFocusNodes.removeAt(index);
                                              });
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Item'),
                                    onPressed: () {
                                      setDialogState(() {
                                        checklistItems.add({'text': '', 'isChecked': false});
                                        itemControllers.add(TextEditingController(text: ''));
                                        final newFocusNode = FocusNode();
                                        itemFocusNodes.add(newFocusNode);
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          newFocusNode.requestFocus();
                                        });
                                      });
                                    },
                                  ),
                                ),
                              ],
                            )
                          : TextField(
                              controller: contentController,
                              decoration: const InputDecoration(
                                hintText: 'Start typing your note...',
                                border: InputBorder.none,
                              ),
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
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

    // Dispose resources on dialog close
    for (var controller in itemControllers) {
      controller.dispose();
    }
    for (var node in itemFocusNodes) {
      node.dispose();
    }
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
                  
                  final isDragging = _draggedIndex == index;
                  final cardContent = _buildNoteCard(
                    note: note,
                    currentUser: currentUser,
                    noteColor: noteColor,
                    isShared: isShared,
                    titleColor: titleColor,
                    subtitleColor: subtitleColor,
                    hintIconColor: hintIconColor,
                    dragHandle: Icon(Icons.drag_indicator, size: 18, color: hintIconColor),
                  );

                  Widget draggableWidget = LongPressDraggable<int>(
                    data: index,
                    feedback: SizedBox(
                      width: cardWidth,
                      height: 180.0,
                      child: Material(
                        color: Colors.transparent,
                        child: Transform.scale(
                          scale: 1.05,
                          child: _buildNoteCard(
                            note: note,
                            currentUser: currentUser,
                            noteColor: noteColor,
                            isShared: isShared,
                            titleColor: titleColor,
                            subtitleColor: subtitleColor,
                            hintIconColor: hintIconColor,
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.2,
                      child: cardContent,
                    ),
                    onDragStarted: () {
                      setState(() {
                        _draggedIndex = index;
                      });
                    },
                    onDraggableCanceled: (_, __) {
                      setState(() {
                        _draggedIndex = null;
                      });
                    },
                    onDragCompleted: () {
                      setState(() {
                        _draggedIndex = null;
                      });
                    },
                    child: Opacity(
                      opacity: isDragging ? 0.4 : 1.0,
                      child: cardContent,
                    ),
                  );

                  return DragTarget<int>(
                    onWillAcceptWithDetails: (details) {
                      final fromIndex = details.data;
                      if (fromIndex == index) return false;
                      final fromNote = orderedNotes[fromIndex];
                      final toNote = orderedNotes[index];
                      return fromNote.isStarred == toNote.isStarred;
                    },
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
                      return draggableWidget;
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
    Widget? dragHandle,
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
                child: note.isLocked
                    ? Text(
                        'Locked Content',
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : note.isChecklist
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: note.checklistItems.take(3).map<Widget>((item) {
                              final checked = item['isChecked'] == true;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      checked ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                                      size: 14,
                                      color: subtitleColor.withOpacity(0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        item['text'] ?? '',
                                        style: TextStyle(
                                          color: subtitleColor,
                                          fontSize: 12,
                                          decoration: checked ? TextDecoration.lineThrough : null,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          )
                        : Text(
                            note.content,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 13,
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
                      if (dragHandle != null) ...[
                        dragHandle,
                        const SizedBox(width: 12),
                      ],
                      GestureDetector(
                        onTap: () async {
                          final updatedNote = Note(
                            id: note.id,
                            title: note.title,
                            content: note.content,
                            date: note.date,
                            isLocked: note.isLocked,
                            ownerUid: note.ownerUid,
                            sharedWith: note.sharedWith,
                            isChecklist: note.isChecklist,
                            checklistItems: note.checklistItems,
                            isStarred: !note.isStarred,
                          );
                          await _storageService.updateNote(updatedNote);
                        },
                        child: Icon(
                          note.isStarred ? Icons.star : Icons.star_border,
                          size: 18,
                          color: note.isStarred ? Colors.amber : hintIconColor,
                        ),
                      ),
                      const SizedBox(width: 12),
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

  String _processContentWithSignatures(String newContent, String? originalContent, String currentUsername) {
    if (originalContent == null || originalContent.isEmpty) {
      return newContent.split('\n').map((line) {
        if (line.trim().isEmpty) return line;
        final cleaned = line.replaceAll(RegExp(r'\s*\(by\s+[^\)]+\)$'), '');
        return '$cleaned (by $currentUsername)';
      }).join('\n');
    }

    final originalLines = originalContent.split('\n').toSet();
    return newContent.split('\n').map((line) {
      if (line.trim().isEmpty) return line;
      if (originalLines.contains(line)) {
        return line;
      }
      final cleaned = line.replaceAll(RegExp(r'\s*\(by\s+[^\)]+\)$'), '');
      return '$cleaned (by $currentUsername)';
    }).join('\n');
  }

  List<Map<String, dynamic>> _processChecklistWithSignatures(
      List<Map<String, dynamic>> newItems,
      List<Map<String, dynamic>>? originalItems,
      String currentUsername) {
    
    if (originalItems == null || originalItems.isEmpty) {
      return newItems.map((item) {
        final text = item['text'] as String;
        if (text.trim().isEmpty) return item;
        final cleaned = text.replaceAll(RegExp(r'\s*\(by\s+[^\)]+\)$'), '');
        return {
          ...item,
          'text': '$cleaned (by $currentUsername)',
        };
      }).toList();
    }

    final originalTexts = originalItems.map((item) => item['text'] as String).toSet();
    return newItems.map((item) {
      final text = item['text'] as String;
      if (text.trim().isEmpty) return item;
      if (originalTexts.contains(text)) {
        return item;
      }
      final cleaned = text.replaceAll(RegExp(r'\s*\(by\s+[^\)]+\)$'), '');
      return {
        ...item,
        'text': '$cleaned (by $currentUsername)',
      };
    }).toList();
  }
}
