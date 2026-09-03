import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/datasources/remote/insurance_assistant_remote_ds.dart';
import '../../../data/repositories/insurance_assistant_repository_impl.dart';
import '../../../core/utils/insurance_conversation_pdf_exporter.dart';
import '../../../domain/entities/insurance_assistant_models.dart';
import '../../../domain/repositories/insurance_assistant_repository.dart';

class InsuranceAssistantPage extends StatefulWidget {
  final String branchName;
  final VoidCallback onBack;
  final InsuranceAssistantRepository? repository;

  const InsuranceAssistantPage({
    super.key,
    required this.branchName,
    required this.onBack,
    this.repository,
  });

  @override
  State<InsuranceAssistantPage> createState() => _InsuranceAssistantPageState();
}

class _InsuranceAssistantPageState extends State<InsuranceAssistantPage> {
  late final InsuranceAssistantRepository _repository;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  List<InsuranceChatSession> _sessions = const [];
  List<InsuranceChatMessage> _messages = const [];
  String? _sessionId;
  InsuranceCitation? _selectedCitation;
  bool _loading = true;
  bool _sending = false;
  bool _exporting = false;
  bool _canManage = false;
  String? _error;
  int _sessionLoadGeneration = 0;
  final Set<String> _confirmedClarifications = {};

  static const _suggestions = [
    (
      'CGRP coverage',
      'What are the coverage conditions for CGRP inhibitors?',
      Icons.verified_user_rounded,
    ),
    (
      'Dose check',
      'What is the maximum dose of Ubrogepant?',
      Icons.medication_liquid_rounded,
    ),
    (
      'Age eligibility',
      'Is CGRP covered for a 16-year-old patient?',
      Icons.badge_outlined,
    ),
    (
      'GLP-1 documents',
      'What documentation is required for the initial GLP-1 dose?',
      Icons.description_outlined,
    ),
    (
      'سؤال بالعربية',
      'ما شروط صرف أدوية CGRP وهل تحتاج موافقة؟',
      Icons.translate_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        InsuranceAssistantRepositoryImpl(
          InsuranceAssistantRemoteDs(Supabase.instance.client),
        );
    _loadWorkspace();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadWorkspace() async {
    try {
      final results = await Future.wait([
        _repository.fetchSessions(),
        _repository.canManageDocuments(),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<InsuranceChatSession>;
        _canManage = results[1] as bool;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _openSession(InsuranceChatSession session) async {
    if (_sending) return;
    final generation = ++_sessionLoadGeneration;
    setState(() {
      _sessionId = session.id;
      _messages = const [];
      _selectedCitation = null;
      _loading = true;
    });
    try {
      final messages = await _repository.fetchMessages(session.id);
      if (!mounted || generation != _sessionLoadGeneration) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted || generation != _sessionLoadGeneration) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _newConversation() {
    if (_sending) return;
    _sessionLoadGeneration++;
    setState(() {
      _sessionId = null;
      _messages = const [];
      _selectedCitation = null;
      _error = null;
    });
    _focusNode.requestFocus();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    final question = (suggestedQuestion ?? _messageController.text).trim();
    if (question.isEmpty || _sending) return;
    _messageController.clear();
    final optimistic = InsuranceChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      message: question,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, optimistic];
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final result = await _repository.ask(
        question: question,
        branchName: widget.branchName,
        sessionId: _sessionId,
        debug: _canManage,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId;
        _messages = [..._messages, result.message];
        _sending = false;
        if (result.message.citations.isNotEmpty) {
          _selectedCitation = result.message.citations.first;
        }
      });
      unawaited(_refreshSessions());
      _scrollToBottom();
      _focusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendlyError(error);
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _confirmClarification(
    InsuranceClarification clarification,
    InsuranceClarificationCandidate candidate,
  ) async {
    if (_sending || _confirmedClarifications.contains(clarification.id)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final result = await _repository.confirmClarification(
        clarificationId: clarification.id,
        candidateId: candidate.id,
        branchName: widget.branchName,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId;
        _messages = [..._messages, result.message];
        _confirmedClarifications.add(clarification.id);
        _sending = false;
        if (result.message.citations.isNotEmpty) {
          _selectedCitation = result.message.citations.first;
        }
      });
      unawaited(_refreshSessions());
      _scrollToBottom();
      _focusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendlyError(error);
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _refreshSessions() async {
    try {
      final sessions = await _repository.fetchSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {}
  }

  Set<String> _previousAnswerIds() {
    final previous = <String>{};
    for (final message in _messages) {
      final recoveryOf = message.recoveryOfMessageId;
      if (!message.isUser && recoveryOf != null && recoveryOf.isNotEmpty) {
        previous.add(recoveryOf);
      }
    }
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      if (message.isUser ||
          message.recoveryDepth < 1 ||
          message.recoveryOfMessageId != null) {
        continue;
      }
      for (
        var candidateIndex = index - 1;
        candidateIndex >= 0;
        candidateIndex--
      ) {
        final candidate = _messages[candidateIndex];
        if (!candidate.isUser &&
            candidate.recoveryDepth == 0 &&
            !candidate.conversational) {
          previous.add(candidate.id);
          break;
        }
      }
    }
    return previous;
  }

  Future<void> _handleFeedback(
    InsuranceChatMessage message,
    int rating, {
    String? recoveryReason,
  }) async {
    if (_sending) return;
    if (rating > 0) {
      await _repository.submitFeedback(message.id, 1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for the feedback.')),
        );
      }
      return;
    }
    final deepReview = message.recoveryDepth > 0;
    final reason =
        recoveryReason ??
        await showDialog<String>(
          context: context,
          builder: (_) => const _FeedbackReasonDialog(),
        );
    if (reason == null || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    // The recovery indicator is appended to the list. Move to it immediately
    // so users can see that the deeper evidence search has started.
    _scrollToBottom();
    try {
      final recovered = await _repository.recoverFromFeedback(
        messageId: message.id,
        reason: reason,
        branchName: widget.branchName,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (recovered != null) {
          _messages = [..._messages, recovered];
          if (recovered.citations.isNotEmpty) {
            _selectedCitation = recovered.citations.first;
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deepReview
                ? 'Thanks — this case was flagged for review.'
                : recovered == null
                ? 'The case was recorded for review; no further automatic retry will run.'
                : 'Deep Review completed using the approved documents.',
          ),
        ),
      );
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Exception: ', '');
    if (value.contains('[object Object]')) {
      return 'The request could not be completed. Please retry.';
    }
    if (value.contains('insurance_documents') ||
        value.contains('is_insurance_knowledge') ||
        value.contains('insurance-assistant') ||
        value.contains('insurance-policy-v2')) {
      return 'Insurance Knowledge backend is not deployed yet. Apply the policy migration and deploy the Insurance Policy V2 function, then retry.';
    }
    return value;
  }

  Future<void> _openCitation(InsuranceCitation citation) async {
    try {
      final url = await _repository.createSourceUrl(citation);
      final launched = await launchUrl(
        Uri.parse(url),
        webOnlyWindowName: '_blank',
      );
      if (!launched) {
        throw Exception('The source document could not be opened.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  Future<void> _showDocuments() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DocumentCenterDialog(repository: _repository),
    );
  }

  Future<void> _exportConversation() async {
    if (_messages.isEmpty || _exporting) return;
    String? title;
    for (final session in _sessions) {
      if (session.id == _sessionId) {
        title = session.title;
        break;
      }
    }
    setState(() => _exporting = true);
    try {
      await InsuranceConversationPdfExporter.export(
        messages: _messages,
        branchName: widget.branchName,
        conversationTitle: title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation PDF is ready to save or share.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not export conversation: ${_friendlyError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSessions = constraints.maxWidth >= 1040;
        final showEvidence = constraints.maxWidth >= 1320;
        return ColoredBox(
          color: const Color(0xFFF4F7FB),
          child: Column(
            children: [
              _AssistantHeader(
                branchName: widget.branchName,
                canManage: _canManage,
                onBack: widget.onBack,
                onNewConversation: _newConversation,
                onDocuments: _showDocuments,
                onExport: _exportConversation,
                exportEnabled: _messages.isNotEmpty && !_sending,
                exporting: _exporting,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSessions) ...[
                        SizedBox(
                          width: 260,
                          child: _SessionsPanel(
                            sessions: _sessions,
                            selectedId: _sessionId,
                            onSelect: _openSession,
                            onNew: _newConversation,
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(child: _buildConversation(showEvidence)),
                      if (showEvidence) ...[
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 330,
                          child: _EvidencePanel(
                            citation: _selectedCitation,
                            onOpen: _openCitation,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConversation(bool evidenceBesideChat) {
    final previousAnswerIds = _previousAnswerIds();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE7F1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: .05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _ConversationStatus(
            documentCountLabel: 'Source-grounded • Arabic + English',
          ),
          if (_error != null)
            _ErrorBanner(message: _error!, onRetry: _loadWorkspace),
          Expanded(
            child: SelectionArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? _WelcomeView(suggestions: _suggestions, onAsk: _send)
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 20),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const _ThinkingBubble();
                        }
                        final message = _messages[index];
                        return _MessageBubble(
                          message: message,
                          previousAnswer: previousAnswerIds.contains(
                            message.id,
                          ),
                          selectedCitation: _selectedCitation,
                          onCitationTap: (citation) {
                            setState(() => _selectedCitation = citation);
                            if (!evidenceBesideChat) {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => FractionallySizedBox(
                                  heightFactor: .72,
                                  child: _EvidencePanel(
                                    citation: citation,
                                    onOpen: _openCitation,
                                  ),
                                ),
                              );
                            }
                          },
                          onFeedback: message.isUser || _sending
                              ? null
                              : (rating) =>
                                    unawaited(_handleFeedback(message, rating)),
                          onRecoveryFeedback: message.isUser || _sending
                              ? null
                              : (reason) => unawaited(
                                  _handleFeedback(
                                    message,
                                    -1,
                                    recoveryReason: reason,
                                  ),
                                ),
                          clarificationEnabled:
                              message.clarification != null &&
                              !_confirmedClarifications.contains(
                                message.clarification!.id,
                              ) &&
                              !_sending,
                          onClarificationSelected: (candidate) {
                            final clarification = message.clarification;
                            if (clarification != null) {
                              unawaited(
                                _confirmClarification(clarification, candidate),
                              );
                            }
                          },
                          showDeveloperDebug: _canManage,
                        );
                      },
                    ),
            ),
          ),
          _Composer(
            controller: _messageController,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  final String branchName;
  final bool canManage;
  final VoidCallback onBack;
  final VoidCallback onNewConversation;
  final VoidCallback onDocuments;
  final VoidCallback onExport;
  final bool exportEnabled;
  final bool exporting;

  const _AssistantHeader({
    required this.branchName,
    required this.canManage,
    required this.onBack,
    required this.onNewConversation,
    required this.onDocuments,
    required this.onExport,
    required this.exportEnabled,
    required this.exporting,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Back to orders',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 9),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6D5DFB), Color(0xFF0EA5E9)],
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Insurance Knowledge Assistant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (canManage)
                        IconButton.filledTonal(
                          tooltip: 'Knowledge Library',
                          onPressed: onDocuments,
                          icon: const Icon(Icons.folder_copy_outlined),
                        ),
                      IconButton.filledTonal(
                        tooltip: exporting ? 'Preparing export' : 'Export PDF',
                        onPressed: exportEnabled && !exporting
                            ? onExport
                            : null,
                        icon: exporting
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                      ),
                      IconButton.filled(
                        tooltip: 'New chat',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF5B55E7),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onNewConversation,
                        icon: const Icon(Icons.add_comment_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Back to orders',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6D5DFB), Color(0xFF0EA5E9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6D5DFB).withValues(alpha: .25),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Insurance Knowledge Assistant',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$branchName • Clinical & coverage intelligence',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                OutlinedButton.icon(
                  onPressed: onDocuments,
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('Knowledge Library'),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton.icon(
                onPressed: exportEnabled && !exporting ? onExport : null,
                icon: exporting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(exporting ? 'Preparing…' : 'Export PDF'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onNewConversation,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5B55E7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                ),
                icon: const Icon(Icons.add_comment_rounded),
                label: const Text('New chat'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionsPanel extends StatelessWidget {
  final List<InsuranceChatSession> sessions;
  final String? selectedId;
  final ValueChanged<InsuranceChatSession> onSelect;
  final VoidCallback onNew;

  const _SessionsPanel({
    required this.sessions,
    required this.selectedId,
    required this.onSelect,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE7F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'RECENT CHATS',
                    style: TextStyle(
                      fontSize: 11.5,
                      letterSpacing: .8,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  tooltip: 'New chat',
                ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Your evidence-backed conversations will appear here.',
                      style: TextStyle(color: Color(0xFF94A3B8), height: 1.45),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                    itemCount: sessions.length,
                    itemBuilder: (_, index) {
                      final session = sessions[index];
                      final selected = session.id == selectedId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: selected
                              ? const Color(0xFFEEF2FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            selected: selected,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 5,
                            ),
                            leading: Icon(
                              selected
                                  ? Icons.chat_bubble_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              size: 20,
                              color: selected
                                  ? const Color(0xFF5B55E7)
                                  : const Color(0xFF94A3B8),
                            ),
                            title: Text(
                              session.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF4338CA)
                                    : const Color(0xFF1E293B),
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                DateFormat(
                                  'dd MMM · HH:mm',
                                ).format(session.updatedAt.toLocal()),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            onTap: () => onSelect(session),
                          ),
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

class _ConversationStatus extends StatelessWidget {
  final String documentCountLabel;
  const _ConversationStatus({required this.documentCountLabel});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 540;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE8EEF5))),
          ),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  documentCountLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.shield_outlined,
                  size: 17,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Private knowledge base',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WelcomeView extends StatelessWidget {
  final List<(String, String, IconData)> suggestions;
  final ValueChanged<String> onAsk;
  const _WelcomeView({required this.suggestions, required this.onAsk});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 36),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFE0F2FE)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: Color(0xFF5B55E7),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ask. Verify. Dispense with confidence.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 670),
            child: const Text(
              'Search coverage rules, doses, age limits, required documents and prescriber criteria. Every answer stays linked to its exact source.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: suggestions
                .map(
                  (suggestion) => ActionChip(
                    avatar: Icon(
                      suggestion.$3,
                      size: 18,
                      color: const Color(0xFF5B55E7),
                    ),
                    label: Text(suggestion.$1),
                    side: const BorderSide(color: Color(0xFFD9E1F2)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    onPressed: () => onAsk(suggestion.$2),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 26),
          Container(
            constraints: const BoxConstraints(maxWidth: 700),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.fact_check_outlined, color: Color(0xFFD97706)),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'The assistant will say when evidence is insufficient. Always open the cited guideline before a final adjudication decision.',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackReasonDialog extends StatelessWidget {
  const _FeedbackReasonDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.rate_review_rounded,
                        color: Color(0xFF4F46E5),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'What should I improve?',
                        style: TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Choose the closest reason so I can re-check the approved documents.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                _FeedbackReasonOption(
                  value: 'incorrect',
                  icon: Icons.cancel_outlined,
                  title: 'Incorrect',
                  description: 'The answer appears wrong',
                ),
                const SizedBox(height: 9),
                _FeedbackReasonOption(
                  value: 'incomplete',
                  icon: Icons.note_alt_outlined,
                  title: 'Incomplete',
                  description: 'The answer is missing important information',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackReasonOption extends StatelessWidget {
  final String value;
  final IconData icon;
  final String title;
  final String description;

  const _FeedbackReasonOption({
    required this.value,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        hoverColor: const Color(0xFFEEF2FF),
        splashColor: const Color(0xFFC7D2FE),
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E7FF)),
          ),
          child: Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFDDE5F8)),
                ),
                child: Icon(icon, size: 19, color: const Color(0xFF4F46E5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final InsuranceChatMessage message;
  final bool previousAnswer;
  final InsuranceCitation? selectedCitation;
  final ValueChanged<InsuranceCitation> onCitationTap;
  final ValueChanged<int>? onFeedback;
  final ValueChanged<String>? onRecoveryFeedback;
  final bool clarificationEnabled;
  final ValueChanged<InsuranceClarificationCandidate> onClarificationSelected;
  final bool showDeveloperDebug;

  const _MessageBubble({
    required this.message,
    required this.previousAnswer,
    required this.selectedCitation,
    required this.onCitationTap,
    required this.onFeedback,
    required this.onRecoveryFeedback,
    required this.clarificationEnabled,
    required this.onClarificationSelected,
    required this.showDeveloperDebug,
  });

  String _debugText() =>
      const JsonEncoder.withIndent('  ').convert(message.debugTrace);

  List<InlineSpan> _answerSpans(String value, TextStyle style) {
    final spans = <InlineSpan>[];
    final bold = RegExp(r'\*\*(.+?)\*\*');
    var cursor = 0;
    for (final match in bold.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: style.copyWith(fontWeight: FontWeight.w900),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }

  ({String answer, String? source}) _separateAnswerAndSource() {
    final value = message.message.trim();
    final sourceMarker = RegExp(
      r'\n\s*Source\s*\n',
      caseSensitive: false,
    ).firstMatch(value);
    if (sourceMarker == null) return (answer: value, source: null);
    final answer = value.substring(0, sourceMarker.start).trim();
    final source = value.substring(sourceMarker.end).trim();
    return (answer: answer, source: source.isEmpty ? null : source);
  }

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    final content = _separateAnswerAndSource();
    final arabic = RegExp(
      r'[\u0600-\u06FF]',
    ).hasMatch(message.answerCard?.summary ?? content.answer);
    final deepReview = !user && message.recoveryDepth > 0;
    final secondaryAnswer = !user && previousAnswer;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final assistantSurface = deepReview
        ? const Color(0xFFF7F5FF)
        : secondaryAnswer
        ? const Color(0xFFF8FAFC)
        : const Color(0xFFF5F7FF);
    final assistantBorder = deepReview
        ? const Color(0xFFD8CCFF)
        : secondaryAnswer
        ? const Color(0xFFE2E8F0)
        : const Color(0xFFD8E1FF);
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: user ? 660 : 900),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: user
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!user && !compact) ...[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: deepReview
                        ? const [Color(0xFF7C3AED), Color(0xFF6366F1)]
                        : const [Color(0xFF5B55E7), Color(0xFF3B82F6)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5B55E7).withValues(alpha: .22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Container(
                padding: EdgeInsets.all(user ? 17 : 18),
                decoration: BoxDecoration(
                  gradient: user
                      ? const LinearGradient(
                          colors: [Color(0xFF5B55E7), Color(0xFF3B82F6)],
                        )
                      : null,
                  color: user ? null : assistantSurface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(user ? 18 : 7),
                    bottomRight: Radius.circular(user ? 5 : 18),
                  ),
                  border: user ? null : Border.all(color: assistantBorder),
                  boxShadow: user
                      ? null
                      : [
                          BoxShadow(
                            color: const Color(
                              0xFF312E81,
                            ).withValues(alpha: .07),
                            blurRadius: 24,
                            offset: const Offset(0, 9),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!user) ...[
                      Row(
                        children: [
                          _AnswerKindBadge(
                            deepReview: deepReview,
                            previousAnswer: secondaryAnswer,
                            arabic: arabic,
                          ),
                          if (message.aiGenerated && !compact) ...[
                            const SizedBox(width: 7),
                            _AiBadge(generator: message.answerGenerator),
                          ],
                          if (!compact && message.answerStatus != 'legacy') ...[
                            const SizedBox(width: 7),
                            _AnswerStatusBadge(
                              status: message.answerStatus,
                              arabic: arabic,
                            ),
                          ],
                          const Spacer(),
                          if (message.evidenceChecked &&
                              !compact &&
                              message.answerCard?.presentation == null)
                            _EvidenceBadge(arabic: arabic),
                        ],
                      ),
                      if (deepReview) ...[
                        const SizedBox(height: 8),
                        Text(
                          arabic
                              ? 'أُعيد التحقق من الوثائق المعتمدة بعد ملاحظتك'
                              : 'Re-checked across approved documents after your feedback',
                          textDirection: arabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: const TextStyle(
                            color: Color(0xFF6D5AA7),
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 13),
                    ],
                    if (!user &&
                        !message.conversational &&
                        message.answerCard != null)
                      _AnswerCardRenderer(
                        card: message.answerCard!,
                        citations: message.citations,
                        arabic: arabic,
                        onCitationTap: onCitationTap,
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(user ? 0 : 17),
                        decoration: user
                            ? null
                            : BoxDecoration(
                                color: secondaryAnswer
                                    ? const Color(0xFFFCFDFE)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: deepReview
                                      ? const Color(0xFFE0D7FF)
                                      : secondaryAnswer
                                      ? const Color(0xFFE8EDF3)
                                      : const Color(0xFFE1E7F5),
                                ),
                              ),
                        child: Directionality(
                          textDirection: arabic
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Text.rich(
                            TextSpan(
                              children: _answerSpans(
                                content.answer,
                                TextStyle(
                                  color: user
                                      ? Colors.white
                                      : secondaryAnswer
                                      ? const Color(0xFF475569)
                                      : const Color(0xFF172033),
                                  height: user ? 1.5 : 1.68,
                                  fontSize: user ? 14.5 : 16,
                                  fontWeight: user
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              color: user
                                  ? Colors.white
                                  : secondaryAnswer
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF172033),
                              height: user ? 1.5 : 1.68,
                              fontSize: user ? 14.5 : 16,
                              fontWeight: user
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    if (!user && message.clarification != null) ...[
                      const SizedBox(height: 13),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: message.clarification!.candidates
                            .map(
                              (candidate) => ActionChip(
                                avatar: const Icon(
                                  Icons.auto_fix_high_rounded,
                                  size: 17,
                                  color: Color(0xFF4F46E5),
                                ),
                                label: Text(
                                  candidate.canonicalName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF3730A3),
                                  ),
                                ),
                                backgroundColor: const Color(0xFFEEF2FF),
                                side: const BorderSide(
                                  color: Color(0xFFA5B4FC),
                                ),
                                onPressed: clarificationEnabled
                                    ? () => onClarificationSelected(candidate)
                                    : null,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (!user &&
                        message.citations.isEmpty &&
                        content.source != null) ...[
                      const SizedBox(height: 12),
                      _InlineSource(source: content.source!),
                    ],
                    if (!user &&
                        message.citations.isNotEmpty &&
                        message.answerCard?.presentation == null) ...[
                      const SizedBox(height: 16),
                      _SourcesList(
                        citations: message.citations,
                        selectedCitation: selectedCitation,
                        arabic: arabic,
                        onCitationTap: onCitationTap,
                      ),
                    ],
                    if (!user &&
                        showDeveloperDebug &&
                        message.debugTrace != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: ExpansionTile(
                          leading: const Icon(
                            Icons.rule_folder_outlined,
                            color: Color(0xFF475569),
                          ),
                          title: const Text(
                            'Developer evidence trace',
                            style: TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Why candidates were accepted or rejected',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10.5,
                            ),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            14,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _debugText(),
                                style: const TextStyle(
                                  color: Color(0xFFE2E8F0),
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!user &&
                        !message.conversational &&
                        !secondaryAnswer &&
                        (onFeedback != null || onRecoveryFeedback != null)) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFDDE5F3)),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        children: [
                          Text(
                            deepReview
                                ? arabic
                                      ? 'هل كانت المراجعة المتعمقة مفيدة؟'
                                      : 'Was this deep review helpful?'
                                : arabic
                                ? 'هل كانت هذه الإجابة مفيدة؟'
                                : 'Was this answer helpful?',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            onPressed: onFeedback == null
                                ? null
                                : () => onFeedback!(1),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.thumb_up_alt_outlined,
                              size: 16,
                            ),
                            tooltip: arabic ? 'مفيد' : 'Useful',
                          ),
                          OutlinedButton.icon(
                            onPressed: onRecoveryFeedback == null
                                ? null
                                : () => onRecoveryFeedback!('incorrect'),
                            icon: const Icon(Icons.cancel_outlined, size: 15),
                            label: Text(arabic ? 'غير صحيحة' : 'Incorrect'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: const Color(0xFFB42318),
                              side: const BorderSide(color: Color(0xFFF3B5AF)),
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: onRecoveryFeedback == null
                                ? null
                                : () => onRecoveryFeedback!('incomplete'),
                            icon: const Icon(Icons.note_alt_outlined, size: 15),
                            label: Text(arabic ? 'غير مكتملة' : 'Incomplete'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: const Color(0xFF6D28D9),
                              side: const BorderSide(color: Color(0xFFD8B4FE)),
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerCardRenderer extends StatelessWidget {
  final InsuranceAnswerCard card;
  final List<InsuranceCitation> citations;
  final bool arabic;
  final ValueChanged<InsuranceCitation> onCitationTap;

  const _AnswerCardRenderer({
    required this.card,
    required this.citations,
    required this.arabic,
    required this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    final presentation = card.presentation;
    if (presentation == null) {
      return _StructuredAnswerCard(
        card: card,
        citations: citations,
        arabic: arabic,
        onCitationTap: onCitationTap,
      );
    }
    return _ProfessionalAnswerCard(
      presentation: presentation,
      citations: citations,
      arabic: arabic,
      onCitationTap: onCitationTap,
    );
  }
}

class _ProfessionalAnswerCard extends StatefulWidget {
  final InsuranceAnswerPresentation presentation;
  final List<InsuranceCitation> citations;
  final bool arabic;
  final ValueChanged<InsuranceCitation> onCitationTap;

  const _ProfessionalAnswerCard({
    required this.presentation,
    required this.citations,
    required this.arabic,
    required this.onCitationTap,
  });

  @override
  State<_ProfessionalAnswerCard> createState() =>
      _ProfessionalAnswerCardState();
}

class _ProfessionalAnswerCardState extends State<_ProfessionalAnswerCard> {
  bool _evidenceExpanded = false;

  ({Color color, Color surface, IconData icon}) get _tone =>
      switch (widget.presentation.tone) {
        'positive' => (
          color: const Color(0xFF047857),
          surface: const Color(0xFFECFDF5),
          icon: Icons.verified_rounded,
        ),
        'negative' => (
          color: const Color(0xFFB42318),
          surface: const Color(0xFFFEF2F2),
          icon: Icons.cancel_rounded,
        ),
        'warning' => (
          color: const Color(0xFFB45309),
          surface: const Color(0xFFFFFBEB),
          icon: Icons.rule_rounded,
        ),
        _ => (
          color: const Color(0xFF4338CA),
          surface: const Color(0xFFEEF2FF),
          icon: Icons.info_rounded,
        ),
      };

  List<InsuranceCitation> _citationsFor(List<String> ids) {
    final allowed = ids.toSet();
    return widget.citations
        .where(
          (citation) =>
              allowed.contains(citation.resolvedEvidenceId) ||
              allowed.contains(citation.chunkId),
        )
        .toList(growable: false);
  }

  ({Color color, IconData icon}) _rowTone(String status) => switch (status) {
    'eligible' || 'met' || 'covered' || 'affirmed' => (
      color: const Color(0xFF047857),
      icon: Icons.check_circle_rounded,
    ),
    'not_eligible' ||
    'not_met' ||
    'not_covered' ||
    'denied' => (color: const Color(0xFFB42318), icon: Icons.cancel_rounded),
    'conditional' ||
    'unknown' => (color: const Color(0xFFB45309), icon: Icons.help_rounded),
    _ => (color: const Color(0xFF4338CA), icon: Icons.info_outline_rounded),
  };

  Widget _evidenceButton(List<String> ids) {
    final matches = _citationsFor(ids);
    if (matches.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => _showClaimEvidence(matches),
      icon: const Icon(Icons.menu_book_rounded, size: 15),
      label: Text(widget.arabic ? 'عرض الدليل' : 'View evidence'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: const Color(0xFF4F46E5),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _showClaimEvidence(List<InsuranceCitation> citations) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    widget.arabic ? 'الأدلة الداعمة' : 'Supporting evidence',
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: citations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final citation = citations[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        leading: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: Color(0xFFEF4444),
                        ),
                        title: Text(
                          citation.documentTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${citation.locationLabel}\n${citation.excerpt}',
                          style: const TextStyle(height: 1.4),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onCitationTap(citation);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _resultRow(InsurancePresentationRow row) {
    final tone = _rowTone(row.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E8F2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Text(
            row.label,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          );
          final result = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tone.icon, size: 18, color: tone.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  row.value,
                  style: TextStyle(
                    color: tone.color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _evidenceButton(row.evidenceIds),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 7), result],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: label),
              const SizedBox(width: 8),
              Flexible(flex: 2, child: result),
            ],
          );
        },
      ),
    );
  }

  Widget _factRow(InsurancePresentationRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          row.label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );
        final value = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                row.value,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _evidenceButton(row.evidenceIds),
          ],
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 4), value],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 128, child: label),
            const SizedBox(width: 9),
            Expanded(child: value),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final tone = _tone;
    final allEvidence = _citationsFor(presentation.displayedEvidenceIds);
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        key: const ValueKey('insurance-answer-card'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.color.withValues(alpha: .24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              color: tone.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.displayTitle,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(tone.icon, size: 20, color: tone.color),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          presentation.displayVerdict,
                          style: TextStyle(
                            color: tone.color,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (presentation.comparisonRows.isNotEmpty) ...[
                    LayoutBuilder(
                      builder: (context, constraints) => Column(
                        children: presentation.comparisonRows
                            .map(
                              (row) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _resultRow(row),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  for (final section in presentation.sections) ...[
                    if (section.rows.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 3, bottom: 10),
                        child: Text(
                          section.title,
                          style: const TextStyle(
                            color: Color(0xFF27324A),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      ...section.rows.map(_factRow),
                    ],
                  ],
                  if (presentation.explanation?.trim().isNotEmpty == true) ...[
                    if (presentation.comparisonRows.isNotEmpty ||
                        presentation.sections.isNotEmpty)
                      const Divider(height: 22, color: Color(0xFFE8EDF5)),
                    Text(
                      presentation.explanation!,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (presentation.missingInformation.isNotEmpty) ...[
                    const SizedBox(height: 13),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        presentation.missingInformation.join('\n'),
                        style: const TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (presentation.nextAction?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 11),
                    Text(
                      presentation.nextAction!,
                      style: const TextStyle(
                        color: Color(0xFF1E3A5F),
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (allEvidence.isNotEmpty) ...[
                    const Divider(height: 24, color: Color(0xFFE8EDF5)),
                    InkWell(
                      key: const ValueKey('insurance-evidence-verification'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(
                        () => _evidenceExpanded = !_evidenceExpanded,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              color: Color(0xFF059669),
                              size: 18,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                widget.arabic
                                    ? 'تم التحقق من الأدلة · ${presentation.evidenceSourceCount} مصدر معتمد'
                                    : 'Evidence verified · ${presentation.evidenceSourceCount} approved source${presentation.evidenceSourceCount == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  color: Color(0xFF047857),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Icon(
                              _evidenceExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: const Color(0xFF059669),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_evidenceExpanded) ...[
                      const SizedBox(height: 8),
                      ...allEvidence.map(
                        (citation) => Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.picture_as_pdf_outlined,
                              color: Color(0xFFEF4444),
                            ),
                            title: Text(
                              citation.documentTitle,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${citation.locationLabel}\n${citation.excerpt}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.35,
                              ),
                            ),
                            onTap: () => widget.onCitationTap(citation),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructuredAnswerCard extends StatelessWidget {
  final InsuranceAnswerCard card;
  final List<InsuranceCitation> citations;
  final bool arabic;
  final ValueChanged<InsuranceCitation> onCitationTap;

  const _StructuredAnswerCard({
    required this.card,
    required this.citations,
    required this.arabic,
    required this.onCitationTap,
  });

  ({String label, Color color, IconData icon}) get _verdictStyle =>
      switch (card.verdict) {
        'covered' => (
          label: arabic ? 'مغطّى' : 'Covered',
          color: const Color(0xFF047857),
          icon: Icons.verified_rounded,
        ),
        'not_covered' => (
          label: arabic ? 'غير مغطّى' : 'Not covered',
          color: const Color(0xFFB42318),
          icon: Icons.cancel_rounded,
        ),
        'conditional' => (
          label: arabic ? 'تغطية مشروطة' : 'Conditional coverage',
          color: const Color(0xFFB45309),
          icon: Icons.rule_rounded,
        ),
        'partial' => (
          label: arabic ? 'تحقق جزئي' : 'Partially established',
          color: const Color(0xFFB45309),
          icon: Icons.incomplete_circle_rounded,
        ),
        'needs_more_information' => (
          label: arabic
              ? 'يلزم المزيد من المعلومات'
              : 'More information needed',
          color: const Color(0xFF0369A1),
          icon: Icons.help_rounded,
        ),
        'insufficient_evidence' => (
          label: arabic ? 'الأدلة غير كافية' : 'Insufficient evidence',
          color: const Color(0xFF475569),
          icon: Icons.find_in_page_outlined,
        ),
        'conflict' => (
          label: arabic ? 'تعارض في الأدلة' : 'Evidence conflict',
          color: const Color(0xFF7E22CE),
          icon: Icons.warning_amber_rounded,
        ),
        _ => (
          label: arabic ? 'معلومة من السياسة' : 'Policy information',
          color: const Color(0xFF4338CA),
          icon: Icons.info_rounded,
        ),
      };

  ({IconData icon, Color color, String label}) _criterionStyle(String status) =>
      switch (status) {
        'met' => (
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF059669),
          label: arabic ? 'متحقق' : 'Met',
        ),
        'not_met' => (
          icon: Icons.cancel_rounded,
          color: const Color(0xFFDC2626),
          label: arabic ? 'غير متحقق' : 'Not met',
        ),
        _ => (
          icon: Icons.help_rounded,
          color: const Color(0xFFD97706),
          label: arabic ? 'غير معروف' : 'Unknown',
        ),
      };

  Widget _title(String english, String arabicLabel, IconData icon) => Row(
    children: [
      Icon(icon, size: 18, color: const Color(0xFF4F46E5)),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          arabic ? arabicLabel : english,
          style: const TextStyle(
            color: Color(0xFF27324A),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );

  Widget _references(List<String> ids) => _EvidenceReferenceChips(
    evidenceIds: ids,
    citations: citations,
    arabic: arabic,
    onCitationTap: onCitationTap,
  );

  @override
  Widget build(BuildContext context) {
    final verdict = _verdictStyle;
    final dose = card.doseSchedule;
    final doseFields = <(String, String)>[
      if (dose?.dose != null) (arabic ? 'الجرعة' : 'Dose', dose!.dose!),
      if (dose?.route != null)
        (arabic ? 'طريقة الإعطاء' : 'Route', dose!.route!),
      if (dose?.frequency != null)
        (arabic ? 'التكرار' : 'Frequency', dose!.frequency!),
      if (dose?.loading != null)
        (arabic ? 'جرعة البدء' : 'Loading', dose!.loading!),
      if (dose?.maintenance != null)
        (arabic ? 'جرعة الاستمرار' : 'Maintenance', dose!.maintenance!),
    ];
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        key: const ValueKey('insurance-answer-card'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: verdict.color.withValues(alpha: .27)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(17, 15, 17, 16),
              color: verdict.color.withValues(alpha: .075),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: verdict.color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          verdict.icon,
                          color: verdict.color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              arabic ? 'النتيجة' : 'VERDICT',
                              style: TextStyle(
                                color: verdict.color.withValues(alpha: .78),
                                fontSize: 10.5,
                                letterSpacing: arabic ? 0 : .65,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              verdict.label,
                              style: TextStyle(
                                color: verdict.color,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    card.summary,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 15,
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (card.criteria.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 16, 17, 8),
                child: _title(
                  'Coverage criteria',
                  'شروط التغطية',
                  Icons.rule_folder_outlined,
                ),
              ),
              ...card.criteria.map((criterion) {
                final status = _criterionStyle(criterion.status);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(17, 5, 17, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(status.icon, color: status.color, size: 19),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              criterion.label,
                              style: const TextStyle(
                                color: Color(0xFF27324A),
                                fontSize: 13.5,
                                height: 1.4,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              status.label,
                              style: TextStyle(
                                color: status.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (criterion.detail != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                criterion.detail!,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            _references(criterion.evidenceIds),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (doseFields.isNotEmpty) ...[
              const Divider(height: 24, color: Color(0xFFE8EDF5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 10),
                child: _title(
                  'Dose & schedule',
                  'الجرعة والجدول',
                  Icons.medication_liquid_rounded,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: doseFields
                      .map(
                        (field) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text.rich(
                            TextSpan(
                              text: '${field.$1}: ',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                TextSpan(
                                  text: field.$2,
                                  style: const TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 8),
                child: _references(dose?.evidenceIds ?? const []),
              ),
            ],
            if (card.missingInformation.isNotEmpty) ...[
              const Divider(height: 24, color: Color(0xFFE8EDF5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 8),
                child: _title(
                  'Missing information',
                  'المعلومات الناقصة',
                  Icons.help_outline_rounded,
                ),
              ),
              ...card.missingInformation.map(
                (item) => Padding(
                  padding: const EdgeInsets.fromLTRB(17, 3, 17, 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 6,
                          color: Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
            ],
            if (card.nextAction?.trim().isNotEmpty == true) ...[
              const Divider(height: 24, color: Color(0xFFE8EDF5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 0, 17, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _title(
                        'Next action',
                        'الخطوة التالية',
                        Icons.arrow_circle_right_outlined,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        card.nextAction!,
                        style: const TextStyle(
                          color: Color(0xFF1E3A5F),
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (card.claims.isNotEmpty) ...[
              const Divider(height: 10, color: Color(0xFFE8EDF5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 13, 17, 8),
                child: _title(
                  'Evidence-linked facts',
                  'الحقائق المرتبطة بالأدلة',
                  Icons.link_rounded,
                ),
              ),
              ...card.claims.map(
                (claim) => Padding(
                  padding: const EdgeInsets.fromLTRB(17, 4, 17, 11),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFBFF),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0xFFE4E9F3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          claim.text,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 12.8,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (claim.evidenceQuote != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '“${claim.evidenceQuote}”',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11.5,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        _references(claim.evidenceIds),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceReferenceChips extends StatelessWidget {
  final List<String> evidenceIds;
  final List<InsuranceCitation> citations;
  final bool arabic;
  final ValueChanged<InsuranceCitation> onCitationTap;

  const _EvidenceReferenceChips({
    required this.evidenceIds,
    required this.citations,
    required this.arabic,
    required this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    if (evidenceIds.isEmpty) return const SizedBox.shrink();
    final ids = evidenceIds.toSet();
    final matches = citations.asMap().entries.where(
      (entry) =>
          ids.contains(entry.value.resolvedEvidenceId) ||
          ids.contains(entry.value.chunkId),
    );
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 5,
        children: matches
            .map(
              (entry) => ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(
                  Icons.menu_book_rounded,
                  size: 14,
                  color: Color(0xFF4F46E5),
                ),
                label: Text(
                  arabic
                      ? 'دليل ${entry.key + 1}'
                      : 'Evidence ${entry.key + 1}',
                  style: const TextStyle(
                    color: Color(0xFF4338CA),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                side: const BorderSide(color: Color(0xFFC7D2FE)),
                backgroundColor: const Color(0xFFEEF2FF),
                tooltip:
                    '${entry.value.documentTitle} • ${entry.value.locationLabel}',
                onPressed: () => onCitationTap(entry.value),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SourcesList extends StatefulWidget {
  final List<InsuranceCitation> citations;
  final InsuranceCitation? selectedCitation;
  final bool arabic;
  final ValueChanged<InsuranceCitation> onCitationTap;

  const _SourcesList({
    required this.citations,
    required this.selectedCitation,
    required this.arabic,
    required this.onCitationTap,
  });

  @override
  State<_SourcesList> createState() => _SourcesListState();
}

class _SourcesListState extends State<_SourcesList> {
  bool _showAll = false;

  String _location(InsuranceCitation citation) {
    if (!widget.arabic) return citation.locationLabel;
    if (citation.pageFrom != null) {
      return citation.pageTo != null && citation.pageTo != citation.pageFrom
          ? 'الصفحات ${citation.pageFrom}-${citation.pageTo}'
          : 'صفحة ${citation.pageFrom}';
    }
    if (citation.sheetName != null) {
      final rows = citation.rowFrom == null
          ? ''
          : citation.rowTo != null && citation.rowTo != citation.rowFrom
          ? ' • الصفوف ${citation.rowFrom}-${citation.rowTo}'
          : ' • الصف ${citation.rowFrom}';
      return 'ورقة: ${citation.sheetName}$rows';
    }
    return citation.sectionTitle?.trim().isNotEmpty == true
        ? citation.sectionTitle!
        : 'وثيقة المصدر';
  }

  String _supportLabel(InsuranceCitation citation) {
    switch (citation.supportLevel) {
      case 'gold_evidence':
        return widget.arabic ? 'دليل مباشر معتمد' : 'Gold direct evidence';
      case 'strongest_direct_support':
        return widget.arabic ? 'أقوى دليل مباشر' : 'Strongest direct support';
      case 'corroborating_evidence':
        return widget.arabic ? 'دليل مؤيد' : 'Corroborating evidence';
      case 'additional_supporting_source':
        return widget.arabic
            ? 'مصدر داعم إضافي'
            : 'Additional supporting source';
      default:
        return widget.arabic ? 'دليل داعم' : 'Supporting evidence';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _showAll ? widget.citations : widget.citations.take(3);
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 19,
                color: Color(0xFF5B55E7),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.arabic
                      ? '${widget.citations.length} ${widget.citations.length == 1 ? 'مصدر داعم' : 'مصادر داعمة'}'
                      : '${widget.citations.length} supporting source${widget.citations.length == 1 ? '' : 's'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ...visible.map((citation) {
            final selected =
                widget.selectedCitation?.resolvedEvidenceId ==
                    citation.resolvedEvidenceId ||
                (citation.resolvedEvidenceId.isEmpty &&
                    widget.selectedCitation?.chunkId == citation.chunkId);
            final gold = citation.supportLevel == 'gold_evidence';
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onCitationTap(citation),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFEDE9FE) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFA78BFA)
                          : gold
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFDCE5EF),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        gold
                            ? Icons.verified_rounded
                            : Icons.picture_as_pdf_outlined,
                        color: gold
                            ? const Color(0xFF059669)
                            : const Color(0xFFEF4444),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${citation.documentTitle} • ${_location(citation)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _supportLabel(citation),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: gold
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        widget.arabic
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        size: 18,
                        color: const Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (widget.citations.length > 3)
            TextButton.icon(
              key: const ValueKey('insurance-show-all-sources'),
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(
                _showAll
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(
                _showAll
                    ? widget.arabic
                          ? 'إخفاء المصادر الإضافية'
                          : 'Show fewer sources'
                    : widget.arabic
                    ? 'إظهار كل المصادر (${widget.citations.length})'
                    : 'Show all sources (${widget.citations.length})',
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswerKindBadge extends StatelessWidget {
  final bool deepReview;
  final bool previousAnswer;
  final bool arabic;

  const _AnswerKindBadge({
    required this.deepReview,
    required this.previousAnswer,
    required this.arabic,
  });

  @override
  Widget build(BuildContext context) {
    final label = arabic
        ? deepReview
              ? 'مراجعة معمّقة'
              : previousAnswer
              ? 'الإجابة السابقة'
              : 'الإجابة'
        : deepReview
        ? 'DEEP REVIEW'
        : previousAnswer
        ? 'PREVIOUS ANSWER'
        : 'ANSWER';
    final background = deepReview
        ? const Color(0xFFEDE9FE)
        : previousAnswer
        ? const Color(0xFFF1F5F9)
        : const Color(0xFFE0E7FF);
    final foreground = deepReview
        ? const Color(0xFF6D28D9)
        : previousAnswer
        ? const Color(0xFF64748B)
        : const Color(0xFF4338CA);
    final icon = deepReview
        ? Icons.auto_awesome_rounded
        : previousAnswer
        ? Icons.history_rounded
        : Icons.check_circle_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              letterSpacing: .7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineSource extends StatelessWidget {
  final String source;
  const _InlineSource({required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 19,
            color: Color(0xFF059669),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SOURCE',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 10.5,
                    letterSpacing: .7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  source,
                  style: const TextStyle(
                    color: Color(0xFF166534),
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  final String? generator;

  const _AiBadge({this.generator});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: generator == null ? 'AI-assisted answer' : 'Generator: $generator',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              letterSpacing: .7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EvidenceBadge extends StatelessWidget {
  final bool arabic;

  const _EvidenceBadge({required this.arabic});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF059669);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        arabic ? 'تم التحقق من الأدلة' : 'Evidence checked',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AnswerStatusBadge extends StatelessWidget {
  final String status;
  final bool arabic;

  const _AnswerStatusBadge({required this.status, required this.arabic});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      'grounded' => (
        arabic ? 'موثّقة' : 'Validated',
        const Color(0xFF059669),
        Icons.verified_rounded,
      ),
      'grounded_extractive' => (
        arabic ? 'استخراج موثّق' : 'Source extract',
        const Color(0xFF0369A1),
        Icons.fact_check_outlined,
      ),
      'clarification_required' => (
        arabic ? 'يلزم توضيح' : 'Clarification needed',
        const Color(0xFFD97706),
        Icons.help_outline_rounded,
      ),
      'internal_error' => (
        arabic ? 'خطأ مؤقت' : 'Temporary error',
        const Color(0xFFB42318),
        Icons.error_outline_rounded,
      ),
      _ => (
        arabic ? 'تمت المعالجة' : 'Processed',
        const Color(0xFF64748B),
        Icons.check_circle_outline_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();
  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFFEEF2FF),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF5B55E7),
            size: 19,
          ),
        ),
        SizedBox(width: 10),
        _PulseDots(),
        SizedBox(width: 9),
        Flexible(
          child: Text(
            'Searching policies and verifying evidence...',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PulseDots extends StatelessWidget {
  const _PulseDots();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: CircularProgressIndicator(
      strokeWidth: 2.4,
      color: Color(0xFF6D5DFB),
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 17),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EEF5))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (!sending) onSend();
                    },
                    const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                      if (!sending) onSend();
                    },
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) {
                      if (!sending) onSend();
                    },
                    decoration: InputDecoration(
                      hintText:
                          'Ask about coverage, dose, age, approval or documentation... / اسأل عن شروط الصرف',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF64748B),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFDCE5EF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFDCE5EF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFF6D5DFB),
                          width: 1.6,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 50,
                height: 50,
                child: FilledButton(
                  onPressed: sending ? null : onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B55E7),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Answers are restricted to approved documents. Review the cited source before dispensing.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  final InsuranceCitation? citation;
  final ValueChanged<InsuranceCitation> onOpen;
  const _EvidencePanel({required this.citation, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDE7F1)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: citation == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fact_check_outlined,
                        size: 46,
                        color: Color(0xFFCBD5E1),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Evidence preview',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF475569),
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Select a cited source to inspect the exact excerpt and location.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF172554), Color(0xFF312E81)],
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.fact_check_rounded,
                          color: Color(0xFFA5B4FC),
                        ),
                        SizedBox(width: 9),
                        Text(
                          'VERIFIED EVIDENCE',
                          style: TextStyle(
                            color: Colors.white,
                            letterSpacing: .7,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      citation!.documentTitle,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      citation!.locationLabel,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF5B55E7),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (citation!.sectionTitle?.trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 17),
                            const Text(
                              'SECTION',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: .8,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              citation!.sectionTitle!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 19),
                          const Text(
                            'SOURCE EXCERPT',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: .8,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              citation!.excerpt,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF334155),
                                height: 1.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => onOpen(citation!),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF5B55E7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: const Text('Open original document'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: Color(0xFF94A3B8),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Private signed link • expires in 5 minutes',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFFF7ED),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: Color(0xFFEA580C),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _DocumentCenterDialog extends StatefulWidget {
  final InsuranceAssistantRepository repository;
  const _DocumentCenterDialog({required this.repository});
  @override
  State<_DocumentCenterDialog> createState() => _DocumentCenterDialogState();
}

class _DocumentCenterDialogState extends State<_DocumentCenterDialog> {
  List<InsuranceDocumentSummary> _documents = const [];
  List<Map<String, dynamic>> _readiness = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final documents = await widget.repository.fetchDocuments();
      List<Map<String, dynamic>> readiness = const [];
      try {
        readiness = await widget.repository.fetchKnowledgeReadiness();
      } catch (_) {
        // The legacy health list remains usable during a staged migration.
      }
      if (mounted) {
        setState(() {
          _documents = documents;
          _readiness = readiness;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'xlsx', 'xls', 'xlsb', 'csv'],
      withData: true,
    );
    if (picked == null ||
        picked.files.isEmpty ||
        picked.files.single.bytes == null) {
      return;
    }
    final file = picked.files.single;
    if (!mounted) return;
    final controller = TextEditingController(
      text: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Knowledge base title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await widget.repository.uploadDocument(
        bytes: file.bytes!,
        fileName: file.name,
        title: title,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openSearchInspector() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> rows = const [];
    bool loading = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.manage_search_rounded),
              SizedBox(width: 10),
              Text('Search Inspector'),
            ],
          ),
          content: SizedBox(
            width: 900,
            height: 560,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: (_) async {
                    if (controller.text.trim().isEmpty) return;
                    setDialogState(() {
                      loading = true;
                      error = null;
                    });
                    try {
                      rows = await widget.repository.inspectSearch(
                        controller.text.trim(),
                      );
                    } catch (value) {
                      error = value.toString();
                    }
                    setDialogState(() => loading = false);
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Enter the exact user question to inspect retrieval…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) return;
                        setDialogState(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          rows = await widget.repository.inspectSearch(
                            controller.text.trim(),
                          );
                        } catch (value) {
                          error = value.toString();
                        }
                        setDialogState(() => loading = false);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                if (loading) const LinearProgressIndicator(),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final accepted = row['accepted'] == true;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accepted
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accepted
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFFCA5A5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${row['rank']}  ${row['document_title']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${accepted ? 'ACCEPTED' : 'REJECTED'} · ${row['acceptance_reason']} · score ${((row['combined_score'] as num?) ?? 0).toStringAsFixed(3)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: accepted
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              row['matched_content']?.toString() ?? '',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _openSourceInspector(InsuranceDocumentSummary document) async {
    final rows = await widget.repository.inspectSource(document.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Source Inspector · ${document.title}'),
        content: SizedBox(
          width: 920,
          height: 600,
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, index) {
              final row = rows[index];
              final location = row['page_from'] != null
                  ? 'Page ${row['page_from']}'
                  : 'Sheet ${row['sheet_name']} · row ${row['row_from']}';
              return ListTile(
                title: Text(
                  'Chunk ${row['chunk_index']} · $location',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${row['section_title'] ?? 'Root'} · ${row['topic_normalized']}\n${row['content_text']}',
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 650,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF172554), Color(0xFF312E81)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_copy_rounded,
                    color: Color(0xFFA5B4FC),
                    size: 29,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insurance Knowledge Library',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Private originals, extraction status and version history',
                          style: TextStyle(
                            color: Color(0xFFC7D2FE),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openSearchInspector,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Search inspector'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _upload,
                    icon: _uploading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload document'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFEF2F2),
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
            if (_readiness.isNotEmpty)
              _KnowledgeReadinessSummary(rows: _readiness),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _documents.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.library_books_outlined,
                            size: 58,
                            color: Color(0xFFCBD5E1),
                          ),
                          SizedBox(height: 14),
                          Text(
                            'No documents yet',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Upload PDF, DOCX or XLSX guidelines to begin.',
                            style: TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(18),
                      itemCount: _documents.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (_, index) {
                        final document = _documents[index];
                        final readiness = _readiness
                            .where(
                              (row) =>
                                  row['source_document_id']?.toString() ==
                                  document.id,
                            )
                            .firstOrNull;
                        return _DocumentTile(
                          document: document,
                          readiness: readiness,
                          onInspect: () => _openSourceInspector(document),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeReadinessSummary extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _KnowledgeReadinessSummary({required this.rows});

  @override
  Widget build(BuildContext context) {
    final ready = rows.where((row) => row['runtime_ready'] == true).length;
    final pending = rows.fold<int>(
      0,
      (total, row) =>
          total + ((row['pending_review_count'] as num?)?.toInt() ?? 0),
    );
    final conflicts = rows.fold<int>(
      0,
      (total, row) =>
          total + ((row['open_conflict_count'] as num?)?.toInt() ?? 0),
    );

    Widget metric(String label, String value, Color color, IconData icon) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Text(
                '$label  $value',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      color: const Color(0xFFF8FAFC),
      child: Wrap(
        spacing: 9,
        runSpacing: 8,
        children: [
          metric(
            'Runtime ready',
            '$ready/${rows.length}',
            const Color(0xFF047857),
            Icons.verified_outlined,
          ),
          metric(
            'Pending review',
            '$pending',
            const Color(0xFFB45309),
            Icons.rate_review_outlined,
          ),
          metric(
            'Open conflicts',
            '$conflicts',
            const Color(0xFFB91C1C),
            Icons.warning_amber_rounded,
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final InsuranceDocumentSummary document;
  final Map<String, dynamic>? readiness;
  final VoidCallback onInspect;
  const _DocumentTile({
    required this.document,
    required this.readiness,
    required this.onInspect,
  });
  @override
  Widget build(BuildContext context) {
    final colors = switch (document.status) {
      'ready' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'failed' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => (const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Inspect extracted source',
            onPressed: onInspect,
            icon: const Icon(Icons.fact_check_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${document.fileName} • ${(document.fileSize / 1048576).toStringAsFixed(1)} MB • ${DateFormat('dd MMM yyyy').format(document.uploadedAt)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (readiness != null) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    children: [
                      _MiniStatus(
                        label: readiness!['runtime_ready'] == true
                            ? 'POLICY READY'
                            : 'NEEDS REVIEW',
                        good: readiness!['runtime_ready'] == true,
                      ),
                      Text(
                        '${readiness!['active_rule_count']} rules • ${readiness!['evidence_count']} evidence • ${readiness!['pending_review_count']} pending',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${document.chunkCount} chunks • ${document.embeddedCount} embedded • ${document.entityCount} entities • ${document.validationStatus}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: document.validationStatus == 'verified'
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                ),
                if (document.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      document.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              document.status.toUpperCase(),
              style: TextStyle(
                color: colors.$2,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  final String label;
  final bool good;
  const _MiniStatus({required this.label, required this.good});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: good ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: good ? const Color(0xFF166534) : const Color(0xFF92400E),
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: .3,
      ),
    ),
  );
}
