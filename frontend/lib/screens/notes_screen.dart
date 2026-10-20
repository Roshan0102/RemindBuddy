import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/note.dart';
import '../services/storage_service.dart';
import '../widgets/collaboration_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../services/url_launcher_helper/url_launcher_helper.dart';
import '../services/home_widget_service.dart';
import '../services/notes_ai_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  static final ValueNotifier<String?> targetNoteIdNotifier = ValueNotifier<String?>(null);

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
    HomeWidgetService().syncWidgetChangesToFirestore();
    NotesScreen.targetNoteIdNotifier.addListener(_checkTargetNote);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTargetNote();
    });
  }

  @override
  void dispose() {
    NotesScreen.targetNoteIdNotifier.removeListener(_checkTargetNote);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _isCheckingTargetNote = false;

  Future<void> _checkTargetNote([List<Note>? currentNotes]) async {
    final targetId = NotesScreen.targetNoteIdNotifier.value;
    if (targetId == null || targetId.isEmpty || _isCheckingTargetNote) return;

    if (!mounted) return;

    // 1. Check if note is already in the loaded notes list
    if (currentNotes != null && currentNotes.isNotEmpty) {
      final localMatch = currentNotes.where((n) => n.id == targetId).firstOrNull;
      if (localMatch != null) {
        NotesScreen.targetNoteIdNotifier.value = null;
        _addOrEditNote(note: localMatch);
        return;
      }
    }

    _isCheckingTargetNote = true;
    try {
      // 2. If user auth is still loading (cold start from widget), wait briefly for auth state
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance
              .authStateChanges()
              .firstWhere((u) => u != null)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }

      final note = await _storageService.getNoteById(targetId);
      if (note != null && mounted) {
        NotesScreen.targetNoteIdNotifier.value = null;
        _addOrEditNote(note: note);
      }
    } catch (e) {
      debugPrint('Error opening note from widget deep link: $e');
    } finally {
      _isCheckingTargetNote = false;
    }
  }

  Future<void> _loadCustomOrder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notes_custom_order_$uid');
    setState(() {
      _customOrderIds = [];
    });
  }

  Future<void> _saveCustomOrder(List<String> order) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notes_custom_order_$uid', order);
  }

  DateTime _parseNoteDate(String dateStr) {
    if (dateStr.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parse(dateStr);
    } catch (_) {}
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parse(dateStr);
    } catch (_) {}
    try {
      return DateFormat('yyyy-MM-dd').parse(dateStr);
    } catch (_) {}
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Note> _sortNotesWithCustomOrder(List<Note> notes) {
    final starredNotes = notes.where((n) => n.isStarred).toList();
    final unstarredNotes = notes.where((n) => !n.isStarred).toList();

    // Sort both pinned and unpinned notes by last edited date descending
    starredNotes.sort((a, b) => _parseNoteDate(b.date).compareTo(_parseNoteDate(a.date)));
    unstarredNotes.sort((a, b) => _parseNoteDate(b.date).compareTo(_parseNoteDate(a.date)));

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
    String? currentNoteId = note?.id;
    final currentUser = FirebaseAuth.instance.currentUser;
    final String? ownerUid = note?.ownerUid ?? currentUser?.uid;

    final titleController = TextEditingController(text: note?.title ?? '');
    final titleFocusNode = FocusNode();

    final String rawContent = note?.content ?? '';
    final String editableContent = rawContent.isNotEmpty
        ? rawContent.split('\n').map((line) => _stripSignature(line)).join('\n')
        : '';
    final contentController = LinkTextEditingController(text: editableContent);
    final contentFocusNode = FocusNode();

    bool isLocked = note?.isLocked ?? false;
    bool isStarred = note?.isStarred ?? false;
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

    // Check Lock
    if (note != null && note.isLocked) {
      bool authenticated = await _showPinDialog();
      if (!authenticated) {
        titleController.dispose();
        titleFocusNode.dispose();
        contentController.dispose();
        contentFocusNode.dispose();
        for (var c in itemControllers) {
          c.dispose();
        }
        for (var n in itemFocusNodes) {
          n.dispose();
        }
        return;
      }
    }

    bool isSaving = false;
    bool isDisposed = false;
    bool isSyncingRemote = false;
    bool hasUnsavedChanges = false;

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? liveDocSub;
    Timer? autoSaveTimer;
    void Function(void Function())? dialogSetState;

    // Real-Time Document Synchronization across tabs/devices
    void setupLiveDocListener(String noteId, String uid) {
      liveDocSub?.cancel();
      liveDocSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notes')
          .doc(noteId)
          .snapshots()
          .listen((snapshot) {
        if (isDisposed || !snapshot.exists || snapshot.data() == null) return;
        // Skip local write echoes to preserve cursor offset and prevent rubber-banding
        if (snapshot.metadata.hasPendingWrites) return;

        final data = snapshot.data()!;
        final remoteNote = Note.fromMap(data, snapshot.id, ownerUid: uid);

        if (dialogSetState != null) {
          isSyncingRemote = true;
          dialogSetState!(() {
            // 1. Sync Title if not currently focused by local user
            if (!titleFocusNode.hasFocus && titleController.text != remoteNote.title) {
              titleController.text = remoteNote.title;
            }

            // 2. Sync Lock & Star states
            isLocked = remoteNote.isLocked;
            isStarred = remoteNote.isStarred;

            // 3. Sync Checklist or Note content
            if (remoteNote.isChecklist) {
              isChecklist = true;
              final remoteItems = remoteNote.checklistItems;

              // Find which item (if any) currently has active keyboard focus
              int activeFocusIndex = -1;
              for (int i = 0; i < itemFocusNodes.length; i++) {
                if (itemFocusNodes[i].hasFocus) {
                  activeFocusIndex = i;
                  break;
                }
              }

              // Adjust controller and focus node pool size
              while (itemControllers.length < remoteItems.length) {
                itemControllers.add(LinkTextEditingController());
                itemFocusNodes.add(FocusNode());
              }
              while (itemControllers.length > remoteItems.length) {
                final c = itemControllers.removeLast();
                final f = itemFocusNodes.removeLast();
                c.dispose();
                f.dispose();
              }

              checklistItems = List<Map<String, dynamic>>.from(
                remoteItems.map((item) {
                  final String text = item['text'] as String? ?? '';
                  return {
                    ...item,
                    'text': _stripSignature(text),
                  };
                }),
              );

              for (int i = 0; i < remoteItems.length; i++) {
                final strippedText = _stripSignature(remoteItems[i]['text'] as String? ?? '');
                // Do not clobber the exact input field the user is actively typing into
                if (i != activeFocusIndex && itemControllers[i].text != strippedText) {
                  itemControllers[i].text = strippedText;
                }
              }
            } else {
              isChecklist = false;
              if (!contentFocusNode.hasFocus) {
                final remoteContent = remoteNote.content.isNotEmpty
                    ? remoteNote.content.split('\n').map((l) => _stripSignature(l)).join('\n')
                    : '';
                if (contentController.text != remoteContent) {
                  contentController.text = remoteContent;
                }
              }
            }
          });
          isSyncingRemote = false;
        }
      }, onError: (err) {
        debugPrint("[NotesSync] Live document sync error: $err");
      });
    }

    // Auto-sync function to immediately or debounced push changes to Firestore
    Future<void> syncToFirestore({bool immediate = false}) async {
      if (isDisposed || isSyncingRemote) return;

      final title = titleController.text.trim();
      final effectiveUid = ownerUid ?? FirebaseAuth.instance.currentUser?.uid;
      if (effectiveUid == null) return;

      List<Map<String, dynamic>> itemsToSave = [];
      if (isChecklist) {
        for (int i = 0; i < checklistItems.length; i++) {
          final text = i < itemControllers.length
              ? itemControllers[i].text
              : (checklistItems[i]['text'] as String? ?? '');
          if (text.isNotEmpty) {
            itemsToSave.add({
              'text': text,
              'isChecked': checklistItems[i]['isChecked'] == true,
            });
          }
        }
      }

      final isShared = currentNoteId != null &&
          note != null &&
          (note.sharedWith.isNotEmpty || (note.ownerUid != null && note.ownerUid != currentUser?.uid));

      if (isShared) {
        final currentUsername =
            currentUser?.displayName ?? currentUser?.email?.split('@').first ?? 'User';
        if (isChecklist) {
          itemsToSave = _processChecklistWithSignatures(
            itemsToSave,
            note.checklistItems,
            currentUsername,
            ownerUsername: note.ownerUsername,
          );
        } else {
          contentController.text = _processContentWithSignatures(
            contentController.text,
            note.content,
            currentUsername,
            ownerUsername: note.ownerUsername,
          );
        }
      }

      String content = contentController.text;
      if (isChecklist) {
        content = itemsToSave
            .map((item) => (item['isChecked'] == true ? '[x] ' : '[ ] ') + (item['text'] as String))
            .join('\n');
      }

      if (currentNoteId == null) {
        if (title.isNotEmpty || (isChecklist ? itemsToSave.isNotEmpty : content.trim().isNotEmpty)) {
          final newNote = Note(
            title: title,
            content: content,
            date: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
            isLocked: isLocked,
            ownerUid: effectiveUid,
            sharedWith: [],
            isChecklist: isChecklist,
            checklistItems: itemsToSave,
            isStarred: isStarred,
          );
          try {
            final newId = await _storageService.insertNote(newNote);
            if (newId.isNotEmpty) {
              currentNoteId = newId;
              hasUnsavedChanges = false;
              setupLiveDocListener(newId, effectiveUid);
            }
          } catch (e) {
            debugPrint("[NotesSync] Error inserting new note: $e");
          }
        }
      } else {
        final updatedNote = Note(
          id: currentNoteId,
          title: title,
          content: content,
          date: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
          isLocked: isLocked,
          ownerUid: effectiveUid,
          sharedWith: note?.sharedWith ?? [],
          isChecklist: isChecklist,
          checklistItems: itemsToSave,
          isStarred: isStarred,
        );
        try {
          await _storageService.updateNote(updatedNote);
          await HomeWidgetService().checkAndSyncIfPinnedNote(updatedNote);
          hasUnsavedChanges = false;
        } catch (e) {
          debugPrint("[NotesSync] Error updating note: $e");
        }
      }
    }

    void scheduleAutoSave() {
      hasUnsavedChanges = true;
      autoSaveTimer?.cancel();
      autoSaveTimer = Timer(const Duration(milliseconds: 600), () {
        syncToFirestore(immediate: false);
      });
    }

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
      // Immediately sync check state to Firestore
      syncToFirestore(immediate: true);
    }

    MathResult? activeMathResult;
    TextEditingController? activeMathController;
    late void Function(void Function(void Function())) applyMath;

    void updateMath(
      TextEditingController ctrl,
      void Function(void Function()) setDialogState,
    ) {
      final sel = ctrl.selection;
      final pos = sel.isValid ? sel.baseOffset : ctrl.text.length;
      final res = NotesAiService.findLastMathExpression(ctrl.text, pos);

      // Clear any prior controller's inline suggestion if switching fields
      if (activeMathController != null &&
          activeMathController != ctrl &&
          activeMathController is LinkTextEditingController) {
        final prev = activeMathController as LinkTextEditingController;
        prev.inlineMathSuggestion = null;
        prev.inlineMathTargetIndex = null;
        prev.onSuggestionTapped = null;
      }

      if (ctrl is LinkTextEditingController) {
        ctrl.inlineMathSuggestion = res?.result;
        ctrl.inlineMathTargetIndex = res?.matchEndIndex;
        ctrl.onSuggestionTapped = () => applyMath(setDialogState);
      }

      if (res?.result != activeMathResult?.result ||
          res?.expression != activeMathResult?.expression ||
          activeMathController != ctrl) {
        setDialogState(() {
          activeMathResult = res;
          activeMathController = ctrl;
        });
      }
    }

    applyMath = (void Function(void Function()) setDialogState) {
      if (activeMathResult == null || activeMathController == null) return;
      final ctrl = activeMathController!;
      final res = activeMathResult!;
      final text = ctrl.text;
      if (res.matchEndIndex <= text.length) {
        final before = text.substring(0, res.matchEndIndex);
        final after = text.substring(res.matchEndIndex);
        final insertStr = ' ${res.result} ';
        final newText = '$before$insertStr$after';
        final newCursor = before.length + insertStr.length;
        if (ctrl is LinkTextEditingController) {
          ctrl.inlineMathSuggestion = null;
          ctrl.inlineMathTargetIndex = null;
          ctrl.onSuggestionTapped = null;
        }
        ctrl.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newCursor),
        );
      }
      setDialogState(() {
        activeMathResult = null;
        activeMathController = null;
      });
    };

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            dialogSetState = setDialogState;
            if (currentNoteId != null && ownerUid != null && liveDocSub == null) {
              setupLiveDocListener(currentNoteId!, ownerUid);
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (bool didPop, Object? result) async {
                if (didPop) {
                  autoSaveTimer?.cancel();
                  if (hasUnsavedChanges) {
                    await syncToFirestore(immediate: true);
                  }
                }
              },
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                },
                child: Focus(
                  autofocus: true,
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
                        syncToFirestore(immediate: true);
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
                        syncToFirestore(immediate: true);
                      },
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                      ),
                      tooltip: 'AI Writing & Math Tools',
                      onPressed: () async {
                        await _openNoteAiTools(
                          context: context,
                          isChecklist: isChecklist,
                          titleController: titleController,
                          contentController: contentController,
                          checklistItems: checklistItems,
                          itemControllers: itemControllers,
                          itemFocusNodes: itemFocusNodes,
                          setDialogState: setDialogState,
                        );
                        syncToFirestore(immediate: true);
                      },
                    ),
                    if (isChecklist)
                      IconButton(
                        icon: const Icon(Icons.widgets_outlined, size: 20),
                        tooltip: 'Pin Checklist to Home Screen',
                        onPressed: () async {
                          final currentNote = Note(
                            id: currentNoteId ?? note?.id,
                            title: titleController.text.trim(),
                            content: contentController.text,
                            date: note?.date ?? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                            isLocked: isLocked,
                            ownerUid: ownerUid ?? note?.ownerUid,
                            sharedWith: note?.sharedWith ?? [],
                            isChecklist: true,
                            checklistItems: checklistItems,
                            isStarred: isStarred,
                          );
                          await _handlePinOrAssignWidget(context, currentNote);
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
                                setDialogState(() {
                                  isSaving = true;
                                });
                                autoSaveTimer?.cancel();
                                await syncToFirestore(immediate: true);
                                if (context.mounted) Navigator.pop(context);
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
                        focusNode: titleFocusNode,
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
                        onChanged: (val) {
                          scheduleAutoSave();
                        },
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
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Focus(
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
                                                            syncToFirestore(immediate: true);
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
                                                          updateMath(itemControllers[index], setDialogState);
                                                          setDialogState(() {});
                                                          scheduleAutoSave();
                                                        },
                                                      ),
                                                    ),
                                                    if (_extractUrlsFromText(item['text'] as String? ?? '').isNotEmpty)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
                                                        child: Wrap(
                                                          spacing: 6,
                                                          runSpacing: 4,
                                                          children: _extractUrlsFromText(item['text'] as String? ?? '').map((url) => Material(
                                                            color: Colors.transparent,
                                                            child: InkWell(
                                                              onTap: () => _promptAndOpenUrl(context, url),
                                                              borderRadius: BorderRadius.circular(8),
                                                              child: Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.1),
                                                                  borderRadius: BorderRadius.circular(8),
                                                                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    const Icon(Icons.link_rounded, size: 13, color: Color(0xFF6366F1)),
                                                                    const SizedBox(width: 4),
                                                                    Text(
                                                                      _formatDisplayUrl(url),
                                                                      style: GoogleFonts.outfit(
                                                                        fontSize: 11,
                                                                        color: const Color(0xFF6366F1),
                                                                        fontWeight: FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 4),
                                                                    const Icon(Icons.open_in_new_rounded, size: 11, color: Color(0xFF6366F1)),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          )).toList(),
                                                        ),
                                                      ),
                                                  ],
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
                                                  syncToFirestore(immediate: true);
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
                                        syncToFirestore(immediate: true);
                                      },
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_extractUrlsFromText(contentController.text).isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: _extractUrlsFromText(contentController.text).map((url) => Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () => _promptAndOpenUrl(context, url),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.link_rounded, size: 13, color: Color(0xFF6366F1)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _formatDisplayUrl(url),
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 11,
                                                      color: const Color(0xFF6366F1),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.open_in_new_rounded, size: 11, color: Color(0xFF6366F1)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )).toList(),
                                      ),
                                    ),
                                  Expanded(
                                    child: TextField(
                                      controller: contentController,
                                      focusNode: contentFocusNode,
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
                                      onChanged: (val) {
                                        updateMath(contentController, setDialogState);
                                        setDialogState(() {});
                                        scheduleAutoSave();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (activeMathResult != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 6),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => applyMath(setDialogState),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withValues(
                                      alpha: isDark ? 0.22 : 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF6366F1).withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.15),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 15,
                                        color: Color(0xFF6366F1),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '= ${activeMathResult!.result}',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: const Color(0xFF6366F1),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Tap to insert',
                                          style: GoogleFonts.outfit(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Dispose resources on dialog close
    isDisposed = true;
    autoSaveTimer?.cancel();
    liveDocSub?.cancel();
    titleFocusNode.dispose();
    contentFocusNode.dispose();
    for (var controller in itemControllers) {
      controller.dispose();
    }
    for (var node in itemFocusNodes) {
      node.dispose();
    }
  }

  Future<void> _openNoteAiTools({
    required BuildContext context,
    required bool isChecklist,
    required TextEditingController titleController,
    required TextEditingController contentController,
    required List<Map<String, dynamic>> checklistItems,
    required List<TextEditingController> itemControllers,
    required List<FocusNode> itemFocusNodes,
    required void Function(void Function()) setDialogState,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedAction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notes AI & Math Tools',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Instant 0ms Math & Gemini AI Assistant',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildAiToolOption(
                    ctx,
                    action: 'calculate_and_sum',
                    title: 'Calculate & Sum All',
                    subtitle: 'Solves all math equations and sums up items/names with totals',
                    icon: Icons.functions_rounded,
                    iconColor: const Color(0xFF6366F1),
                    isDark: isDark,
                  ),
                  _buildAiToolOption(
                    ctx,
                    action: 'custom_prompt',
                    title: 'Ask AI / Custom Prompt',
                    subtitle: 'Give any custom instruction to write, edit, or transform this note',
                    icon: Icons.psychology_rounded,
                    iconColor: const Color(0xFFEC4899),
                    isDark: isDark,
                  ),
                  _buildAiToolOption(
                    ctx,
                    action: 'solve_all_math',
                    title: 'Solve All Math in Note',
                    subtitle: 'Instantly calculate all formulas and expressions ending with =',
                    icon: Icons.calculate_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    isDark: isDark,
                  ),
                  _buildAiToolOption(
                    ctx,
                    action: 'fix_grammar',
                    title: 'Fix Grammar & Spelling',
                    subtitle: 'Correct typos and punctuation while keeping your original tone',
                    icon: Icons.spellcheck_rounded,
                    iconColor: const Color(0xFF10B981),
                    isDark: isDark,
                  ),
                  _buildAiToolOption(
                    ctx,
                    action: 'polish',
                    title: 'Polish & Professionalize',
                    subtitle: 'Elevate tone, sentence flow, and clarity for a pristine finish',
                    icon: Icons.auto_awesome_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    isDark: isDark,
                  ),
                  _buildAiToolOption(
                    ctx,
                    action: 'summarize',
                    title: 'Summarize Key Points',
                    subtitle: 'Generate bulleted summary of key ideas and action points',
                    icon: Icons.format_list_bulleted_rounded,
                    iconColor: const Color(0xFF3B82F6),
                    isDark: isDark,
                  ),
                  _buildAiToolOption(
                    ctx,
                    action: 'to_checklist',
                    title: 'Convert to Checklist',
                    subtitle: 'Transform notes into actionable checkable to-do items',
                    icon: Icons.playlist_add_check_rounded,
                    iconColor: const Color(0xFFEC4899),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedAction == null || !context.mounted) return;

    if (selectedAction == 'solve_all_math') {
      if (isChecklist) {
        int count = 0;
        setDialogState(() {
          for (int i = 0; i < itemControllers.length; i++) {
            final original = itemControllers[i].text;
            final solved = NotesAiService.solveAllMathInText(original);
            if (solved != original) {
              itemControllers[i].text = solved;
              checklistItems[i]['text'] = solved;
              count++;
            }
          }
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(count > 0 ? 'Solved math in $count checklist items!' : 'No unsolved equations found (e.g. 100 + 30 =)'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF8B5CF6),
            ),
          );
        }
      } else {
        final original = contentController.text;
        final solved = NotesAiService.solveAllMathInText(original);
        if (solved != original) {
          setDialogState(() {
            contentController.text = solved;
          });
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('All math expressions solved!'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Color(0xFF8B5CF6),
              ),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No unsolved equations found (e.g. 100 + 30 =)'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
      return;
    }

    String? customPrompt;
    if (selectedAction == 'custom_prompt') {
      final promptCtrl = TextEditingController();
      final userConfirmed = await showDialog<bool>(
        context: context,
        builder: (pCtx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Ask AI',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What would you like AI to do with this note?',
                style: GoogleFonts.outfit(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                autofocus: true,
                maxLines: 3,
                style: GoogleFonts.outfit(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g., Categorize expenses, translate to French, add key takeaways, organize into sections...',
                  hintStyle: GoogleFonts.outfit(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(pCtx, false),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(pCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Generate', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (userConfirmed != true || promptCtrl.text.trim().isEmpty) return;
      customPrompt = promptCtrl.text.trim();
    }

    final rawText = isChecklist
        ? checklistItems.map((it) => (it['text'] as String? ?? '').trim()).where((t) => t.isNotEmpty).join('\n')
        : contentController.text;

    if (rawText.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add some content to your note first!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6366F1)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'AI is processing your note...',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      String aiResult;
      try {
        aiResult = await NotesAiService.callNotesAI(
          action: selectedAction,
          text: rawText,
          title: titleController.text,
          customPrompt: customPrompt,
        );
      } catch (cloudErr) {
        if (selectedAction == 'calculate_and_sum') {
          aiResult = NotesAiService.calculateAndSumInText(rawText);
        } else {
          rethrow;
        }
      }

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (!context.mounted) return;

      await _showAiResultPreviewDialog(
        context: context,
        action: selectedAction,
        originalText: rawText,
        aiResult: aiResult,
        isChecklist: isChecklist,
        contentController: contentController,
        checklistItems: checklistItems,
        itemControllers: itemControllers,
        itemFocusNodes: itemFocusNodes,
        setDialogState: setDialogState,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notes AI error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildAiToolOption(
    BuildContext context, {
    required String action,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(context, action),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showAiResultPreviewDialog({
    required BuildContext context,
    required String action,
    required String originalText,
    required String aiResult,
    required bool isChecklist,
    required TextEditingController contentController,
    required List<Map<String, dynamic>> checklistItems,
    required List<TextEditingController> itemControllers,
    required List<FocusNode> itemFocusNodes,
    required void Function(void Function()) setDialogState,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final actionTitles = {
      'calculate_and_sum': 'Calculated & Summed',
      'custom_prompt': 'AI Generated Note',
      'fix_grammar': 'Grammar & Spelling Fixed',
      'polish': 'Polished Note',
      'summarize': 'Key Points Summary',
      'to_checklist': 'Checklist Created',
    };

    final title = actionTitles[action] ?? 'AI Suggestion';

    await showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    aiResult,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          if (action != 'to_checklist')
            OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Append to Note'),
              onPressed: () {
                setDialogState(() {
                  if (isChecklist) {
                    final lines = aiResult.split('\n').where((l) => l.trim().isNotEmpty);
                    for (final l in lines) {
                      checklistItems.add({'text': l.trim(), 'isChecked': false});
                      itemControllers.add(LinkTextEditingController(text: l.trim()));
                      itemFocusNodes.add(FocusNode());
                    }
                  } else {
                    final curr = contentController.text.trim();
                    contentController.text = curr.isEmpty ? aiResult : '$curr\n\n$aiResult';
                  }
                });
                Navigator.pop(dlgCtx);
              },
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text(action == 'to_checklist' ? 'Apply Checklist' : 'Replace Note'),
            onPressed: () {
              setDialogState(() {
                if (action == 'to_checklist' || isChecklist) {
                  final lines = aiResult.split('\n').where((l) => l.trim().isNotEmpty).toList();
                  checklistItems.clear();
                  for (final c in itemControllers) {
                    c.dispose();
                  }
                  for (final f in itemFocusNodes) {
                    f.dispose();
                  }
                  itemControllers.clear();
                  itemFocusNodes.clear();

                  for (final l in lines) {
                    var cleaned = l.trim();
                    if (cleaned.startsWith('- [ ] ') || cleaned.startsWith('- [x] ')) {
                      cleaned = cleaned.substring(6).trim();
                    } else if (cleaned.startsWith('- ') || cleaned.startsWith('* ')) {
                      cleaned = cleaned.substring(2).trim();
                    } else if (RegExp(r'^\d+\.\s+').hasMatch(cleaned)) {
                      cleaned = cleaned.replaceFirst(RegExp(r'^\d+\.\s+'), '').trim();
                    }
                    if (cleaned.isNotEmpty) {
                      checklistItems.add({'text': cleaned, 'isChecked': false});
                      itemControllers.add(LinkTextEditingController(text: cleaned));
                      itemFocusNodes.add(FocusNode());
                    }
                  }
                  if (checklistItems.isEmpty) {
                    checklistItems.add({'text': '', 'isChecked': false});
                    itemControllers.add(LinkTextEditingController(text: ''));
                    itemFocusNodes.add(FocusNode());
                  }
                } else {
                  contentController.text = aiResult;
                }
              });
              Navigator.pop(dlgCtx);
            },
          ),
        ],
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
          if (allNotes.isNotEmpty && NotesScreen.targetNoteIdNotifier.value != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _checkTargetNote(allNotes);
            });
          }
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
                          date: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
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
                    if (note.isChecklist) ...[
                      GestureDetector(
                        onTap: () => _handlePinOrAssignWidget(context, note),
                        child: Tooltip(
                          message: 'Pin to Home Screen Widget',
                          child: Icon(Icons.widgets_outlined, size: 18, color: hintIconColor),
                        ),
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

  List<String> _extractUrlsFromText(String text) {
    if (text.isEmpty) return [];
    final RegExp urlRegExp = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final Iterable<RegExpMatch> matches = urlRegExp.allMatches(text);
    final List<String> urls = [];
    for (final m in matches) {
      String raw = m.group(0)!;
      if (raw.endsWith('.') || raw.endsWith(',') || raw.endsWith(')')) {
        raw = raw.substring(0, raw.length - 1);
      }
      if (raw.isNotEmpty && !urls.contains(raw)) {
        urls.add(raw);
      }
    }
    return urls;
  }

  String _formatDisplayUrl(String url) {
    String clean = url.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    clean = clean.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
    if (clean.length > 35) {
      clean = '${clean.substring(0, 32)}...';
    }
    return clean;
  }

  Future<void> _promptAndOpenUrl(BuildContext context, String rawUrl) async {
    String cleanUrl = rawUrl.trim();
    if (cleanUrl.endsWith(')')) cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    if (!cleanUrl.toLowerCase().startsWith('http://') && !cleanUrl.toLowerCase().startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.open_in_new_rounded, color: Color(0xFF6366F1), size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Open External Link?',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to navigate to an external website:',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: SelectableText(
                cleanUrl,
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  color: const Color(0xFF6366F1),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.launch_rounded, size: 16),
            label: Text(
              'Open Link',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldOpen == true) {
      await UrlLauncherHelper.openInNewTabOrExternal(cleanUrl);
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
          ..onTap = () => _promptAndOpenUrl(context, url),
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

  Future<void> _handlePinOrAssignWidget(BuildContext context, Note note) async {
    final instances = await HomeWidgetService().getNoteWidgetInstances();
    if (!context.mounted) return;

    if (instances.isEmpty) {
      final pinned = await HomeWidgetService().pinNoteChecklistWidget(note);
      if (!context.mounted) return;
      _showWidgetResultSnackbar(context, note, pinned);
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedOption = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.widgets_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Home Screen Widget',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          Text(
                            'Assign "${note.title.isNotEmpty ? note.title : 'Checklist'}" to a widget',
                            style: GoogleFonts.outfit(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_to_home_screen_rounded, color: Color(0xFF10B981), size: 22),
                  ),
                  title: Text(
                    'Pin New Widget to Home Screen',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Text(
                    'Adds a separate widget for this note alongside your existing widgets',
                    style: GoogleFonts.outfit(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                  onTap: () => Navigator.pop(sheetCtx, {'action': 'pin_new'}),
                ),
                const Divider(height: 16),
                Text(
                  'OR UPDATE AN EXISTING WIDGET',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 8),
                ...instances.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final inst = entry.value;
                  final widgetId = inst['appWidgetId'] as int;
                  final currentTitle = inst['title']?.toString() ?? 'Checklist';
                  final isCurrentNote = inst['noteId'] == note.id;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isCurrentNote ? const Color(0xFF6366F1) : Colors.blueGrey).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCurrentNote ? Icons.check_circle_rounded : Icons.phone_android_rounded,
                        color: isCurrentNote ? const Color(0xFF6366F1) : (isDark ? Colors.white70 : Colors.blueGrey),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Widget #${idx + 1}: $currentTitle',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      isCurrentNote ? 'Already showing this note' : 'Switch this widget to "${note.title.isNotEmpty ? note.title : 'Checklist'}"',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isCurrentNote ? const Color(0xFF6366F1) : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                    onTap: () => Navigator.pop(sheetCtx, {
                      'action': 'update_existing',
                      'appWidgetId': widgetId,
                    }),
                  );
                }),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );

    if (selectedOption == null || !context.mounted) return;

    if (selectedOption['action'] == 'pin_new') {
      final pinned = await HomeWidgetService().pinNoteChecklistWidget(note);
      if (!context.mounted) return;
      _showWidgetResultSnackbar(context, note, pinned);
    } else if (selectedOption['action'] == 'update_existing') {
      final appWidgetId = selectedOption['appWidgetId'] as int;
      await HomeWidgetService().pinNoteChecklistWidget(note, targetAppWidgetId: appWidgetId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Updated widget with "${note.title.isNotEmpty ? note.title : 'Checklist'}"!',
                  style: GoogleFonts.outfit(),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF6366F1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showWidgetResultSnackbar(BuildContext context, Note note, bool pinned) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pinned
                    ? 'Pinned "${note.title.isNotEmpty ? note.title : 'Checklist'}" to Home Screen!'
                    : 'Checklist synced to Home Widget! Add the "Checklist Note" widget to your home screen.',
                style: GoogleFonts.outfit(),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class LinkTextEditingController extends TextEditingController {
  String? inlineMathSuggestion;
  int? inlineMathTargetIndex;
  VoidCallback? onSuggestionTapped;

  LinkTextEditingController({
    super.text,
    this.inlineMathSuggestion,
    this.inlineMathTargetIndex,
    this.onSuggestionTapped,
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final RegExp urlRegExp =
        RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final String textStr = text;

    if (textStr.isEmpty) {
      if (inlineMathSuggestion != null && inlineMathSuggestion!.isNotEmpty) {
        return TextSpan(
          children: [
            TextSpan(
              text: ' $inlineMathSuggestion',
              style: (style ?? const TextStyle()).copyWith(
                color: const Color(0xFF6366F1).withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
              ),
              recognizer: onSuggestionTapped != null
                  ? (TapGestureRecognizer()..onTap = onSuggestionTapped)
                  : null,
            ),
          ],
          style: style,
        );
      }
      return TextSpan(text: textStr, style: style);
    }

    final int? targetIdx = inlineMathTargetIndex;
    final String? suggestion = inlineMathSuggestion;
    final bool hasInlineSuggestion = suggestion != null &&
        suggestion.isNotEmpty &&
        targetIdx != null &&
        targetIdx >= 0 &&
        targetIdx <= textStr.length;

    final List<TextSpan> children = [];
    final matches = urlRegExp.allMatches(textStr);
    int lastMatchEnd = 0;

    void addTextSegment(int start, int end) {
      if (start >= end) return;
      if (hasInlineSuggestion && targetIdx >= start && targetIdx <= end) {
        if (targetIdx > start) {
          children.add(
            TextSpan(
              text: textStr.substring(start, targetIdx),
              style: style,
            ),
          );
        }
        children.add(
          TextSpan(
            text: ' $suggestion',
            style: (style ?? const TextStyle()).copyWith(
              color: const Color(0xFF6366F1).withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.bold,
            ),
            recognizer: onSuggestionTapped != null
                ? (TapGestureRecognizer()..onTap = onSuggestionTapped)
                : null,
          ),
        );
        if (end > targetIdx) {
          children.add(
            TextSpan(
              text: textStr.substring(targetIdx, end),
              style: style,
            ),
          );
        }
      } else {
        children.add(
          TextSpan(
            text: textStr.substring(start, end),
            style: style,
          ),
        );
      }
    }

    for (final RegExpMatch match in matches) {
      if (match.start > lastMatchEnd) {
        addTextSegment(lastMatchEnd, match.start);
      }

      final url = match.group(0)!;
      children.add(
        TextSpan(
          text: url,
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF6366F1),
            decoration: TextDecoration.underline,
          ),
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < textStr.length) {
      addTextSegment(lastMatchEnd, textStr.length);
    } else if (hasInlineSuggestion && targetIdx == textStr.length) {
      children.add(
        TextSpan(
          text: ' $suggestion',
          style: (style ?? const TextStyle()).copyWith(
            color: const Color(0xFF6366F1).withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          ),
          recognizer: onSuggestionTapped != null
              ? (TapGestureRecognizer()..onTap = onSuggestionTapped)
              : null,
        ),
      );
    }

    return TextSpan(children: children, style: style);
  }
}

