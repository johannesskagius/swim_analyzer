import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/objects/user/swimmer.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/objects/user/user_types.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class ProfilePage extends StatefulWidget {
  final AppUser appUser;

  const ProfilePage({super.key, required this.appUser});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

// Helper class for displaying personal bests.
class _PersonalBest {
  final String eventName;
  final Duration time;

  _PersonalBest(this.eventName, this.time);
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _lastNameController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditMode = false;
  String _initialError = '';
  AppUser? _user;

  // State for personal bests
  bool _isLoadingBests = false;
  final List<_PersonalBest> _personalBests = [];

  String get _userRole {
    if (_user == null) return '';
    final name = _user!.userType.name;
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _lastNameController = TextEditingController();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = widget.appUser;
      if (mounted) {
        setState(() {
          _user = user;
          _nameController.text = user.name;
          _lastNameController.text = user.lastName ?? '';
          _isLoading = false;
        });
        // If the user is a swimmer, kick off loading their personal bests.
        if (user is Swimmer) {
          //_loadPersonalBests(user);
        }
      } else if (mounted) {
        setState(() {
          _initialError = 'Could not load user profile.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialError = 'Error: \${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  // Updated method to fetch and load real personal bests for a swimmer.
  // Future<void> _loadPersonalBests(Swimmer swimmer) async {
  //   final mainEvents = swimmer.mainEventIds;
  //   if (mainEvents.isEmpty) {
  //     return;
  //   }
  //
  //   if (mounted) setState(() => _isLoadingBests = true);
  //
  //   try {
  //     final analyzesRepo = Provider.of<AnalyzesRepository>(context, listen: false);
  //     final bestsMap = await analyzesRepo.getPersonalBests(swimmer.id, mainEvents);
  //
  //     final personalBestsData = bestsMap.entries.map((entry) {
  //       return _PersonalBest(entry.key, entry.value);
  //     }).toList();
  //
  //     // Sort by event name for a consistent display order.
  //     personalBestsData.sort((a, b) => a.eventName.compareTo(b.eventName));
  //
  //     if (mounted) {
  //       setState(() {
  //         _personalBests.clear();
  //         _personalBests.addAll(personalBestsData);
  //         _isLoadingBests = false;
  //       });
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Could not load personal bests: \${e.toString()}'),
  //           backgroundColor: Theme.of(context).colorScheme.error,
  //         ),
  //       );
  //       setState(() => _isLoadingBests = false);
  //     }
  //   }
  // }

  void _enterEditMode() {
    setState(() => _isEditMode = true);
  }

  void _cancelEdit() {
    _nameController.text = _user?.name ?? '';
    _lastNameController.text = _user?.lastName ?? '';
    setState(() => _isEditMode = false);
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final userRepo = Provider.of<UserRepository>(context, listen: false);
    try {
      final updatedUser = _user!.copyWith(
        name: _nameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );

      await userRepo.updateUser(updatedUser);

      if (mounted) {
        setState(() {
          _user = updatedUser;
          _isEditMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: \${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Profile' : 'Profile'),
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_isSaving) {
      return [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: Colors.white)),
        ),
      ];
    }
    if (_isEditMode) {
      return [
        IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _cancelEdit),
        IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _saveProfile),
      ];
    } else {
      return [
        IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Profile',
            onPressed: _enterEditMode),
      ];
    }
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_initialError.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_initialError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center),
        ),
      );
    }
    return _isEditMode ? _buildEditView() : _buildReadView();
  }

  Widget _buildReadView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
          const SizedBox(height: 16),
          if (_user != null)
            Center(
              child: Chip(
                avatar: Icon(
                  _user!.userType == UserType.coach
                      ? Icons.admin_panel_settings_outlined
                      : Icons.pool,
                  color: Theme.of(context).primaryColor,
                ),
                label: Text(_userRole,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          const SizedBox(height: 24),
          _buildProfileInfoTile(
              icon: Icons.person_outline,
              label: 'First Name',
              value: _user?.name ?? 'N/A'),
          const SizedBox(height: 16),
          _buildProfileInfoTile(
              icon: Icons.person_outline,
              label: 'Last Name',
              value: _user?.lastName ?? 'N/A'),
          const SizedBox(height: 16),
          _buildProfileInfoTile(
              icon: Icons.email_outlined,
              label: 'Email',
              value: _user?.email ?? 'N/A'),

          // --- SECTION FOR SWIMMER PERSONAL BESTS ---
          // if (_user is Swimmer) ...[
          //   const SizedBox(height: 24),
          //   Padding(
          //     padding: const EdgeInsets.only(left: 4.0),
          //     child: Text('Personal Bests', style: Theme.of(context).textTheme.headlineSmall),
          //   ),
          //   const SizedBox(height: 8),
          //   _isLoadingBests
          //       ? const Center(child: CircularProgressIndicator())
          //       : _personalBests.isEmpty
          //           ? const Card(child: ListTile(title: Text('No main events configured.')))
          //           : Card(
          //               clipBehavior: Clip.antiAlias,
          //               child: ListView.separated(
          //                 shrinkWrap: true,
          //                 physics: const NeverScrollableScrollPhysics(),
          //                 itemCount: _personalBests.length,
          //                 itemBuilder: (context, index) {
          //                   final best = _personalBests[index];
          //                   final timeString =
          //                       '\${best.time.inMinutes}:${(best.time.inSeconds % 60).toString().padLeft(2, '0')}.\${(best.time.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2)}';
          //                   return ListTile(
          //                     leading: const Icon(Icons.star, color: Colors.amber),
          //                     title: Text(best.eventName, style: const TextStyle(fontWeight: FontWeight.w500)),
          //                     trailing: Text(
          //                       timeString,
          //                       style: const TextStyle(
          //                         fontSize: 16,
          //                         fontWeight: FontWeight.bold,
          //                         fontFamily: 'monospace',
          //                       ),
          //                     ),
          //                   );
          //                 },
          //                 separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
          //               ),
          //             ),
          // ],
        ],
      ),
    );
  }

  Widget _buildProfileInfoTile(
      {required IconData icon, required String label, required String value}) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(label),
        subtitle: Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEditView() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 32),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: 'First Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline)),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Please enter your first name'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                  labelText: 'Last Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline)),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Please enter your last name'
                  : null,
            ),
            const SizedBox(height: 24),
            TextFormField(
              initialValue: _user?.email,
              readOnly: true,
              decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                  fillColor: Colors.black12,
                  filled: true),
            ),
          ],
        ),
      ),
    );
  }
}
