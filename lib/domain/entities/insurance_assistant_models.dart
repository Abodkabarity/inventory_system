import 'package:equatable/equatable.dart';

class InsuranceCitation extends Equatable {
  final String chunkId;
  final String documentTitle;
  final String fileName;
  final String storageBucket;
  final String storagePath;
  final String excerpt;
  final String? sectionTitle;
  final int? pageFrom;
  final int? pageTo;
  final String? sheetName;
  final int? rowFrom;
  final int? rowTo;
  final double score;

  const InsuranceCitation({
    required this.chunkId,
    required this.documentTitle,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.excerpt,
    this.sectionTitle,
    this.pageFrom,
    this.pageTo,
    this.sheetName,
    this.rowFrom,
    this.rowTo,
    this.score = 0,
  });

  String get locationLabel {
    if (pageFrom != null) {
      return pageTo != null && pageTo != pageFrom
          ? 'Pages $pageFrom-$pageTo'
          : 'Page $pageFrom';
    }
    if (sheetName != null) {
      final rows = rowFrom == null
          ? ''
          : rowTo != null && rowTo != rowFrom
          ? ' • Rows $rowFrom-$rowTo'
          : ' • Row $rowFrom';
      return 'Sheet: $sheetName$rows';
    }
    return sectionTitle?.trim().isNotEmpty == true
        ? sectionTitle!
        : 'Source document';
  }

  @override
  List<Object?> get props => [chunkId, storagePath, excerpt, pageFrom, rowFrom];
}

class InsuranceClarificationCandidate extends Equatable {
  final String id;
  final String canonicalName;
  final String entityType;
  final String queryFragment;
  final double similarity;

  const InsuranceClarificationCandidate({
    required this.id,
    required this.canonicalName,
    required this.entityType,
    required this.queryFragment,
    required this.similarity,
  });

  @override
  List<Object?> get props => [id, canonicalName, entityType, queryFragment];
}

class InsuranceClarification extends Equatable {
  final String id;
  final List<InsuranceClarificationCandidate> candidates;

  const InsuranceClarification({required this.id, required this.candidates});

  @override
  List<Object?> get props => [id, candidates];
}

class InsuranceChatMessage extends Equatable {
  final String id;
  final String role;
  final String message;
  final DateTime createdAt;
  final double? confidence;
  final List<InsuranceCitation> citations;
  final bool conversational;
  final InsuranceClarification? clarification;

  const InsuranceChatMessage({
    required this.id,
    required this.role,
    required this.message,
    required this.createdAt,
    this.confidence,
    this.citations = const [],
    this.conversational = false,
    this.clarification,
  });

  bool get isUser => role == 'user';

  @override
  List<Object?> get props => [
    id,
    role,
    message,
    createdAt,
    citations,
    conversational,
    clarification,
  ];
}

class InsuranceChatSession extends Equatable {
  final String id;
  final String title;
  final DateTime updatedAt;

  const InsuranceChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, title, updatedAt];
}

class InsuranceDocumentSummary extends Equatable {
  final String id;
  final String title;
  final String fileName;
  final String status;
  final String? error;
  final int fileSize;
  final DateTime uploadedAt;
  final String validationStatus;
  final String lifecycleStatus;
  final int chunkCount;
  final int embeddedCount;
  final int entityCount;

  const InsuranceDocumentSummary({
    required this.id,
    required this.title,
    required this.fileName,
    required this.status,
    required this.fileSize,
    required this.uploadedAt,
    this.validationStatus = 'pending',
    this.lifecycleStatus = 'current',
    this.chunkCount = 0,
    this.embeddedCount = 0,
    this.entityCount = 0,
    this.error,
  });

  @override
  List<Object?> get props => [
    id,
    status,
    validationStatus,
    chunkCount,
    uploadedAt,
  ];
}
