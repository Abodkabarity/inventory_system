import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/theme/app_colors.dart';
import '../../app/bloc/app_bloc.dart';
import '../../app/bloc/app_event.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailC = TextEditingController();
  final passC = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _navigated = false;

  @override
  void dispose() {
    emailC.dispose();
    passC.dispose();
    super.dispose();
  }

  void onCheckBoxChanged(bool? value) {
    context.read<AuthBloc>().add(AuthTogglePasswordVisibility());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/background.png",
              fit: BoxFit.fill,
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15.r),
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  child: Card(
                    color: Colors.transparent,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: BlocConsumer<AuthBloc, AuthState>(
                        listener: (context, state) {
                          if (state.navToHome && !_navigated) {
                            _navigated = true;

                            final user =
                                sb.Supabase.instance.client.auth.currentUser;
                            debugPrint('AUTH USER (after login): ${user?.id}');

                            context.read<AppBloc>().add(const AppStarted());
                            context.read<AuthBloc>().add(AuthNavConsumed());
                            context.go('/');
                          }
                        },
                        builder: (context, state) {
                          final loading = state.isLoading;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 16),
                              LogInWidget(
                                title: 'Daily Order System',
                                emailController: emailC,
                                passwordController: passC,
                                onPressed: () {
                                  final email = emailC.text.trim();
                                  final pass = passC.text;

                                  context.read<AuthBloc>().add(
                                    AuthLoginSubmitted(email, pass),
                                  );
                                },
                                error: state.error,
                                formKey: _formKey,
                                onCheckBoxChanged: onCheckBoxChanged,
                                isObscure: state.isObscure,
                                isLoading: loading,
                              ),

                              const SizedBox(height: 16),
                              if (state.status == AuthStatus.failure)
                                Text(
                                  state.error ?? 'Login failed',
                                  style: const TextStyle(color: Colors.red),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LogInWidget extends StatelessWidget {
  const LogInWidget({
    super.key,
    required this.title,
    required this.emailController,
    required this.passwordController,
    required this.onPressed,
    required this.error,
    required this.formKey,
    required this.onCheckBoxChanged,
    required this.isObscure,
    required this.isLoading,
  });
  final String title;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final void Function() onPressed;
  final String? error;
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final void Function(bool?) onCheckBoxChanged;
  final bool isObscure;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: formKey,
        child: Column(
          children: [
            SizedBox(height: 10.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 25.h),
            LoginTextField(
              label: 'Email',
              isObscure: false,
              controller: emailController,
              icon: Icons.email,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Email is required";
                }

                final valid = RegExp(
                  r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$",
                ).hasMatch(value);

                if (!valid) {
                  return "Please enter a valid email";
                }

                return null;
              },

              errorText: error,
            ),
            LoginTextField(
              label: 'Password',
              isObscure: !isObscure,
              controller: passwordController,
              icon: Icons.lock,

              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Password is required";
                }
                return null;
              },
              errorText: error,
            ),

            CheckboxListTile(
              value: isObscure,
              activeColor: AppColors.secondaryColor,
              title: Padding(
                padding: EdgeInsets.only(left: 20.w),
                child: Text(
                  "Show Password",
                  style: TextStyle(fontSize: 16.sp, color: Colors.white),
                ),
              ),

              onChanged: onCheckBoxChanged,
            ),
            SizedBox(height: 15.h),
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
                borderRadius: BorderRadius.circular(30.r),
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,

                  colors: [AppColors.primaryColor, AppColors.secondaryColor],
                ),
              ),
              child: MaterialButton(
                minWidth: 300.w,
                height: 50.h,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30.r),
                ),
                onPressed: () {
                  if ((formKey.currentState?.validate() ?? false)) {
                    onPressed();
                  }
                },
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 25.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginTextField extends StatelessWidget {
  const LoginTextField({
    super.key,
    required this.label,
    required this.isObscure,
    required this.controller,
    required this.icon,
    required this.validator,
    required this.errorText,
  });
  final String label;
  final bool isObscure;
  final TextEditingController controller;
  final IconData icon;
  final String? errorText;
  final String? Function(String?) validator;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 15.w),
      child: TextFormField(
        controller: controller,
        obscureText: isObscure,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppColors.secondaryColor),
          filled: true,
          errorText: errorText,
          suffixIcon: Icon(icon, color: AppColors.secondaryColor),
          fillColor: Colors.white,
          errorStyle: TextStyle(color: Colors.red, fontSize: 14.sp),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.r),
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.r),
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.r),
            borderSide: BorderSide(color: AppColors.primaryColor),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.r),
            borderSide: BorderSide(color: AppColors.primaryColor),
          ),
        ),
      ),
    );
  }
}
