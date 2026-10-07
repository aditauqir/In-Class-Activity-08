import 'package:flutter/material.dart';
import 'database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  try {
    await helper.init();
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Could not open local storage. Restart the app and check the logs.',
          ),
        ),
      ),
    ));
    return;
  }
  runApp(DirectoryApp(helper: helper));
}

class DirectoryApp extends StatelessWidget {
  final DatabaseHelper helper;

  const DirectoryApp({super.key, required this.helper});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Festival Roster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: RosterScreen(helper: helper),
    );
  }
}

class RosterScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const RosterScreen({super.key, required this.helper});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  List<Map<String, dynamic>> _guests = [];
  int _guestCount = 0;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _readError;
  String? _statusMessage;
  bool _statusIsError = false;

  int? _selectedId;
  String? _nameError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _readError = null;
    });

    try {
      final rows = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();

      if (!mounted) return;
      setState(() {
        _guests = rows;
        _guestCount = count;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading roster: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _readError = 'Failed to load guests: $e';
        _isLoading = false;
      });
    }
  }

  bool _validateInput() {
    bool isValid = true;
    final trimmedName = _nameController.text.trim();
    final rawAge = _ageController.text.trim();

    if (trimmedName.isEmpty) {
      _nameError = 'Name cannot be blank';
      isValid = false;
    } else {
      _nameError = null;
    }

    final parsedAge = int.tryParse(rawAge);
    if (rawAge.isEmpty) {
      _ageError = 'Age is required';
      isValid = false;
    } else if (parsedAge == null) {
      _ageError = 'Age must be a valid whole number';
      isValid = false;
    } else if (parsedAge < 0 || parsedAge > 130) {
      _ageError = 'Age must be between 0 and 130 inclusive';
      isValid = false;
    } else {
      _ageError = null;
    }

    setState(() {});
    return isValid;
  }

  void _clearForm() {
    _nameController.clear();
    _ageController.clear();
    _selectedId = null;
    _nameError = null;
    _ageError = null;
  }

  Future<void> _saveGuest() async {
    if (_isBusy) return;

    if (!_validateInput()) {
      setState(() {
        _statusMessage = 'Validation failed. Check required fields.';
        _statusIsError = true;
      });
      return;
    }

    final name = _nameController.text.trim();
    final age = int.parse(_ageController.text.trim());

    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });

    bool writeSucceeded = false;
    int affectedOrInsertedId = 0;
    bool isUpdate = _selectedId != null;

    try {
      if (isUpdate) {
        final currentId = _selectedId!;
        final affected = await widget.helper.update({
          DatabaseHelper.columnId: currentId,
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });

        if (affected == 0) {
          if (!mounted) return;
          setState(() {
            _statusMessage = 'Guest #$currentId no longer exists.';
            _statusIsError = true;
            _clearForm();
          });
          await _loadData();
          return;
        }

        writeSucceeded = true;
        affectedOrInsertedId = affected;
      } else {
        final insertedId = await widget.helper.insert({
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });
        writeSucceeded = true;
        affectedOrInsertedId = insertedId;
      }
    } catch (e, stackTrace) {
      debugPrint('Database write error: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Write error: $e';
        _statusIsError = true;
      });
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }

    if (writeSucceeded) {
      _clearForm();

      try {
        final rows = await widget.helper.queryAllRows();
        final count = await widget.helper.queryRowCount();

        if (!mounted) return;
        setState(() {
          _guests = rows;
          _guestCount = count;
          _statusIsError = false;
          if (isUpdate) {
            _statusMessage =
                'Updated guest successfully (affected: $affectedOrInsertedId).';
          } else {
            _statusMessage =
                'Guest added successfully with ID #$affectedOrInsertedId.';
          }
        });
      } catch (e, stackTrace) {
        debugPrint('Refresh failed after save: $e\n$stackTrace');
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Saved, but refresh failed. Tap Refresh.';
          _statusIsError = true;
        });
      }
    }
  }

  void _startEdit(Map<String, dynamic> row) {
    if (_isBusy) return;
    setState(() {
      _selectedId = row[DatabaseHelper.columnId] as int;
      _nameController.text = row[DatabaseHelper.columnName]?.toString() ?? '';
      _ageController.text = row[DatabaseHelper.columnAge]?.toString() ?? '';
      _nameError = null;
      _ageError = null;
      _statusMessage = 'Editing guest #$_selectedId.';
      _statusIsError = false;
    });
  }

  void _cancelEdit() {
    if (_isBusy) return;
    setState(() {
      _clearForm();
      _statusMessage = 'Edit cancelled.';
      _statusIsError = false;
    });
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    if (_isBusy) return;

    final id = row[DatabaseHelper.columnId] as int;
    final name = row[DatabaseHelper.columnName]?.toString() ?? 'Guest';

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Guest?'),
        content: Text(
          'Are you sure you want to remove guest #$id ($name) from the roster?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Deletion of guest #$id cancelled.';
        _statusIsError = false;
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });

    bool deleteSucceeded = false;
    int affected = 0;

    try {
      affected = await widget.helper.delete(id);
      if (affected == 0) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Guest #$id no longer exists.';
          _statusIsError = true;
        });
        if (_selectedId == id) {
          _clearForm();
        }
        await _loadData();
        return;
      }

      deleteSucceeded = true;
      if (_selectedId == id) {
        _clearForm();
      }
    } catch (e, stackTrace) {
      debugPrint('Delete error: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Delete failed: $e';
        _statusIsError = true;
      });
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }

    if (deleteSucceeded) {
      try {
        final rows = await widget.helper.queryAllRows();
        final count = await widget.helper.queryRowCount();

        if (!mounted) return;
        setState(() {
          _guests = rows;
          _guestCount = count;
          _statusMessage =
              'Deleted guest #$id successfully (affected: $affected).';
          _statusIsError = false;
        });
      } catch (e, stackTrace) {
        debugPrint('Refresh failed after delete: $e\n$stackTrace');
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Deleted, but refresh failed. Tap Refresh.';
          _statusIsError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _selectedId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Festival Roster'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Roster',
            onPressed: _isBusy ? null : _loadData,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Input and Action Form Card
            Card(
              margin: const EdgeInsets.all(12.0),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEditing
                          ? 'Edit Guest #$_selectedId'
                          : 'Register New Guest',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      enabled: !_isBusy,
                      decoration: InputDecoration(
                        labelText: 'Guest Name',
                        hintText: 'e.g. River',
                        errorText: _nameError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ageController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Age (0 - 130)',
                        hintText: 'e.g. 21',
                        errorText: _ageError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: const Icon(Icons.cake),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: Icon(isEditing ? Icons.save : Icons.person_add),
                            label: Text(isEditing ? 'Save Changes' : 'Add Guest'),
                            onPressed: _isBusy ? null : _saveGuest,
                          ),
                        ),
                        if (isEditing) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel Edit'),
                            onPressed: _isBusy ? null : _cancelEdit,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Status feedback banner
            if (_statusMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12.0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 20,
                      color: _statusIsError
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _statusIsError
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Record Count Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Festival Guests',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Total Guests: $_guestCount',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Roster List or States (Loading / Error / Empty)
            Expanded(
              child: _buildRosterContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRosterContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading festival guests...'),
          ],
        ),
      );
    }

    if (_readError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _readError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _isBusy ? null : _loadData,
              ),
            ],
          ),
        ),
      );
    }

    if (_guests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.park_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 12),
              Text(
                'No festival guests yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Register attendees above to begin the festival roster.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      itemCount: _guests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final row = _guests[index];
        final id = row[DatabaseHelper.columnId] as int;
        final name = row[DatabaseHelper.columnName]?.toString() ?? '';
        final age = row[DatabaseHelper.columnAge]?.toString() ?? '';
        final isRowSelected = _selectedId == id;

        return Card(
          elevation: isRowSelected ? 3 : 1,
          color: isRowSelected
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isRowSelected
                ? BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : BorderSide.none,
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: Text(
                '#$id',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Age: $age  •  Database ID: $id'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit guest #$id',
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _isBusy ? null : () => _startEdit(row),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete guest #$id',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: _isBusy ? null : () => _confirmDelete(row),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
