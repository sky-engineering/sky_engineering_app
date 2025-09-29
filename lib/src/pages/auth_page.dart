import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/loading_overlay.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);
    LoadingOverlay.show(context, message: 'Signing in...');

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtl.text.trim(),
        password: _passwordCtl.text,
      );
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Sign-in failed');
    } catch (_) {
      _showError('Sign-in failed');
    } finally {
      if (mounted) {
        LoadingOverlay.hide(context);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);
    LoadingOverlay.show(context, message: 'Creating account...');

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtl.text.trim(),
        password: _passwordCtl.text,
      );
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Registration failed');
    } catch (_) {
      _showError('Registration failed');
    } finally {
      if (mounted) {
        LoadingOverlay.hide(context);
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sky Engineering — Sign In')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _emailCtl,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@company.com',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        v = v?.trim();
                        if (v == null || v.isEmpty) return 'Email required';
                        if (!v.contains('@') || !v.contains('.')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtl,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _signIn(),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password required';
                        if (v.length < 6) return 'Min 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _loading ? null : _signIn,
                            child: _loading
                                ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : _register,
                            child: const Text('Create Account'),
                          ),
                        ),
                      ],
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
}
