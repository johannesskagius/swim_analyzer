import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/objects/user/coach.dart';
import 'package:swim_apps_shared/objects/user/swimmer.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

/// A page that allows a coach to create a new swimmer profile.
///
/// When a swimmer is successfully created, it pops the navigation stack
/// and returns `true`. Otherwise, it returns `false` or `null` on failure
/// or cancellation.
class AddSwimmerPage extends StatefulWidget {
  final Coach coach;

  const AddSwimmerPage({super.key, required this.coach});

  @override
  State<AddSwimmerPage> createState() => _AddSwimmerPageState();
}

class _AddSwimmerPageState extends State<AddSwimmerPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Handles the form submission to create a new swimmer profile in Firestore.
  Future<void> _createSwimmer() async {
    // First, validate the form fields to ensure they are not empty.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userRepo = Provider.of<UserRepository>(context, listen: false);
      String newSwimmerName = _nameController.text.trim();
      String newSwimmerEmail = _emailController.text.trim();

      Swimmer newSwimmer = await userRepo.createSwimmer(
          name: newSwimmerName,
          clubId: widget.coach.clubId,
          email: newSwimmerEmail);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newSwimmer.name} was added successfully.')),
        );
        // Pop the page and return `true` to signal success to the previous screen.
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add swimmer: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Swimmer'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the details for the new swimmer. This will create a profile under your coaching account.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Swimmer's Full Name",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter the swimmer's name.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Swimmer's Email (Optional)",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                // Email is optional, so no validator is strictly needed.
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _createSwimmer,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add Swimmer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
