import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/note.dart';
import '../services/storage_service.dart';
import '../widgets/collaboration_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final StorageService _storageService = StorageService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final Stream<List<Note>> _notesStream;
  List<String> _customOrderIds = [];
  String? _draggedNoteId;
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'pinned', 'checklists', 'private', 'shared'

  final List<Map<String, dynamic>> _filterTabs = [
    {'id': 'all', 'label': 'All', 'icon': Icons.grid_view_rounded},
    {'id': 'pinned', 'label': 'Pinned', 'icon': Icons.push_pin_rounded},
    {'id': 'checklists', 'label': 'Checklists', 'icon': Icons.checklist_rounded},
    {'id': 'private', 'label': 'Private', 'icon': Icons.lock_outline_rounded},
    {'id': 'shared', 'label': 'Shared', 'icon': Icons.people_outline_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _notesStream = _storageService.getNotesStream();
    _loadCustomOrder();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  List<Note> _filterNotes(List<Note> notes, User? currentUser) {
    return notes.where((note) {
      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final titleMatch = note.title.toLowerCase().contains(q);
        final contentMatch = note.content.toLowerCase().contains(q);
        final checklistMatch = note.checklistItems.any(
          (item) => (item['text'] as String? ?? '').toLowerCase().contains(q),
        );
        if (!titleMatch && !contentMatch && !checklistMatch) return false;
      }

      final isShared = note.sharedWith.isNotEmpty ||
          (note.ownerUid != null && note.ownerUid != currentUser?.uid);

      switch (_selectedFilter) {
        case 'pinned':
          return note.isStarred;
        case 'checklists':
          return note.isChecklist;
        case 'private':
          return !isShared;
        case 'shared':
          return isShared;
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  int _getFilterCount(List<Note> notes, String filterId, User? currentUser) {
    switch (filterId) {
      case 'pinned':
        return notes.where((n) => n.isStarred).length;
      case 'checklists':
        return notes.where((n) => n.isChecklist).length;
      case 'private':
        return notes.where((n) =>
          n.sharedWith.isEmpty && (n.ownerUid == null || n.ownerUid == currentUser?.uid)
        ).length;
      case 'shared':
        return notes.where((n) =>
          n.sharedWith.isNotEmpty || (n.ownerUid != null && n.ownerUid != currentUser?.uid)
        ).length;
      case 'all':
      default:
        return notes.length;
    }
  }

  Future<void> _addOrEditNote({Note? note, bool startAsChecklist = false}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final String rawContent = note?.content ?? '';
    final String editableContent = rawContent.isNotEmpty
        ? rawContent.split('\n').map((line) => _stripSignature(line)).join('\n')
        : '';
    final contentController = LinkTextEditingController(text: editableContent);
    bool isLocked = note?.isLocked ?? false;
    bool isChecklist = note?.isChecklist ?? (note == null && startAsChecklist);
    List<Map<String, dynamic>> checklistItems = note != null
        ? List<Map<String, dynamic>>.from(
            note.checklistItems.map((item) {
              final String text = item['text'] as String? ?? '';
              return {
                ...item,
                'text': _stripSignature(text),
              };
            }),
          )
        : (startAsChecklist ? [{'text': '', 'isChecked': false}] : []);

    final List<TextEditingController> itemControllers = checklistItems
        .map((item) => LinkTextEditingController(text: item['text'] as String))
        .toList();
    final List<FocusNode> itemFocusNodes = checklistItems.map((_) => FocusNode()).toList();

    void toggleItemChecked(int index, bool isChecked, void Function(void Function()) setDialogState) {
      setDialogState(() {
        if (index < 0 || index >= checklistItems.length) return;

        final item = checklistItems[index];
        final controller = itemControllers[index];
        final focusNode = itemFocusNodes[index];

        item['isChecked'] = isChecked;

        // Remove from current position
        checklistItems.removeAt(index);
        itemControllers.removeAt(index);
        itemFocusNodes.removeAt(index);

        if (isChecked) {
          // Place at top of checked items section
          int firstCheckedIndex = checklistItems.indexWhere((it) => it['isChecked'] == true);
          if (firstCheckedIndex == -1) {
            checklistItems.add(item);
            itemControllers.add(controller);
            itemFocusNodes.add(focusNode);
          } else {
            checklistItems.insert(firstCheckedIndex, item);
            itemControllers.insert(firstCheckedIndex, controller);
            itemFocusNodes.insert(firstCheckedIndex, focusNode);
          }
        } else {
          // Place at bottom of unchecked items section
          int firstCheckedIndex = checklistItems.indexWhere((it) => it['isChecked'] == true);
          if (firstCheckedIndex == -1) {
            checklistItems.add(item);
            itemControllers.add(controller);
            itemFocusNodes.add(focusNode);
          } else {
            checklistItems.insert(firstCheckedIndex, item);
            itemControllers.insert(firstCheckedIndex, controller);
            itemFocusNodes.insert(firstCheckedIndex, focusNode);
          }
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
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (bool didPop, Object? result) async {
                if (didPop && !hasSaved) {
                  final title = titleController.text;
                  if (isChecklist) {
                    final List<Map<String, dynamic>> filteredItems = [];
                    for (int i = 0; i < checklistItems.length; i++) {
                      final text = itemControllers[i].text;
                      if (text.isNotEmpty) {
                        checklistItems[i]['text'] = text;
                        filteredItems.add(checklistItems[i]);
                      }
                    }
                    checklistItems = filteredItems;
                  }

                  final currentUser = FirebaseAuth.instance.currentUser;
                  final isShared = note != null && (
                    note.sharedWith.isNotEmpty || 
                    (note.ownerUid != null && note.ownerUid != currentUser?.uid)
                  );

                  if (isShared) {
                    final currentUsername = currentUser?.displayName ?? currentUser?.email?.split('@').first ?? 'User';
                    if (isChecklist) {
                      checklistItems = _processChecklistWithSignatures(checklistItems, note.checklistItems, currentUsername, ownerUsername: note.ownerUsername);
                    } else {
                      contentController.text = _processContentWithSignatures(contentController.text, note.content, currentUsername, ownerUsername: note.ownerUsername);
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
                backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                appBar: AppBar(
                  backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(
                    note == null
                        ? (isChecklist ? 'New Checklist' : 'New Note')
                        : (isChecklist ? 'Edit Checklist' : 'Edit Note'),
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(isChecklist ? Icons.notes_rounded : Icons.playlist_add_check_rounded),
                      tooltip: isChecklist ? 'Convert to Note' : 'Convert to Checklist',
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
                            for (var node in itemFocusNodes) {
                              node.dispose();
                            }
                            itemFocusNodes.clear();
                            for (var item in checklistItems) {
                              itemControllers.add(LinkTextEditingController(text: item['text'] as String));
                              itemFocusNodes.add(FocusNode());
                            }
                            isChecklist = true;
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: isLocked ? const Color(0xFFF43F5E) : const Color(0xFF10B981),
                      ),
                      tooltip: isLocked ? 'Unlock Note' : 'Lock Note',
                      onPressed: () async {
                        if (!isLocked) {
                          bool hasPin = await _ensureNotesPin(context);
                          if (!hasPin) return;
                        }
                        setDialogState(() {
                          isLocked = !isLocked;
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: isSaving
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            )
                          : FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(
                                'Save',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () async {
                                final title = titleController.text;
                                if (isChecklist) {
                                  final List<Map<String, dynamic>> filteredItems = [];
                                  for (int i = 0; i < checklistItems.length; i++) {
                                    final text = itemControllers[i].text;
                                    if (text.isNotEmpty) {
                                      checklistItems[i]['text'] = text;
                                      filteredItems.add(checklistItems[i]);
                                    }
                                  }
                                  checklistItems = filteredItems;
                                }

                                final currentUser = FirebaseAuth.instance.currentUser;
                                final isShared = note != null && (
                                  note.sharedWith.isNotEmpty || 
                                  (note.ownerUid != null && note.ownerUid != currentUser?.uid)
                                );

                                if (isShared) {
                                  final currentUsername = currentUser?.displayName ?? currentUser?.email?.split('@').first ?? 'User';
                                  if (isChecklist) {
                                    checklistItems = _processChecklistWithSignatures(checklistItems, note.checklistItems, currentUsername, ownerUsername: note.ownerUsername);
                                  } else {
                                    contentController.text = _processContentWithSignatures(contentController.text, note.content, currentUsername, ownerUsername: note.ownerUsername);
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
                            ),
                    ),
                  ],
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          hintText: 'Title...',
                          border: InputBorder.none,
                          hintStyle: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                        style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold),
                        autofocus: note == null,
                      ),
                      Divider(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                        height: 20,
                      ),
                      Expanded(
                        child: isChecklist
                            ? Column(
                                children: [
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: checklistItems.length,
                                      itemBuilder: (context, index) {
                                        final item = checklistItems[index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Checkbox(
                                                value: item['isChecked'] == true,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                                activeColor: const Color(0xFF6366F1),
                                                onChanged: (val) {
                                                  toggleItemChecked(index, val ?? false, setDialogState);
                                                },
                                              ),
                                              Expanded(
                                                child: Focus(
                                                  onKeyEvent: (node, event) {
                                                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                                                      final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                                                      if (!isShiftPressed) {
                                                        setDialogState(() {
                                                          checklistItems.insert(index + 1, {'text': '', 'isChecked': false});
                                                          itemControllers.insert(index + 1, LinkTextEditingController(text: ''));
                                                          final newFocusNode = FocusNode();
                                                          itemFocusNodes.insert(index + 1, newFocusNode);
                                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                                            newFocusNode.requestFocus();
                                                          });
                                                        });
                                                        return KeyEventResult.handled;
                                                      }
                                                    }
                                                    return KeyEventResult.ignored;
                                                  },
                                                  child: TextField(
                                                    controller: itemControllers[index],
                                                    focusNode: itemFocusNodes[index],
                                                    style: GoogleFonts.outfit(
                                                      decoration: item['isChecked'] == true
                                                          ? TextDecoration.lineThrough
                                                          : null,
                                                      color: item['isChecked'] == true
                                                          ? (isDark ? Colors.white38 : Colors.black38)
                                                          : null,
                                                      fontSize: 15,
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText: 'Add checklist item...',
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding: const EdgeInsets.symmetric(vertical: 6.0),
                                                      hintStyle: GoogleFonts.outfit(
                                                        color: isDark ? Colors.white30 : Colors.black38,
                                                      ),
                                                    ),
                                                    textCapitalization: TextCapitalization.sentences,
                                                    maxLines: null,
                                                    keyboardType: TextInputType.multiline,
                                                    onChanged: (val) {
                                                      item['text'] = val;
                                                      setDialogState(() {});
                                                    },
                                                  ),
                                                ),
                                              ),
                                              if (note != null && index < note.checklistItems.length) ...[
                                                Builder(
                                                  builder: (ctx) {
                                                    final origText = note.checklistItems[index]['text'] as String? ?? '';
                                                    final origUser = _extractUsername(origText);
                                                    if (origUser != null && origUser.isNotEmpty) {
                                                      final isDarkCtx = Theme.of(ctx).brightness == Brightness.dark;
                                                      final color = _getSignatureColor(origUser, isDarkCtx);
                                                      return Padding(
                                                        padding: const EdgeInsets.only(right: 6.0),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: color.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            origUser,
                                                            style: GoogleFonts.outfit(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                              color: color,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    return const SizedBox.shrink();
                                                  },
                                                ),
                                              ],
                                              IconButton(
                                                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
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
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFF6366F1),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      icon: const Icon(Icons.add_rounded, size: 20),
                                      label: Text(
                                        'Add Item',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          checklistItems.insert(0, {'text': '', 'isChecked': false});
                                          itemControllers.insert(0, LinkTextEditingController(text: ''));
                                          final newFocusNode = FocusNode();
                                          itemFocusNodes.insert(0, newFocusNode);
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
                                decoration: InputDecoration(
                                  hintText: 'Start typing your note...',
                                  border: InputBorder.none,
                                  hintStyle: GoogleFonts.outfit(
                                    fontSize: 15,
                                    color: isDark ? Colors.white30 : Colors.black38,
                                  ),
                                ),
                                style: GoogleFonts.outfit(fontSize: 15, height: 1.5),
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                keyboardType: TextInputType.multiline,
                                textCapitalization: TextCapitalization.sentences,
                                onChanged: (val) => setDialogState(() {}),
                              ),
                      ),
                      Builder(
                        builder: (context) {
                          final detectedLinks = _extractAllLinks(
                            titleController.text,
                            isChecklist ? '' : contentController.text,
                            isChecklist,
                            isChecklist ? checklistItems.map((item) => {'text': item['text']}).toList() : [],
                          );
                          if (detectedLinks.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.link_rounded, size: 16, color: Color(0xFF6366F1)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Links in Note (${detectedLinks.length}):',
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: detectedLinks.map((url) => ActionChip(
                                      avatar: const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF6366F1)),
                                      label: Text(
                                        url.length > 28 ? '${url.substring(0, 25)}...' : url,
                                        style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF6366F1), fontWeight: FontWeight.w600),
                                      ),
                                      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                      side: BorderSide(
                                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                                      ),
                                      onPressed: () => _openExternalUrl(url),
                                    )).toList(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set up Notes PIN', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You need to set up a 4-digit PIN to lock your notes.',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey),
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
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
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
            child: Text('Save PIN', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter PIN', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter 4-digit PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (pinController.text == correctPin) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
              }
            },
            child: Text('Unlock', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  Color _getCardAccent(Note note) {
    final List<Color> accents = [
      const Color(0xFF38BDF8), // Cyan / Sky Blue
      const Color(0xFF818CF8), // Indigo
      const Color(0xFF34D399), // Emerald
      const Color(0xFFFBBF24), // Amber
      const Color(0xFFA78BFA), // Purple
      const Color(0xFFF472B6), // Pink
      const Color(0xFF2DD4BF), // Teal
      const Color(0xFFFB923C), // Coral
    ];
    final hash = (note.id ?? note.title).hashCode.abs();
    return accents[hash % accents.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B101E) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B101E) : Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes & Checklist',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              'Capture thoughts, checklists & team notes',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _storageService.getIncomingRequestsStream('note'),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              final hasRequests = requests.isNotEmpty;
              return Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: hasRequests
                      ? Badge(
                          backgroundColor: const Color(0xFFEF4444),
                          label: Text(
                            requests.length.toString(),
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          child: Icon(Icons.people_alt_rounded, color: isDark ? Colors.white70 : Colors.black87),
                        )
                      : Icon(Icons.people_alt_rounded, color: isDark ? Colors.white70 : Colors.black87),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      builder: (context) => CollaborationRequestsSheet(type: 'note'),
                    );
                  },
                  tooltip: 'Collaboration Requests',
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Note>>(
        stream: _notesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allNotes = snapshot.data ?? [];
          final orderedNotes = _sortNotesWithCustomOrder(allNotes);
          final displayedNotes = _filterNotes(orderedNotes, currentUser);

          return Column(
            children: [
              // Search Box
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151D2A) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF6366F1).withValues(alpha: 0.45) : const Color(0xFF6366F1).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.12 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  key: const ValueKey('notes_search_input'),
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search notes, checklists, links...',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF6366F1),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),

              // Filter Category Chips
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filterTabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = _filterTabs[index];
                    final isSelected = _selectedFilter == tab['id'];
                    final count = _getFilterCount(allNotes, tab['id'] as String, currentUser);
                    return ChoiceChip(
                      avatar: Icon(
                        tab['icon'] as IconData,
                        size: 15,
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                      ),
                      label: Text(
                        '${tab['label']} ($count)',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF6366F1),
                      backgroundColor: isDark ? const Color(0xFF151D2A) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                        ),
                      ),
                      showCheckmark: false,
                      onSelected: (val) {
                        if (val) setState(() => _selectedFilter = tab['id'] as String);
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Notes Grid or Empty State
              Expanded(
                child: displayedNotes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit_note_rounded,
                                  size: 38,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No matching notes found'
                                    : 'No notes yet in this category',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try searching with different keywords.'
                                    : 'Tap below to create a quick note or checklist.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
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

                          final double cardWidth = (width - (crossAxisCount - 1) * 12 - 28) / crossAxisCount;
                          final double childAspectRatio = cardWidth / 195.0;

                          return GridView.builder(
                            padding: const EdgeInsets.only(left: 14, right: 14, top: 6, bottom: 96),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: childAspectRatio,
                            ),
                            itemCount: displayedNotes.length,
                            itemBuilder: (context, index) {
                              final note = displayedNotes[index];
                              final isShared = note.sharedWith.isNotEmpty ||
                                  (note.ownerUid != null && note.ownerUid != currentUser?.uid);
                              final accentColor = _getCardAccent(note);
                              final isDragging = _draggedNoteId == note.id;

                              final cardContent = _buildNoteCard(
                                note: note,
                                currentUser: currentUser,
                                accentColor: accentColor,
                                isShared: isShared,
                                isDark: isDark,
                                dragHandle: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 18,
                                  color: isDark ? Colors.white30 : Colors.black26,
                                ),
                              );

                              // Drag & Drop reordering support
                              return DragTarget<String>(
                                onWillAcceptWithDetails: (details) {
                                  final draggedId = details.data;
                                  if (draggedId == note.id) return false;
                                  return true;
                                },
                                onAcceptWithDetails: (details) {
                                  final draggedId = details.data;
                                  if (draggedId.isEmpty || draggedId == note.id) return;
                                  setState(() {
                                    final currentIds = orderedNotes.map((n) => n.id ?? '').toList();
                                    currentIds.remove(draggedId);
                                    final targetIndex = currentIds.indexOf(note.id ?? '');
                                    if (targetIndex != -1) {
                                      currentIds.insert(targetIndex, draggedId);
                                    } else {
                                      currentIds.add(draggedId);
                                    }
                                    _customOrderIds = currentIds;
                                    _saveCustomOrder(_customOrderIds);
                                  });
                                },
                                builder: (context, candidateData, rejectedData) {
                                  return LongPressDraggable<String>(
                                    data: note.id ?? '',
                                    feedback: SizedBox(
                                      width: cardWidth,
                                      height: 195.0,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Transform.scale(
                                          scale: 1.05,
                                          child: _buildNoteCard(
                                            note: note,
                                            currentUser: currentUser,
                                            accentColor: accentColor,
                                            isShared: isShared,
                                            isDark: isDark,
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.25,
                                      child: cardContent,
                                    ),
                                    onDragStarted: () {
                                      setState(() => _draggedNoteId = note.id);
                                    },
                                    onDraggableCanceled: (_, __) {
                                      setState(() => _draggedNoteId = null);
                                    },
                                    onDragCompleted: () {
                                      setState(() => _draggedNoteId = null);
                                    },
                                    child: Opacity(
                                      opacity: isDragging ? 0.35 : 1.0,
                                      child: cardContent,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab_checklist',
            onPressed: () => _addOrEditNote(startAsChecklist: true),
            icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
            label: Text('Checklist', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            foregroundColor: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
            elevation: 3,
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'fab_note',
            onPressed: () => _addOrEditNote(startAsChecklist: false),
            icon: const Icon(Icons.edit_note_rounded, size: 22),
            label: Text('Note', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            elevation: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard({
    required Note note,
    required User? currentUser,
    required Color accentColor,
    required bool isShared,
    required bool isDark,
    Widget? dragHandle,
  }) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.65);
    final hintIconColor = isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151D2A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: note.isStarred
              ? const Color(0xFFFBBF24).withValues(alpha: 0.6)
              : accentColor.withValues(alpha: isDark ? 0.22 : 0.3),
          width: note.isStarred ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: note.isStarred
                ? const Color(0xFFFBBF24).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _addOrEditNote(note: note),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header: Badges & Status Indicators
                Row(
                  children: [
                    // Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: note.isStarred
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
                            : (note.isChecklist
                                ? const Color(0xFF2DD4BF).withValues(alpha: 0.15)
                                : (isShared
                                    ? const Color(0xFFA78BFA).withValues(alpha: 0.15)
                                    : accentColor.withValues(alpha: 0.15))),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            note.isStarred
                                ? Icons.push_pin_rounded
                                : (note.isChecklist
                                    ? Icons.checklist_rounded
                                    : (isShared ? Icons.people_outline_rounded : Icons.notes_rounded)),
                            size: 11,
                            color: note.isStarred
                                ? const Color(0xFFFBBF24)
                                : (note.isChecklist
                                    ? const Color(0xFF2DD4BF)
                                    : (isShared ? const Color(0xFFA78BFA) : accentColor)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            note.isStarred
                                ? 'Pinned'
                                : (note.isChecklist
                                    ? 'Checklist'
                                    : (isShared ? 'Shared' : 'Note')),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: note.isStarred
                                  ? const Color(0xFFFBBF24)
                                  : (note.isChecklist
                                      ? const Color(0xFF2DD4BF)
                                      : (isShared ? const Color(0xFFA78BFA) : accentColor)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (isShared) ...[
                      const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFFA78BFA)),
                      const SizedBox(width: 4),
                    ],
                    if (note.isLocked)
                      const Icon(Icons.lock_rounded, size: 13, color: Color(0xFFF43F5E)),
                  ],
                ),

                const SizedBox(height: 8),

                // Note Title
                if (note.title.isNotEmpty)
                  Text(
                    note.title,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                if (note.title.isNotEmpty) const SizedBox(height: 6),

                // Card Body Content
                Expanded(
                  child: note.isLocked
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 22,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'PIN Protected',
                                style: GoogleFonts.outfit(
                                  color: subtitleColor,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        )
                      : note.isChecklist
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: note.checklistItems.take(3).map<Widget>((item) {
                                final checked = item['isChecked'] == true;
                                final String itemText = item['text'] ?? '';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 3.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        checked
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked_rounded,
                                        size: 13,
                                        color: checked
                                            ? const Color(0xFF10B981)
                                            : (isDark ? Colors.white38 : Colors.black38),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildFormattedTextWithSignature(
                                          text: itemText,
                                          baseStyle: GoogleFonts.outfit(
                                            color: checked
                                                ? (isDark ? Colors.white30 : Colors.black38)
                                                : subtitleColor,
                                            fontSize: 12,
                                            decoration: checked ? TextDecoration.lineThrough : null,
                                          ),
                                          isDarkTheme: isDark,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: note.content
                                  .split('\n')
                                  .take(3)
                                  .map((line) => Padding(
                                        padding: const EdgeInsets.only(bottom: 2.0),
                                        child: _buildFormattedTextWithSignature(
                                          text: line,
                                          baseStyle: GoogleFonts.outfit(
                                            color: subtitleColor,
                                            fontSize: 12.5,
                                            height: 1.3,
                                          ),
                                          isDarkTheme: isDark,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                            ),
                ),

                const SizedBox(height: 6),

                // Card Bottom Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMM d, yyyy').format(
                          DateFormat('yyyy-MM-dd HH:mm').parse(note.date),
                        ),
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: hintIconColor,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (dragHandle != null) ...[
                      dragHandle,
                      const SizedBox(width: 8),
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
                        note.isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 20,
                        color: note.isStarred ? const Color(0xFFFBBF24) : hintIconColor,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                        child: Icon(Icons.person_add_alt_1_rounded, size: 18, color: hintIconColor),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: () async {
                        if (note.isLocked) {
                          bool auth = await _showPinDialog();
                          if (!auth) return;
                        }
                        if (!mounted) return;
                        final isOwn = note.ownerUid == null || note.ownerUid == currentUser?.uid;
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text(
                              isOwn ? 'Delete Note' : 'Leave Shared Note',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                            ),
                            content: Text(
                              isOwn
                                  ? 'Are you sure you want to delete this note?'
                                  : 'Are you sure you want to stop collaborating on this note?',
                              style: GoogleFonts.outfit(fontSize: 14),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text('Cancel', style: GoogleFonts.outfit()),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(isOwn ? 'Delete' : 'Leave', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );

                        if (confirm != true) return;
                        await _storageService.deleteNote(note.id!, ownerUid: note.ownerUid);
                      },
                      child: Icon(Icons.delete_outline_rounded, size: 18, color: hintIconColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _stripSignature(String text) {
    return text.replaceAll(RegExp(r'\s*\(by\s+[^\)]+\)$'), '').trimRight();
  }

  static String? _extractUsername(String text) {
    final match = RegExp(r'\s*\(by\s+([^\)]+)\)$').firstMatch(text);
    return match?.group(1);
  }

  static Color _getSignatureColor(String username, bool isDarkTheme) {
    if (username.isEmpty) return isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    final List<Color> lightColors = [
      const Color(0xFFC05621), // Muted Dark Orange
      const Color(0xFF2B6CB0), // Muted Soft Blue
      const Color(0xFF2F855A), // Muted Forest Green
      const Color(0xFF805AD5), // Muted Purple
      const Color(0xFFD69E2E), // Muted Deep Gold
      const Color(0xFFB83280), // Muted Magenta
      const Color(0xFF319795), // Muted Teal
      const Color(0xFFDD6B20), // Muted Warm Coral
    ];

    final List<Color> darkColors = [
      const Color(0xFFFBD38D), // Soft Amber
      const Color(0xFF90CDF4), // Soft Light Blue
      const Color(0xFF9AE6B4), // Soft Light Green
      const Color(0xFFD6BCFA), // Soft Light Lavender
      const Color(0xFFFBB6CE), // Soft Soft Pink
      const Color(0xFF81E6D9), // Soft Soft Teal
      const Color(0xFFFEEBC8), // Soft Light Peach
      const Color(0xFFE9D8FD), // Soft Light Purple
    ];

    int hash = 0;
    for (int i = 0; i < username.length; i++) {
      hash = username.codeUnitAt(i) + ((hash << 5) - hash);
    }

    final colors = isDarkTheme ? darkColors : lightColors;
    final baseColor = colors[hash.abs() % colors.length];
    return baseColor.withValues(alpha: 0.85);
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    String cleanUrl = rawUrl.trim();
    if (cleanUrl.endsWith(')')) cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    if (!cleanUrl.toLowerCase().startsWith('http://') && !cleanUrl.toLowerCase().startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    try {
      final Uri uri = Uri.parse(cleanUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching URL ($cleanUrl): $e');
    }
  }

  List<InlineSpan> _buildTextSpansWithUrls(String text, TextStyle baseStyle) {
    final RegExp urlRegExp = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final Iterable<RegExpMatch> matches = urlRegExp.allMatches(text);

    if (matches.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final List<InlineSpan> spans = [];
    int lastMatchEnd = 0;

    for (final RegExpMatch match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final String url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: baseStyle.copyWith(
          color: const Color(0xFF6366F1),
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openExternalUrl(url),
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }

  Widget _buildFormattedTextWithSignature({
    required String text,
    required TextStyle baseStyle,
    required bool isDarkTheme,
    String? defaultAuthor,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
  }) {
    final username = _extractUsername(text) ?? defaultAuthor;
    final cleanedText = _stripSignature(text);

    final textSpans = _buildTextSpansWithUrls(cleanedText, baseStyle);

    if (username == null || username.isEmpty) {
      return Text.rich(
        TextSpan(children: textSpans),
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final sigColor = _getSignatureColor(username, isDarkTheme);

    return Text.rich(
      TextSpan(
        children: [
          ...textSpans,
          const TextSpan(text: ' '),
          TextSpan(
            text: '(by $username)',
            style: baseStyle.copyWith(
              color: sigColor,
              fontSize: ((baseStyle.fontSize ?? 13) * 0.88).clamp(9.0, 14.0),
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  bool _hasSignature(String text) {
    return RegExp(r'\s*\(by\s+[^\)]+\)$').hasMatch(text);
  }

  String _processContentWithSignatures(
    String newContent,
    String? originalContent,
    String currentUsername, {
    String? ownerUsername,
  }) {
    final defaultAuthor = (ownerUsername != null && ownerUsername.isNotEmpty) ? ownerUsername : currentUsername;

    if (originalContent == null || originalContent.isEmpty) {
      return newContent.split('\n').map((line) {
        if (line.trim().isEmpty) return line;
        final cleaned = _stripSignature(line);
        return '$cleaned (by $currentUsername)';
      }).join('\n');
    }

    final List<String> originalLines = originalContent.split('\n');
    final Map<String, String> originalStrippedMap = {};
    for (var orig in originalLines) {
      final stripped = _stripSignature(orig);
      if (stripped.isNotEmpty && !originalStrippedMap.containsKey(stripped)) {
        if (_hasSignature(orig)) {
          originalStrippedMap[stripped] = orig;
        } else {
          originalStrippedMap[stripped] = '$stripped (by $defaultAuthor)';
        }
      }
    }

    return newContent.split('\n').map((line) {
      final stripped = _stripSignature(line);
      if (stripped.trim().isEmpty) return line;
      if (originalStrippedMap.containsKey(stripped)) {
        return originalStrippedMap[stripped]!;
      }
      return '$stripped (by $currentUsername)';
    }).join('\n');
  }

  List<Map<String, dynamic>> _processChecklistWithSignatures(
    List<Map<String, dynamic>> newItems,
    List<Map<String, dynamic>>? originalItems,
    String currentUsername, {
    String? ownerUsername,
  }) {
    final defaultAuthor = (ownerUsername != null && ownerUsername.isNotEmpty) ? ownerUsername : currentUsername;

    if (originalItems == null || originalItems.isEmpty) {
      return newItems.map((item) {
        final text = item['text'] as String;
        if (text.trim().isEmpty) return item;
        final cleaned = _stripSignature(text);
        return {
          ...item,
          'text': '$cleaned (by $currentUsername)',
        };
      }).toList();
    }

    final Map<String, String> originalStrippedMap = {};
    for (var orig in originalItems) {
      final text = orig['text'] as String? ?? '';
      final stripped = _stripSignature(text);
      if (stripped.isNotEmpty && !originalStrippedMap.containsKey(stripped)) {
        if (_hasSignature(text)) {
          originalStrippedMap[stripped] = text;
        } else {
          originalStrippedMap[stripped] = '$stripped (by $defaultAuthor)';
        }
      }
    }

    return newItems.map((item) {
      final text = item['text'] as String;
      final stripped = _stripSignature(text);
      if (stripped.trim().isEmpty) return item;
      if (originalStrippedMap.containsKey(stripped)) {
        return {
          ...item,
          'text': originalStrippedMap[stripped]!,
        };
      }
      return {
        ...item,
        'text': '$stripped (by $currentUsername)',
      };
    }).toList();
  }

  List<String> _extractAllLinks(
    String title,
    String content,
    bool isChecklist,
    List<Map<String, dynamic>> checklistItems,
  ) {
    final RegExp urlRegExp = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final Set<String> links = {};

    final cleanTitle = _stripSignature(title);
    final cleanContent = _stripSignature(content);

    for (final match in urlRegExp.allMatches(cleanTitle)) {
      links.add(match.group(0)!);
    }
    for (final match in urlRegExp.allMatches(cleanContent)) {
      links.add(match.group(0)!);
    }

    if (isChecklist) {
      for (var item in checklistItems) {
        final text = item['text'] as String? ?? '';
        final cleanText = _stripSignature(text);
        for (final match in urlRegExp.allMatches(cleanText)) {
          links.add(match.group(0)!);
        }
      }
    }

    return links.toList();
  }
}

class LinkTextEditingController extends TextEditingController {
  LinkTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final RegExp urlRegExp = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final String textStr = text;

    if (textStr.isEmpty) {
      return TextSpan(text: textStr, style: style);
    }

    final List<TextSpan> children = [];
    final matches = urlRegExp.allMatches(textStr);
    int lastMatchEnd = 0;

    for (final RegExpMatch match in matches) {
      if (match.start > lastMatchEnd) {
        children.add(TextSpan(
          text: textStr.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }

      final url = match.group(0)!;
      children.add(TextSpan(
        text: url,
        style: (style ?? const TextStyle()).copyWith(
          color: const Color(0xFF6366F1),
          decoration: TextDecoration.underline,
        ),
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < textStr.length) {
      children.add(TextSpan(
        text: textStr.substring(lastMatchEnd),
        style: style,
      ));
    }

    return TextSpan(children: children, style: style);
  }
}
