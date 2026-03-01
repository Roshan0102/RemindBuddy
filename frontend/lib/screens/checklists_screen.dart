
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';

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

  Future<void> _createChecklist(String title, int iconCode, int color) async {
    await _storage.createChecklist(title, iconCode, color);
    _loadChecklists();
    try { SyncService(AuthService().pb).syncChecklists(); } catch (e) {}
  }

  Future<void> _deleteChecklist(int id) async {
    await _storage.deleteChecklist(id);
    _loadChecklists();
    try { SyncService(AuthService().pb).syncDeletions(); } catch (e) {}
  }

  void _showAddDialog() {
    final TextEditingController _controller = TextEditingController();
    int _selectedIcon = Icons.list.codePoint;
    int _selectedColor = Colors.blue.value;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('New Packing List'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(labelText: 'List Name (e.g., Office, Travel)'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Icon:'),
                  SizedBox(
                    height: 50,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Icons.work, Icons.flight_takeoff, Icons.school, Icons.fitness_center, Icons.shopping_bag
                      ].map((icon) => IconButton(
                        icon: Icon(icon, color: _selectedIcon == icon.codePoint ? Color(_selectedColor) : Colors.grey),
                        onPressed: () => setState(() => _selectedIcon = icon.codePoint),
                      )).toList(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_controller.text.isNotEmpty) {
                      _createChecklist(_controller.text, _selectedIcon, _selectedColor);
                      Navigator.pop(context);
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

  // Helper function to get IconData from code point
  IconData _getIconFromCode(int? code) {
    if (code == null) return Icons.list;
    
    // Map common icon codes to their IconData
    final iconMap = {
      Icons.work.codePoint: Icons.work,
      Icons.flight_takeoff.codePoint: Icons.flight_takeoff,
      Icons.school.codePoint: Icons.school,
      Icons.fitness_center.codePoint: Icons.fitness_center,
      Icons.shopping_bag.codePoint: Icons.shopping_bag,
      Icons.list.codePoint: Icons.list,
    };
    
    return iconMap[code] ?? Icons.list;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Belongings Lists'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _checklists.isEmpty
          ? const Center(child: Text('No lists yet. Add one!'))
          : ListView.builder(
              itemCount: _checklists.length,
              itemBuilder: (context, index) {
                final list = _checklists[index];
                final color = Color(list['color'] ?? Colors.blue.value);
                final icon = _getIconFromCode(list['iconCode']);


                return Dismissible(
                  key: Key(list['id'].toString()),
                  background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) => _deleteChecklist(list['id']),
                  confirmDismiss: (_) async => await showDialog(
                    context: context, 
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete List?'), 
                      content: const Text('This will delete all items in the list.'),
                      actions: [
                        TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text('Delete')),
                      ]
                    )
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.1),
                      child: Icon(icon, color: color),
                    ),
                    title: Text(list['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChecklistDetailScreen(
                            checklistId: list['id'],
                            title: list['title'],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class ChecklistDetailScreen extends StatefulWidget {
  final int checklistId;
  final String title;

  const ChecklistDetailScreen({
    super.key,
    required this.checklistId,
    required this.title,
  });

  @override
  State<ChecklistDetailScreen> createState() => _ChecklistDetailScreenState();
}

class _ChecklistDetailScreenState extends State<ChecklistDetailScreen> {
  final StorageService _storage = StorageService();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await _storage.getChecklistItems(widget.checklistId);
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _addItem(String text) async {
    await _storage.addChecklistItem(widget.checklistId, text);
    _loadItems();
    try { SyncService(AuthService().pb).syncChecklists(); } catch (e) {}
  }

  Future<void> _toggleItem(int id, bool isChecked) async {
    await _storage.toggleChecklistItem(id, isChecked);
    _loadItems();
    try { SyncService(AuthService().pb).syncChecklists(); } catch (e) {}
  }

  Future<void> _deleteItem(int id) async {
    await _storage.deleteChecklistItem(id);
    _loadItems();
    try { SyncService(AuthService().pb).syncDeletions(); } catch (e) {}
  }

  Future<void> _resetList() async {
    await _storage.resetChecklistItems(widget.checklistId);
    _loadItems();
    try { SyncService(AuthService().pb).syncChecklists(); } catch (e) {}
  }

  void _showAddItemDialog() {
    final TextEditingController _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Item'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Item Name'),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (_controller.text.isNotEmpty) {
                _addItem(_controller.text);
                Navigator.pop(context);
              }
            }, 
            child: const Text('Add')
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sort: Unchecked first, then Checked
    final sortedItems = List<Map<String, dynamic>>.from(_items);
    sortedItems.sort((a, b) {
      if (a['isChecked'] == b['isChecked']) return 0;
      return a['isChecked'] == 1 ? 1 : -1;
    });

    final total = sortedItems.length;
    final checked = sortedItems.where((i) => i['isChecked'] == 1).length;
    final progress = total == 0 ? 0.0 : checked / total;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset All',
            onPressed: () async {
               final confirm = await showDialog<bool>(
                 context: context,
                 builder: (ctx) => AlertDialog(
                   title: const Text('Reset List?'),
                   content: const Text('Uncheck all items?'),
                   actions: [
                      TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text('No')),
                      TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text('Yes')),
                   ]
                 )
               );
               if (confirm == true) _resetList();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
           if (total > 0)
             LinearProgressIndicator(
               value: progress, 
               backgroundColor: Colors.grey[200],
               valueColor: AlwaysStoppedAnimation<Color>(progress == 1.0 ? Colors.green : Colors.blue),
               minHeight: 6,
             ),
             
           Expanded(
             child: _isLoading 
               ? const Center(child: CircularProgressIndicator())
               : sortedItems.isEmpty
                 ? Center(
                     child: Column(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         Icon(Icons.checklist, size: 60, color: Colors.grey[300]),
                         const SizedBox(height: 16),
                         Text('Add items to your ${widget.title} list!', style: TextStyle(color: Colors.grey[500])),
                       ],
                     ),
                   )
                 : ListView.builder(
                     itemCount: sortedItems.length,
                     itemBuilder: (context, index) {
                       final item = sortedItems[index];
                       final isChecked = item['isChecked'] == 1;
                       
                       return Dismissible(
                         key: Key(item['id'].toString()),
                         background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                         onDismissed: (_) => _deleteItem(item['id']),
                         child: Column(
                           children: [
                             CheckboxListTile(
                               value: isChecked,
                               onChanged: (val) => _toggleItem(item['id'], val ?? false),
                               title: Text(
                                 item['text'],
                                 style: TextStyle(
                                   decoration: isChecked ? TextDecoration.lineThrough : null,
                                   color: isChecked ? Colors.grey : Colors.black,
                                 ),
                               ),
                               activeColor: Colors.green,
                             ),
                             const Divider(height: 1),
                           ],
                         ),
                       );
                     },
                   ),
           ),
        ],
      ),
    );
  }
}
