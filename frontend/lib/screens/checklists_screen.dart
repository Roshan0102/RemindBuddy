
import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  final StorageService _storage = StorageService();
  List<Map<String, dynamic>> _checklists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChecklists();
  }

  Future<void> _loadChecklists() async {
    setState(() => _isLoading = true);
    final lists = await _storage.getChecklists();
    setState(() {
      _checklists = lists;
      _isLoading = false;
    });
  }

  Future<void> _createChecklist(String title, int iconCode, int colorValue) async {
    await _storage.createChecklist(title, iconCode, colorValue);
    _loadChecklists();
  }

  Future<void> _deleteChecklist(String id) async {
    await _storage.deleteChecklist(id);
    _loadChecklists();
  }

  void _showAddDialog() {
    final TextEditingController _controller = TextEditingController();
    int _selectedIcon = Icons.list.codePoint;
    int _selectedColorValue = Colors.blue.value;
    bool _isSaving = false;

    final List<Map<String, dynamic>> _options = [
      {'icon': Icons.work, 'color': Colors.blue},
      {'icon': Icons.flight_takeoff, 'color': Colors.orange},
      {'icon': Icons.school, 'color': Colors.green},
      {'icon': Icons.fitness_center, 'color': Colors.purple},
      {'icon': Icons.shopping_bag, 'color': Colors.pink},
      {'icon': Icons.home, 'color': Colors.teal},
      {'icon': Icons.restaurant, 'color': Colors.red},
      {'icon': Icons.medical_services, 'color': Colors.cyan},
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('New Checklist', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        labelText: 'List Name',
                        hintText: 'e.g., Office, Travel',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.edit),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 20),
                    const Text('Pick a style:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      height: 120,
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: _options.length,
                        itemBuilder: (context, index) {
                          final option = _options[index];
                          final isSelected = _selectedIcon == (option['icon'] as IconData).codePoint;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                _selectedIcon = (option['icon'] as IconData).codePoint;
                                _selectedColorValue = (option['color'] as Color).value;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: (option['color'] as Color).withOpacity(isSelected ? 0.2 : 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? (option['color'] as Color) : Colors.grey.withOpacity(0.2),
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                option['icon'] as IconData,
                                color: isSelected ? (option['color'] as Color) : Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                _isSaving 
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (_controller.text.isNotEmpty) {
                          setDialogState(() => _isSaving = true);
                          try {
                            await _createChecklist(_controller.text, _selectedIcon, _selectedColorValue);
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            setDialogState(() => _isSaving = false);
                          }
                        }
                      },
                      child: const Text('Create'),
                    ),
              ],
            );
          }
        );
      },
    );
  }

  IconData _getIconFromCode(int? code) {
    if (code == null) return Icons.list;
    return IconData(code, fontFamily: 'MaterialIcons');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Belongings', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('New List'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _storage.getChecklistsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _checklists.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final checklists = snapshot.data ?? [];
          
          if (checklists.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 100, color: Colors.grey[300]),
                  const SizedBox(height: 24),
                  const Text(
                    'No lists organized yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _showAddDialog,
                    child: const Text('Create your first list'),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemCount: checklists.length,
            itemBuilder: (context, index) {
              final list = checklists[index];
              final colorValue = list['color'] ?? Colors.blue.value;
              final color = Color(colorValue);
              final icon = _getIconFromCode(list['iconCode']);

              return Hero(
                tag: 'list_${list['id']}',
                child: Material(
                  borderRadius: BorderRadius.circular(24),
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChecklistDetailScreen(
                            checklistId: list['id'],
                            title: list['title'],
                            color: color,
                          ),
                        ),
                      );
                    },
                    onLongPress: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete List?'),
                          content: Text('Are you sure you want to delete "${list['title']}"?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true), 
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) _deleteChecklist(list['id']);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withOpacity(0.8),
                            color,
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -20,
                            bottom: -20,
                            child: Icon(
                              icon,
                              size: 100,
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(icon, color: Colors.white, size: 24),
                                ),
                                Text(
                                  list['title'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChecklistDetailScreen extends StatefulWidget {
  final String checklistId;
  final String title;
  final Color color;

  const ChecklistDetailScreen({
    super.key,
    required this.checklistId,
    required this.title,
    required this.color,
  });

  @override
  State<ChecklistDetailScreen> createState() => _ChecklistDetailScreenState();
}

class _ChecklistDetailScreenState extends State<ChecklistDetailScreen> {
  final StorageService _storage = StorageService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _addItem(String text) async {
    await _storage.addChecklistItem(widget.checklistId, text);
  }

  Future<void> _toggleItem(String id, bool isChecked) async {
    await _storage.toggleChecklistItem(widget.checklistId, id, isChecked);
  }

  Future<void> _deleteItem(String id) async {
    await _storage.deleteChecklistItem(widget.checklistId, id);
  }

  Future<void> _resetList() async {
    await _storage.resetChecklistItems(widget.checklistId);
  }

  void _showAddItemDialog() {
    final TextEditingController _controller = TextEditingController();
    bool _isSaving = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Item', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Item Name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            _isSaving 
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    if (_controller.text.isNotEmpty) {
                      setDialogState(() => _isSaving = true);
                      try {
                        await _addItem(_controller.text);
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        setDialogState(() => _isSaving = false);
                      }
                    }
                  }, 
                  child: const Text('Add')
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _storage.getChecklistItemsStream(widget.checklistId),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          
          final sortedItems = List<Map<String, dynamic>>.from(items);
          sortedItems.sort((a, b) {
            final aChecked = a['isChecked'] == true || a['isChecked'] == 1;
            final bChecked = b['isChecked'] == true || b['isChecked'] == 1;
            if (aChecked == bChecked) return 0;
            return aChecked ? 1 : -1;
          });

          final total = sortedItems.length;
          final checkedCount = sortedItems.where((i) => i['isChecked'] == true || i['isChecked'] == 1).length;
          final progress = total == 0 ? 0.0 : checkedCount / total;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 180.0,
                floating: false,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  background: Hero(
                    tag: 'list_${widget.checklistId}',
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [widget.color.withOpacity(0.8), widget.color],
                        ),
                      ),
                      child: Center(
                        child: Opacity(
                          opacity: 0.1,
                          child: Icon(Icons.checklist, size: 100, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Reset List?'),
                          content: const Text('Uncheck all items in this list?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                          ],
                        ),
                      );
                      if (confirm == true) _resetList();
                    },
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            '$checkedCount / $total items',
                            style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(progress == 1.0 ? Colors.green : widget.color),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (sortedItems.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_task, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('Your list is empty', style: TextStyle(color: Colors.grey[500])),
                        TextButton(onPressed: _showAddItemDialog, child: const Text('Add an item')),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = sortedItems[index];
                      final isChecked = item['isChecked'] == true || item['isChecked'] == 1;
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Dismissible(
                          key: Key(item['id'].toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Colors.red[400],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _deleteItem(item['id']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CheckboxListTile(
                              value: isChecked,
                              onChanged: (val) => _toggleItem(item['id'], val ?? false),
                              activeColor: Colors.green,
                              checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              title: Text(
                                item['text'],
                                style: TextStyle(
                                  decoration: isChecked ? TextDecoration.lineThrough : null,
                                  color: isChecked ? Colors.grey : Colors.black87,
                                  fontWeight: isChecked ? FontWeight.normal : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: sortedItems.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        backgroundColor: widget.color,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
