// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SyncQueueTableTable extends SyncQueueTable
    with TableInfo<$SyncQueueTableTable, SyncQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _idempotencyKeyMeta =
      const VerificationMeta('idempotencyKey');
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
      'idempotency_key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _mutationPathMeta =
      const VerificationMeta('mutationPath');
  @override
  late final GeneratedColumn<String> mutationPath = GeneratedColumn<String>(
      'mutation_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  late final GeneratedColumnWithTypeConverter<OperationType, String>
      operationType = GeneratedColumn<String>(
              'operation_type', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<OperationType>(
              $SyncQueueTableTable.$converteroperationType);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> status =
      GeneratedColumn<String>('status', aliasedName, false,
              type: DriftSqlType.string,
              requiredDuringInsert: false,
              defaultValue: Constant(SyncStatus.pending.name))
          .withConverter<SyncStatus>($SyncQueueTableTable.$converterstatus);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maxRetriesMeta =
      const VerificationMeta('maxRetries');
  @override
  late final GeneratedColumn<int> maxRetries = GeneratedColumn<int>(
      'max_retries', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(5));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<int> lastAttemptAt = GeneratedColumn<int>(
      'last_attempt_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(5));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        idempotencyKey,
        mutationPath,
        operationType,
        entityType,
        entityId,
        payloadJson,
        status,
        retryCount,
        maxRetries,
        createdAt,
        lastAttemptAt,
        errorMessage,
        priority
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue_table';
  @override
  VerificationContext validateIntegrity(Insertable<SyncQueueEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
          _idempotencyKeyMeta,
          idempotencyKey.isAcceptableOrUnknown(
              data['idempotency_key']!, _idempotencyKeyMeta));
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('mutation_path')) {
      context.handle(
          _mutationPathMeta,
          mutationPath.isAcceptableOrUnknown(
              data['mutation_path']!, _mutationPathMeta));
    } else if (isInserting) {
      context.missing(_mutationPathMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('max_retries')) {
      context.handle(
          _maxRetriesMeta,
          maxRetries.isAcceptableOrUnknown(
              data['max_retries']!, _maxRetriesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      idempotencyKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}idempotency_key'])!,
      mutationPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mutation_path'])!,
      operationType: $SyncQueueTableTable.$converteroperationType.fromSql(
          attachedDatabase.typeMapping.read(
              DriftSqlType.string, data['${effectivePrefix}operation_type'])!),
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      status: $SyncQueueTableTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      maxRetries: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_retries'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      lastAttemptAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_attempt_at']),
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
    );
  }

  @override
  $SyncQueueTableTable createAlias(String alias) {
    return $SyncQueueTableTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OperationType, String, String>
      $converteroperationType =
      const EnumNameConverter<OperationType>(OperationType.values);
  static JsonTypeConverter2<SyncStatus, String, String> $converterstatus =
      const EnumNameConverter<SyncStatus>(SyncStatus.values);
}

class SyncQueueEntry extends DataClass implements Insertable<SyncQueueEntry> {
  /// UUIDv4 primary key, generated client-side.
  final String id;

  /// Idempotency key to prevent duplicate execution on Convex.
  final String idempotencyKey;

  /// The Convex mutation path to invoke (e.g., "rides:requestRide").
  final String mutationPath;

  /// The type of operation: create, update, or delete.
  final OperationType operationType;

  /// Target entity type (e.g., "rideRequests", "realEstateBookings").
  final String entityType;

  /// Client-generated ID of the entity being mutated.
  final String entityId;

  /// JSON-serialized mutation arguments (the full payload).
  final String payloadJson;

  /// Current sync status.
  final SyncStatus status;

  /// Number of times sync has been attempted.
  final int retryCount;

  /// Maximum allowed retries before marking as failed.
  final int maxRetries;

  /// Timestamp when the entry was created (milliseconds since epoch).
  final int createdAt;

  /// Timestamp of the last sync attempt.
  final int? lastAttemptAt;

  /// Error message from the last failed attempt.
  final String? errorMessage;

  /// Priority: lower number = higher priority (rides > property inquiries).
  final int priority;
  const SyncQueueEntry(
      {required this.id,
      required this.idempotencyKey,
      required this.mutationPath,
      required this.operationType,
      required this.entityType,
      required this.entityId,
      required this.payloadJson,
      required this.status,
      required this.retryCount,
      required this.maxRetries,
      required this.createdAt,
      this.lastAttemptAt,
      this.errorMessage,
      required this.priority});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['mutation_path'] = Variable<String>(mutationPath);
    {
      map['operation_type'] = Variable<String>(
          $SyncQueueTableTable.$converteroperationType.toSql(operationType));
    }
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['payload_json'] = Variable<String>(payloadJson);
    {
      map['status'] =
          Variable<String>($SyncQueueTableTable.$converterstatus.toSql(status));
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['max_retries'] = Variable<int>(maxRetries);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['priority'] = Variable<int>(priority);
    return map;
  }

  SyncQueueTableCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueTableCompanion(
      id: Value(id),
      idempotencyKey: Value(idempotencyKey),
      mutationPath: Value(mutationPath),
      operationType: Value(operationType),
      entityType: Value(entityType),
      entityId: Value(entityId),
      payloadJson: Value(payloadJson),
      status: Value(status),
      retryCount: Value(retryCount),
      maxRetries: Value(maxRetries),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      priority: Value(priority),
    );
  }

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueEntry(
      id: serializer.fromJson<String>(json['id']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      mutationPath: serializer.fromJson<String>(json['mutationPath']),
      operationType: $SyncQueueTableTable.$converteroperationType
          .fromJson(serializer.fromJson<String>(json['operationType'])),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: $SyncQueueTableTable.$converterstatus
          .fromJson(serializer.fromJson<String>(json['status'])),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      maxRetries: serializer.fromJson<int>(json['maxRetries']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<int?>(json['lastAttemptAt']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      priority: serializer.fromJson<int>(json['priority']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'mutationPath': serializer.toJson<String>(mutationPath),
      'operationType': serializer.toJson<String>(
          $SyncQueueTableTable.$converteroperationType.toJson(operationType)),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer
          .toJson<String>($SyncQueueTableTable.$converterstatus.toJson(status)),
      'retryCount': serializer.toJson<int>(retryCount),
      'maxRetries': serializer.toJson<int>(maxRetries),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastAttemptAt': serializer.toJson<int?>(lastAttemptAt),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'priority': serializer.toJson<int>(priority),
    };
  }

  SyncQueueEntry copyWith(
          {String? id,
          String? idempotencyKey,
          String? mutationPath,
          OperationType? operationType,
          String? entityType,
          String? entityId,
          String? payloadJson,
          SyncStatus? status,
          int? retryCount,
          int? maxRetries,
          int? createdAt,
          Value<int?> lastAttemptAt = const Value.absent(),
          Value<String?> errorMessage = const Value.absent(),
          int? priority}) =>
      SyncQueueEntry(
        id: id ?? this.id,
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        mutationPath: mutationPath ?? this.mutationPath,
        operationType: operationType ?? this.operationType,
        entityType: entityType ?? this.entityType,
        entityId: entityId ?? this.entityId,
        payloadJson: payloadJson ?? this.payloadJson,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        maxRetries: maxRetries ?? this.maxRetries,
        createdAt: createdAt ?? this.createdAt,
        lastAttemptAt:
            lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
        priority: priority ?? this.priority,
      );
  SyncQueueEntry copyWithCompanion(SyncQueueTableCompanion data) {
    return SyncQueueEntry(
      id: data.id.present ? data.id.value : this.id,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      mutationPath: data.mutationPath.present
          ? data.mutationPath.value
          : this.mutationPath,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      maxRetries:
          data.maxRetries.present ? data.maxRetries.value : this.maxRetries,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      priority: data.priority.present ? data.priority.value : this.priority,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueEntry(')
          ..write('id: $id, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('mutationPath: $mutationPath, ')
          ..write('operationType: $operationType, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('priority: $priority')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      idempotencyKey,
      mutationPath,
      operationType,
      entityType,
      entityId,
      payloadJson,
      status,
      retryCount,
      maxRetries,
      createdAt,
      lastAttemptAt,
      errorMessage,
      priority);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueEntry &&
          other.id == this.id &&
          other.idempotencyKey == this.idempotencyKey &&
          other.mutationPath == this.mutationPath &&
          other.operationType == this.operationType &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.maxRetries == this.maxRetries &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.errorMessage == this.errorMessage &&
          other.priority == this.priority);
}

class SyncQueueTableCompanion extends UpdateCompanion<SyncQueueEntry> {
  final Value<String> id;
  final Value<String> idempotencyKey;
  final Value<String> mutationPath;
  final Value<OperationType> operationType;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> payloadJson;
  final Value<SyncStatus> status;
  final Value<int> retryCount;
  final Value<int> maxRetries;
  final Value<int> createdAt;
  final Value<int?> lastAttemptAt;
  final Value<String?> errorMessage;
  final Value<int> priority;
  final Value<int> rowid;
  const SyncQueueTableCompanion({
    this.id = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.mutationPath = const Value.absent(),
    this.operationType = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.priority = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueTableCompanion.insert({
    required String id,
    required String idempotencyKey,
    required String mutationPath,
    required OperationType operationType,
    required String entityType,
    required String entityId,
    required String payloadJson,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    required int createdAt,
    this.lastAttemptAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.priority = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        idempotencyKey = Value(idempotencyKey),
        mutationPath = Value(mutationPath),
        operationType = Value(operationType),
        entityType = Value(entityType),
        entityId = Value(entityId),
        payloadJson = Value(payloadJson),
        createdAt = Value(createdAt);
  static Insertable<SyncQueueEntry> custom({
    Expression<String>? id,
    Expression<String>? idempotencyKey,
    Expression<String>? mutationPath,
    Expression<String>? operationType,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<int>? maxRetries,
    Expression<int>? createdAt,
    Expression<int>? lastAttemptAt,
    Expression<String>? errorMessage,
    Expression<int>? priority,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (mutationPath != null) 'mutation_path': mutationPath,
      if (operationType != null) 'operation_type': operationType,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (errorMessage != null) 'error_message': errorMessage,
      if (priority != null) 'priority': priority,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? idempotencyKey,
      Value<String>? mutationPath,
      Value<OperationType>? operationType,
      Value<String>? entityType,
      Value<String>? entityId,
      Value<String>? payloadJson,
      Value<SyncStatus>? status,
      Value<int>? retryCount,
      Value<int>? maxRetries,
      Value<int>? createdAt,
      Value<int?>? lastAttemptAt,
      Value<String?>? errorMessage,
      Value<int>? priority,
      Value<int>? rowid}) {
    return SyncQueueTableCompanion(
      id: id ?? this.id,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      mutationPath: mutationPath ?? this.mutationPath,
      operationType: operationType ?? this.operationType,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
      priority: priority ?? this.priority,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (mutationPath.present) {
      map['mutation_path'] = Variable<String>(mutationPath.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>($SyncQueueTableTable
          .$converteroperationType
          .toSql(operationType.value));
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
          $SyncQueueTableTable.$converterstatus.toSql(status.value));
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (maxRetries.present) {
      map['max_retries'] = Variable<int>(maxRetries.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueTableCompanion(')
          ..write('id: $id, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('mutationPath: $mutationPath, ')
          ..write('operationType: $operationType, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('priority: $priority, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPropertiesTableTable extends CachedPropertiesTable
    with TableInfo<$CachedPropertiesTableTable, CachedProperty> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPropertiesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _hourlyRateMeta =
      const VerificationMeta('hourlyRate');
  @override
  late final GeneratedColumn<double> hourlyRate = GeneratedColumn<double>(
      'hourly_rate', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('SLE'));
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  @override
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
      'city', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _countryMeta =
      const VerificationMeta('country');
  @override
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
      'country', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _geohashMeta =
      const VerificationMeta('geohash');
  @override
  late final GeneratedColumn<String> geohash = GeneratedColumn<String>(
      'geohash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _availabilityStatusMeta =
      const VerificationMeta('availabilityStatus');
  @override
  late final GeneratedColumn<String> availabilityStatus =
      GeneratedColumn<String>('availability_status', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlsJsonMeta =
      const VerificationMeta('imageUrlsJson');
  @override
  late final GeneratedColumn<String> imageUrlsJson = GeneratedColumn<String>(
      'image_urls_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _isFeaturedMeta =
      const VerificationMeta('isFeatured');
  @override
  late final GeneratedColumn<bool> isFeatured = GeneratedColumn<bool>(
      'is_featured', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_featured" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _viewCountMeta =
      const VerificationMeta('viewCount');
  @override
  late final GeneratedColumn<int> viewCount = GeneratedColumn<int>(
      'view_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  late final GeneratedColumnWithTypeConverter<EntitySyncStatus, String>
      syncStatus = GeneratedColumn<String>('sync_status', aliasedName, false,
              type: DriftSqlType.string,
              requiredDuringInsert: false,
              defaultValue: Constant(EntitySyncStatus.synced.name))
          .withConverter<EntitySyncStatus>(
              $CachedPropertiesTableTable.$convertersyncStatus);
  static const VerificationMeta _localUpdatedAtMeta =
      const VerificationMeta('localUpdatedAt');
  @override
  late final GeneratedColumn<int> localUpdatedAt = GeneratedColumn<int>(
      'local_updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _remoteUpdatedAtMeta =
      const VerificationMeta('remoteUpdatedAt');
  @override
  late final GeneratedColumn<int> remoteUpdatedAt = GeneratedColumn<int>(
      'remote_updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
      'last_synced_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ownerId,
        title,
        description,
        category,
        price,
        hourlyRate,
        currency,
        address,
        city,
        country,
        latitude,
        longitude,
        geohash,
        availabilityStatus,
        imageUrlsJson,
        isFeatured,
        viewCount,
        syncStatus,
        localUpdatedAt,
        remoteUpdatedAt,
        lastSyncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_properties_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedProperty> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('hourly_rate')) {
      context.handle(
          _hourlyRateMeta,
          hourlyRate.isAcceptableOrUnknown(
              data['hourly_rate']!, _hourlyRateMeta));
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('city')) {
      context.handle(
          _cityMeta, city.isAcceptableOrUnknown(data['city']!, _cityMeta));
    } else if (isInserting) {
      context.missing(_cityMeta);
    }
    if (data.containsKey('country')) {
      context.handle(_countryMeta,
          country.isAcceptableOrUnknown(data['country']!, _countryMeta));
    } else if (isInserting) {
      context.missing(_countryMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('geohash')) {
      context.handle(_geohashMeta,
          geohash.isAcceptableOrUnknown(data['geohash']!, _geohashMeta));
    } else if (isInserting) {
      context.missing(_geohashMeta);
    }
    if (data.containsKey('availability_status')) {
      context.handle(
          _availabilityStatusMeta,
          availabilityStatus.isAcceptableOrUnknown(
              data['availability_status']!, _availabilityStatusMeta));
    } else if (isInserting) {
      context.missing(_availabilityStatusMeta);
    }
    if (data.containsKey('image_urls_json')) {
      context.handle(
          _imageUrlsJsonMeta,
          imageUrlsJson.isAcceptableOrUnknown(
              data['image_urls_json']!, _imageUrlsJsonMeta));
    }
    if (data.containsKey('is_featured')) {
      context.handle(
          _isFeaturedMeta,
          isFeatured.isAcceptableOrUnknown(
              data['is_featured']!, _isFeaturedMeta));
    }
    if (data.containsKey('view_count')) {
      context.handle(_viewCountMeta,
          viewCount.isAcceptableOrUnknown(data['view_count']!, _viewCountMeta));
    }
    if (data.containsKey('local_updated_at')) {
      context.handle(
          _localUpdatedAtMeta,
          localUpdatedAt.isAcceptableOrUnknown(
              data['local_updated_at']!, _localUpdatedAtMeta));
    } else if (isInserting) {
      context.missing(_localUpdatedAtMeta);
    }
    if (data.containsKey('remote_updated_at')) {
      context.handle(
          _remoteUpdatedAtMeta,
          remoteUpdatedAt.isAcceptableOrUnknown(
              data['remote_updated_at']!, _remoteUpdatedAtMeta));
    } else if (isInserting) {
      context.missing(_remoteUpdatedAtMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedProperty map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProperty(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      hourlyRate: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}hourly_rate']),
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address'])!,
      city: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}city'])!,
      country: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}country'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      geohash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}geohash'])!,
      availabilityStatus: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}availability_status'])!,
      imageUrlsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}image_urls_json'])!,
      isFeatured: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_featured'])!,
      viewCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}view_count'])!,
      syncStatus: $CachedPropertiesTableTable.$convertersyncStatus.fromSql(
          attachedDatabase.typeMapping.read(
              DriftSqlType.string, data['${effectivePrefix}sync_status'])!),
      localUpdatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}local_updated_at'])!,
      remoteUpdatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_updated_at'])!,
      lastSyncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_synced_at']),
    );
  }

  @override
  $CachedPropertiesTableTable createAlias(String alias) {
    return $CachedPropertiesTableTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EntitySyncStatus, String, String>
      $convertersyncStatus =
      const EnumNameConverter<EntitySyncStatus>(EntitySyncStatus.values);
}

class CachedProperty extends DataClass implements Insertable<CachedProperty> {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final String category;
  final double price;
  final double? hourlyRate;
  final String currency;
  final String address;
  final String city;
  final String country;
  final double latitude;
  final double longitude;
  final String geohash;
  final String availabilityStatus;
  final String imageUrlsJson;
  final bool isFeatured;
  final int viewCount;
  final EntitySyncStatus syncStatus;
  final int localUpdatedAt;
  final int remoteUpdatedAt;
  final int? lastSyncedAt;
  const CachedProperty(
      {required this.id,
      required this.ownerId,
      required this.title,
      required this.description,
      required this.category,
      required this.price,
      this.hourlyRate,
      required this.currency,
      required this.address,
      required this.city,
      required this.country,
      required this.latitude,
      required this.longitude,
      required this.geohash,
      required this.availabilityStatus,
      required this.imageUrlsJson,
      required this.isFeatured,
      required this.viewCount,
      required this.syncStatus,
      required this.localUpdatedAt,
      required this.remoteUpdatedAt,
      this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['category'] = Variable<String>(category);
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || hourlyRate != null) {
      map['hourly_rate'] = Variable<double>(hourlyRate);
    }
    map['currency'] = Variable<String>(currency);
    map['address'] = Variable<String>(address);
    map['city'] = Variable<String>(city);
    map['country'] = Variable<String>(country);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['geohash'] = Variable<String>(geohash);
    map['availability_status'] = Variable<String>(availabilityStatus);
    map['image_urls_json'] = Variable<String>(imageUrlsJson);
    map['is_featured'] = Variable<bool>(isFeatured);
    map['view_count'] = Variable<int>(viewCount);
    {
      map['sync_status'] = Variable<String>(
          $CachedPropertiesTableTable.$convertersyncStatus.toSql(syncStatus));
    }
    map['local_updated_at'] = Variable<int>(localUpdatedAt);
    map['remote_updated_at'] = Variable<int>(remoteUpdatedAt);
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt);
    }
    return map;
  }

  CachedPropertiesTableCompanion toCompanion(bool nullToAbsent) {
    return CachedPropertiesTableCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      title: Value(title),
      description: Value(description),
      category: Value(category),
      price: Value(price),
      hourlyRate: hourlyRate == null && nullToAbsent
          ? const Value.absent()
          : Value(hourlyRate),
      currency: Value(currency),
      address: Value(address),
      city: Value(city),
      country: Value(country),
      latitude: Value(latitude),
      longitude: Value(longitude),
      geohash: Value(geohash),
      availabilityStatus: Value(availabilityStatus),
      imageUrlsJson: Value(imageUrlsJson),
      isFeatured: Value(isFeatured),
      viewCount: Value(viewCount),
      syncStatus: Value(syncStatus),
      localUpdatedAt: Value(localUpdatedAt),
      remoteUpdatedAt: Value(remoteUpdatedAt),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
    );
  }

  factory CachedProperty.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProperty(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      category: serializer.fromJson<String>(json['category']),
      price: serializer.fromJson<double>(json['price']),
      hourlyRate: serializer.fromJson<double?>(json['hourlyRate']),
      currency: serializer.fromJson<String>(json['currency']),
      address: serializer.fromJson<String>(json['address']),
      city: serializer.fromJson<String>(json['city']),
      country: serializer.fromJson<String>(json['country']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      geohash: serializer.fromJson<String>(json['geohash']),
      availabilityStatus:
          serializer.fromJson<String>(json['availabilityStatus']),
      imageUrlsJson: serializer.fromJson<String>(json['imageUrlsJson']),
      isFeatured: serializer.fromJson<bool>(json['isFeatured']),
      viewCount: serializer.fromJson<int>(json['viewCount']),
      syncStatus: $CachedPropertiesTableTable.$convertersyncStatus
          .fromJson(serializer.fromJson<String>(json['syncStatus'])),
      localUpdatedAt: serializer.fromJson<int>(json['localUpdatedAt']),
      remoteUpdatedAt: serializer.fromJson<int>(json['remoteUpdatedAt']),
      lastSyncedAt: serializer.fromJson<int?>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'category': serializer.toJson<String>(category),
      'price': serializer.toJson<double>(price),
      'hourlyRate': serializer.toJson<double?>(hourlyRate),
      'currency': serializer.toJson<String>(currency),
      'address': serializer.toJson<String>(address),
      'city': serializer.toJson<String>(city),
      'country': serializer.toJson<String>(country),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'geohash': serializer.toJson<String>(geohash),
      'availabilityStatus': serializer.toJson<String>(availabilityStatus),
      'imageUrlsJson': serializer.toJson<String>(imageUrlsJson),
      'isFeatured': serializer.toJson<bool>(isFeatured),
      'viewCount': serializer.toJson<int>(viewCount),
      'syncStatus': serializer.toJson<String>(
          $CachedPropertiesTableTable.$convertersyncStatus.toJson(syncStatus)),
      'localUpdatedAt': serializer.toJson<int>(localUpdatedAt),
      'remoteUpdatedAt': serializer.toJson<int>(remoteUpdatedAt),
      'lastSyncedAt': serializer.toJson<int?>(lastSyncedAt),
    };
  }

  CachedProperty copyWith(
          {String? id,
          String? ownerId,
          String? title,
          String? description,
          String? category,
          double? price,
          Value<double?> hourlyRate = const Value.absent(),
          String? currency,
          String? address,
          String? city,
          String? country,
          double? latitude,
          double? longitude,
          String? geohash,
          String? availabilityStatus,
          String? imageUrlsJson,
          bool? isFeatured,
          int? viewCount,
          EntitySyncStatus? syncStatus,
          int? localUpdatedAt,
          int? remoteUpdatedAt,
          Value<int?> lastSyncedAt = const Value.absent()}) =>
      CachedProperty(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        price: price ?? this.price,
        hourlyRate: hourlyRate.present ? hourlyRate.value : this.hourlyRate,
        currency: currency ?? this.currency,
        address: address ?? this.address,
        city: city ?? this.city,
        country: country ?? this.country,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        geohash: geohash ?? this.geohash,
        availabilityStatus: availabilityStatus ?? this.availabilityStatus,
        imageUrlsJson: imageUrlsJson ?? this.imageUrlsJson,
        isFeatured: isFeatured ?? this.isFeatured,
        viewCount: viewCount ?? this.viewCount,
        syncStatus: syncStatus ?? this.syncStatus,
        localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
        lastSyncedAt:
            lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
      );
  CachedProperty copyWithCompanion(CachedPropertiesTableCompanion data) {
    return CachedProperty(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      category: data.category.present ? data.category.value : this.category,
      price: data.price.present ? data.price.value : this.price,
      hourlyRate:
          data.hourlyRate.present ? data.hourlyRate.value : this.hourlyRate,
      currency: data.currency.present ? data.currency.value : this.currency,
      address: data.address.present ? data.address.value : this.address,
      city: data.city.present ? data.city.value : this.city,
      country: data.country.present ? data.country.value : this.country,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      geohash: data.geohash.present ? data.geohash.value : this.geohash,
      availabilityStatus: data.availabilityStatus.present
          ? data.availabilityStatus.value
          : this.availabilityStatus,
      imageUrlsJson: data.imageUrlsJson.present
          ? data.imageUrlsJson.value
          : this.imageUrlsJson,
      isFeatured:
          data.isFeatured.present ? data.isFeatured.value : this.isFeatured,
      viewCount: data.viewCount.present ? data.viewCount.value : this.viewCount,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
      localUpdatedAt: data.localUpdatedAt.present
          ? data.localUpdatedAt.value
          : this.localUpdatedAt,
      remoteUpdatedAt: data.remoteUpdatedAt.present
          ? data.remoteUpdatedAt.value
          : this.remoteUpdatedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProperty(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('price: $price, ')
          ..write('hourlyRate: $hourlyRate, ')
          ..write('currency: $currency, ')
          ..write('address: $address, ')
          ..write('city: $city, ')
          ..write('country: $country, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('geohash: $geohash, ')
          ..write('availabilityStatus: $availabilityStatus, ')
          ..write('imageUrlsJson: $imageUrlsJson, ')
          ..write('isFeatured: $isFeatured, ')
          ..write('viewCount: $viewCount, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        ownerId,
        title,
        description,
        category,
        price,
        hourlyRate,
        currency,
        address,
        city,
        country,
        latitude,
        longitude,
        geohash,
        availabilityStatus,
        imageUrlsJson,
        isFeatured,
        viewCount,
        syncStatus,
        localUpdatedAt,
        remoteUpdatedAt,
        lastSyncedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProperty &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.title == this.title &&
          other.description == this.description &&
          other.category == this.category &&
          other.price == this.price &&
          other.hourlyRate == this.hourlyRate &&
          other.currency == this.currency &&
          other.address == this.address &&
          other.city == this.city &&
          other.country == this.country &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.geohash == this.geohash &&
          other.availabilityStatus == this.availabilityStatus &&
          other.imageUrlsJson == this.imageUrlsJson &&
          other.isFeatured == this.isFeatured &&
          other.viewCount == this.viewCount &&
          other.syncStatus == this.syncStatus &&
          other.localUpdatedAt == this.localUpdatedAt &&
          other.remoteUpdatedAt == this.remoteUpdatedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class CachedPropertiesTableCompanion extends UpdateCompanion<CachedProperty> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> title;
  final Value<String> description;
  final Value<String> category;
  final Value<double> price;
  final Value<double?> hourlyRate;
  final Value<String> currency;
  final Value<String> address;
  final Value<String> city;
  final Value<String> country;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String> geohash;
  final Value<String> availabilityStatus;
  final Value<String> imageUrlsJson;
  final Value<bool> isFeatured;
  final Value<int> viewCount;
  final Value<EntitySyncStatus> syncStatus;
  final Value<int> localUpdatedAt;
  final Value<int> remoteUpdatedAt;
  final Value<int?> lastSyncedAt;
  final Value<int> rowid;
  const CachedPropertiesTableCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.price = const Value.absent(),
    this.hourlyRate = const Value.absent(),
    this.currency = const Value.absent(),
    this.address = const Value.absent(),
    this.city = const Value.absent(),
    this.country = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.geohash = const Value.absent(),
    this.availabilityStatus = const Value.absent(),
    this.imageUrlsJson = const Value.absent(),
    this.isFeatured = const Value.absent(),
    this.viewCount = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localUpdatedAt = const Value.absent(),
    this.remoteUpdatedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPropertiesTableCompanion.insert({
    required String id,
    required String ownerId,
    required String title,
    required String description,
    required String category,
    required double price,
    this.hourlyRate = const Value.absent(),
    this.currency = const Value.absent(),
    required String address,
    required String city,
    required String country,
    required double latitude,
    required double longitude,
    required String geohash,
    required String availabilityStatus,
    this.imageUrlsJson = const Value.absent(),
    this.isFeatured = const Value.absent(),
    this.viewCount = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required int localUpdatedAt,
    required int remoteUpdatedAt,
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ownerId = Value(ownerId),
        title = Value(title),
        description = Value(description),
        category = Value(category),
        price = Value(price),
        address = Value(address),
        city = Value(city),
        country = Value(country),
        latitude = Value(latitude),
        longitude = Value(longitude),
        geohash = Value(geohash),
        availabilityStatus = Value(availabilityStatus),
        localUpdatedAt = Value(localUpdatedAt),
        remoteUpdatedAt = Value(remoteUpdatedAt);
  static Insertable<CachedProperty> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? category,
    Expression<double>? price,
    Expression<double>? hourlyRate,
    Expression<String>? currency,
    Expression<String>? address,
    Expression<String>? city,
    Expression<String>? country,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? geohash,
    Expression<String>? availabilityStatus,
    Expression<String>? imageUrlsJson,
    Expression<bool>? isFeatured,
    Expression<int>? viewCount,
    Expression<String>? syncStatus,
    Expression<int>? localUpdatedAt,
    Expression<int>? remoteUpdatedAt,
    Expression<int>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (price != null) 'price': price,
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
      if (currency != null) 'currency': currency,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (country != null) 'country': country,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (geohash != null) 'geohash': geohash,
      if (availabilityStatus != null) 'availability_status': availabilityStatus,
      if (imageUrlsJson != null) 'image_urls_json': imageUrlsJson,
      if (isFeatured != null) 'is_featured': isFeatured,
      if (viewCount != null) 'view_count': viewCount,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (localUpdatedAt != null) 'local_updated_at': localUpdatedAt,
      if (remoteUpdatedAt != null) 'remote_updated_at': remoteUpdatedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPropertiesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? ownerId,
      Value<String>? title,
      Value<String>? description,
      Value<String>? category,
      Value<double>? price,
      Value<double?>? hourlyRate,
      Value<String>? currency,
      Value<String>? address,
      Value<String>? city,
      Value<String>? country,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<String>? geohash,
      Value<String>? availabilityStatus,
      Value<String>? imageUrlsJson,
      Value<bool>? isFeatured,
      Value<int>? viewCount,
      Value<EntitySyncStatus>? syncStatus,
      Value<int>? localUpdatedAt,
      Value<int>? remoteUpdatedAt,
      Value<int?>? lastSyncedAt,
      Value<int>? rowid}) {
    return CachedPropertiesTableCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      currency: currency ?? this.currency,
      address: address ?? this.address,
      city: city ?? this.city,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geohash: geohash ?? this.geohash,
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
      imageUrlsJson: imageUrlsJson ?? this.imageUrlsJson,
      isFeatured: isFeatured ?? this.isFeatured,
      viewCount: viewCount ?? this.viewCount,
      syncStatus: syncStatus ?? this.syncStatus,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (hourlyRate.present) {
      map['hourly_rate'] = Variable<double>(hourlyRate.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (geohash.present) {
      map['geohash'] = Variable<String>(geohash.value);
    }
    if (availabilityStatus.present) {
      map['availability_status'] = Variable<String>(availabilityStatus.value);
    }
    if (imageUrlsJson.present) {
      map['image_urls_json'] = Variable<String>(imageUrlsJson.value);
    }
    if (isFeatured.present) {
      map['is_featured'] = Variable<bool>(isFeatured.value);
    }
    if (viewCount.present) {
      map['view_count'] = Variable<int>(viewCount.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>($CachedPropertiesTableTable
          .$convertersyncStatus
          .toSql(syncStatus.value));
    }
    if (localUpdatedAt.present) {
      map['local_updated_at'] = Variable<int>(localUpdatedAt.value);
    }
    if (remoteUpdatedAt.present) {
      map['remote_updated_at'] = Variable<int>(remoteUpdatedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPropertiesTableCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('price: $price, ')
          ..write('hourlyRate: $hourlyRate, ')
          ..write('currency: $currency, ')
          ..write('address: $address, ')
          ..write('city: $city, ')
          ..write('country: $country, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('geohash: $geohash, ')
          ..write('availabilityStatus: $availabilityStatus, ')
          ..write('imageUrlsJson: $imageUrlsJson, ')
          ..write('isFeatured: $isFeatured, ')
          ..write('viewCount: $viewCount, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedRidesTableTable extends CachedRidesTable
    with TableInfo<$CachedRidesTableTable, CachedRide> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedRidesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _passengerIdMeta =
      const VerificationMeta('passengerId');
  @override
  late final GeneratedColumn<String> passengerId = GeneratedColumn<String>(
      'passenger_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _driverIdMeta =
      const VerificationMeta('driverId');
  @override
  late final GeneratedColumn<String> driverId = GeneratedColumn<String>(
      'driver_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _vehicleIdMeta =
      const VerificationMeta('vehicleId');
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
      'vehicle_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pickupLatMeta =
      const VerificationMeta('pickupLat');
  @override
  late final GeneratedColumn<double> pickupLat = GeneratedColumn<double>(
      'pickup_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pickupLngMeta =
      const VerificationMeta('pickupLng');
  @override
  late final GeneratedColumn<double> pickupLng = GeneratedColumn<double>(
      'pickup_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pickupAddressMeta =
      const VerificationMeta('pickupAddress');
  @override
  late final GeneratedColumn<String> pickupAddress = GeneratedColumn<String>(
      'pickup_address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dropoffLatMeta =
      const VerificationMeta('dropoffLat');
  @override
  late final GeneratedColumn<double> dropoffLat = GeneratedColumn<double>(
      'dropoff_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _dropoffLngMeta =
      const VerificationMeta('dropoffLng');
  @override
  late final GeneratedColumn<double> dropoffLng = GeneratedColumn<double>(
      'dropoff_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _dropoffAddressMeta =
      const VerificationMeta('dropoffAddress');
  @override
  late final GeneratedColumn<String> dropoffAddress = GeneratedColumn<String>(
      'dropoff_address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _distanceKmMeta =
      const VerificationMeta('distanceKm');
  @override
  late final GeneratedColumn<double> distanceKm = GeneratedColumn<double>(
      'distance_km', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _estimatedDurationMinMeta =
      const VerificationMeta('estimatedDurationMin');
  @override
  late final GeneratedColumn<int> estimatedDurationMin = GeneratedColumn<int>(
      'estimated_duration_min', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fareAmountMeta =
      const VerificationMeta('fareAmount');
  @override
  late final GeneratedColumn<double> fareAmount = GeneratedColumn<double>(
      'fare_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('SLE'));
  static const VerificationMeta _platformFeeMeta =
      const VerificationMeta('platformFee');
  @override
  late final GeneratedColumn<double> platformFee = GeneratedColumn<double>(
      'platform_fee', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _driverPayoutMeta =
      const VerificationMeta('driverPayout');
  @override
  late final GeneratedColumn<double> driverPayout = GeneratedColumn<double>(
      'driver_payout', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _paymentStatusMeta =
      const VerificationMeta('paymentStatus');
  @override
  late final GeneratedColumn<String> paymentStatus = GeneratedColumn<String>(
      'payment_status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _paymentReferenceMeta =
      const VerificationMeta('paymentReference');
  @override
  late final GeneratedColumn<String> paymentReference = GeneratedColumn<String>(
      'payment_reference', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _blockchainLogHashMeta =
      const VerificationMeta('blockchainLogHash');
  @override
  late final GeneratedColumn<String> blockchainLogHash =
      GeneratedColumn<String>('blockchain_log_hash', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _acceptedAtMeta =
      const VerificationMeta('acceptedAt');
  @override
  late final GeneratedColumn<int> acceptedAt = GeneratedColumn<int>(
      'accepted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
      'started_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _cancelledAtMeta =
      const VerificationMeta('cancelledAt');
  @override
  late final GeneratedColumn<int> cancelledAt = GeneratedColumn<int>(
      'cancelled_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _cancelReasonMeta =
      const VerificationMeta('cancelReason');
  @override
  late final GeneratedColumn<String> cancelReason = GeneratedColumn<String>(
      'cancel_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  late final GeneratedColumnWithTypeConverter<EntitySyncStatus, String>
      syncStatus = GeneratedColumn<String>('sync_status', aliasedName, false,
              type: DriftSqlType.string,
              requiredDuringInsert: false,
              defaultValue: Constant(EntitySyncStatus.synced.name))
          .withConverter<EntitySyncStatus>(
              $CachedRidesTableTable.$convertersyncStatus);
  static const VerificationMeta _localUpdatedAtMeta =
      const VerificationMeta('localUpdatedAt');
  @override
  late final GeneratedColumn<int> localUpdatedAt = GeneratedColumn<int>(
      'local_updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _remoteUpdatedAtMeta =
      const VerificationMeta('remoteUpdatedAt');
  @override
  late final GeneratedColumn<int> remoteUpdatedAt = GeneratedColumn<int>(
      'remote_updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
      'last_synced_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        passengerId,
        driverId,
        vehicleId,
        pickupLat,
        pickupLng,
        pickupAddress,
        dropoffLat,
        dropoffLng,
        dropoffAddress,
        distanceKm,
        estimatedDurationMin,
        fareAmount,
        currency,
        platformFee,
        driverPayout,
        status,
        paymentStatus,
        paymentReference,
        blockchainLogHash,
        acceptedAt,
        startedAt,
        completedAt,
        cancelledAt,
        cancelReason,
        syncStatus,
        localUpdatedAt,
        remoteUpdatedAt,
        lastSyncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_rides_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedRide> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('passenger_id')) {
      context.handle(
          _passengerIdMeta,
          passengerId.isAcceptableOrUnknown(
              data['passenger_id']!, _passengerIdMeta));
    } else if (isInserting) {
      context.missing(_passengerIdMeta);
    }
    if (data.containsKey('driver_id')) {
      context.handle(_driverIdMeta,
          driverId.isAcceptableOrUnknown(data['driver_id']!, _driverIdMeta));
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(_vehicleIdMeta,
          vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta));
    }
    if (data.containsKey('pickup_lat')) {
      context.handle(_pickupLatMeta,
          pickupLat.isAcceptableOrUnknown(data['pickup_lat']!, _pickupLatMeta));
    } else if (isInserting) {
      context.missing(_pickupLatMeta);
    }
    if (data.containsKey('pickup_lng')) {
      context.handle(_pickupLngMeta,
          pickupLng.isAcceptableOrUnknown(data['pickup_lng']!, _pickupLngMeta));
    } else if (isInserting) {
      context.missing(_pickupLngMeta);
    }
    if (data.containsKey('pickup_address')) {
      context.handle(
          _pickupAddressMeta,
          pickupAddress.isAcceptableOrUnknown(
              data['pickup_address']!, _pickupAddressMeta));
    }
    if (data.containsKey('dropoff_lat')) {
      context.handle(
          _dropoffLatMeta,
          dropoffLat.isAcceptableOrUnknown(
              data['dropoff_lat']!, _dropoffLatMeta));
    } else if (isInserting) {
      context.missing(_dropoffLatMeta);
    }
    if (data.containsKey('dropoff_lng')) {
      context.handle(
          _dropoffLngMeta,
          dropoffLng.isAcceptableOrUnknown(
              data['dropoff_lng']!, _dropoffLngMeta));
    } else if (isInserting) {
      context.missing(_dropoffLngMeta);
    }
    if (data.containsKey('dropoff_address')) {
      context.handle(
          _dropoffAddressMeta,
          dropoffAddress.isAcceptableOrUnknown(
              data['dropoff_address']!, _dropoffAddressMeta));
    }
    if (data.containsKey('distance_km')) {
      context.handle(
          _distanceKmMeta,
          distanceKm.isAcceptableOrUnknown(
              data['distance_km']!, _distanceKmMeta));
    } else if (isInserting) {
      context.missing(_distanceKmMeta);
    }
    if (data.containsKey('estimated_duration_min')) {
      context.handle(
          _estimatedDurationMinMeta,
          estimatedDurationMin.isAcceptableOrUnknown(
              data['estimated_duration_min']!, _estimatedDurationMinMeta));
    } else if (isInserting) {
      context.missing(_estimatedDurationMinMeta);
    }
    if (data.containsKey('fare_amount')) {
      context.handle(
          _fareAmountMeta,
          fareAmount.isAcceptableOrUnknown(
              data['fare_amount']!, _fareAmountMeta));
    } else if (isInserting) {
      context.missing(_fareAmountMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('platform_fee')) {
      context.handle(
          _platformFeeMeta,
          platformFee.isAcceptableOrUnknown(
              data['platform_fee']!, _platformFeeMeta));
    } else if (isInserting) {
      context.missing(_platformFeeMeta);
    }
    if (data.containsKey('driver_payout')) {
      context.handle(
          _driverPayoutMeta,
          driverPayout.isAcceptableOrUnknown(
              data['driver_payout']!, _driverPayoutMeta));
    } else if (isInserting) {
      context.missing(_driverPayoutMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('payment_status')) {
      context.handle(
          _paymentStatusMeta,
          paymentStatus.isAcceptableOrUnknown(
              data['payment_status']!, _paymentStatusMeta));
    } else if (isInserting) {
      context.missing(_paymentStatusMeta);
    }
    if (data.containsKey('payment_reference')) {
      context.handle(
          _paymentReferenceMeta,
          paymentReference.isAcceptableOrUnknown(
              data['payment_reference']!, _paymentReferenceMeta));
    }
    if (data.containsKey('blockchain_log_hash')) {
      context.handle(
          _blockchainLogHashMeta,
          blockchainLogHash.isAcceptableOrUnknown(
              data['blockchain_log_hash']!, _blockchainLogHashMeta));
    }
    if (data.containsKey('accepted_at')) {
      context.handle(
          _acceptedAtMeta,
          acceptedAt.isAcceptableOrUnknown(
              data['accepted_at']!, _acceptedAtMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('cancelled_at')) {
      context.handle(
          _cancelledAtMeta,
          cancelledAt.isAcceptableOrUnknown(
              data['cancelled_at']!, _cancelledAtMeta));
    }
    if (data.containsKey('cancel_reason')) {
      context.handle(
          _cancelReasonMeta,
          cancelReason.isAcceptableOrUnknown(
              data['cancel_reason']!, _cancelReasonMeta));
    }
    if (data.containsKey('local_updated_at')) {
      context.handle(
          _localUpdatedAtMeta,
          localUpdatedAt.isAcceptableOrUnknown(
              data['local_updated_at']!, _localUpdatedAtMeta));
    } else if (isInserting) {
      context.missing(_localUpdatedAtMeta);
    }
    if (data.containsKey('remote_updated_at')) {
      context.handle(
          _remoteUpdatedAtMeta,
          remoteUpdatedAt.isAcceptableOrUnknown(
              data['remote_updated_at']!, _remoteUpdatedAtMeta));
    } else if (isInserting) {
      context.missing(_remoteUpdatedAtMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedRide map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedRide(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      passengerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}passenger_id'])!,
      driverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}driver_id']),
      vehicleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}vehicle_id']),
      pickupLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}pickup_lat'])!,
      pickupLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}pickup_lng'])!,
      pickupAddress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pickup_address']),
      dropoffLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}dropoff_lat'])!,
      dropoffLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}dropoff_lng'])!,
      dropoffAddress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dropoff_address']),
      distanceKm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}distance_km'])!,
      estimatedDurationMin: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}estimated_duration_min'])!,
      fareAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}fare_amount'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      platformFee: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}platform_fee'])!,
      driverPayout: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}driver_payout'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      paymentStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_status'])!,
      paymentReference: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}payment_reference']),
      blockchainLogHash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}blockchain_log_hash']),
      acceptedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}accepted_at']),
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}started_at']),
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_at']),
      cancelledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cancelled_at']),
      cancelReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cancel_reason']),
      syncStatus: $CachedRidesTableTable.$convertersyncStatus.fromSql(
          attachedDatabase.typeMapping.read(
              DriftSqlType.string, data['${effectivePrefix}sync_status'])!),
      localUpdatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}local_updated_at'])!,
      remoteUpdatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_updated_at'])!,
      lastSyncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_synced_at']),
    );
  }

  @override
  $CachedRidesTableTable createAlias(String alias) {
    return $CachedRidesTableTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EntitySyncStatus, String, String>
      $convertersyncStatus =
      const EnumNameConverter<EntitySyncStatus>(EntitySyncStatus.values);
}

class CachedRide extends DataClass implements Insertable<CachedRide> {
  final String id;
  final String passengerId;
  final String? driverId;
  final String? vehicleId;
  final double pickupLat;
  final double pickupLng;
  final String? pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String? dropoffAddress;
  final double distanceKm;
  final int estimatedDurationMin;
  final double fareAmount;
  final String currency;
  final double platformFee;
  final double driverPayout;
  final String status;
  final String paymentStatus;
  final String? paymentReference;
  final String? blockchainLogHash;
  final int? acceptedAt;
  final int? startedAt;
  final int? completedAt;
  final int? cancelledAt;
  final String? cancelReason;
  final EntitySyncStatus syncStatus;
  final int localUpdatedAt;
  final int remoteUpdatedAt;
  final int? lastSyncedAt;
  const CachedRide(
      {required this.id,
      required this.passengerId,
      this.driverId,
      this.vehicleId,
      required this.pickupLat,
      required this.pickupLng,
      this.pickupAddress,
      required this.dropoffLat,
      required this.dropoffLng,
      this.dropoffAddress,
      required this.distanceKm,
      required this.estimatedDurationMin,
      required this.fareAmount,
      required this.currency,
      required this.platformFee,
      required this.driverPayout,
      required this.status,
      required this.paymentStatus,
      this.paymentReference,
      this.blockchainLogHash,
      this.acceptedAt,
      this.startedAt,
      this.completedAt,
      this.cancelledAt,
      this.cancelReason,
      required this.syncStatus,
      required this.localUpdatedAt,
      required this.remoteUpdatedAt,
      this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['passenger_id'] = Variable<String>(passengerId);
    if (!nullToAbsent || driverId != null) {
      map['driver_id'] = Variable<String>(driverId);
    }
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    map['pickup_lat'] = Variable<double>(pickupLat);
    map['pickup_lng'] = Variable<double>(pickupLng);
    if (!nullToAbsent || pickupAddress != null) {
      map['pickup_address'] = Variable<String>(pickupAddress);
    }
    map['dropoff_lat'] = Variable<double>(dropoffLat);
    map['dropoff_lng'] = Variable<double>(dropoffLng);
    if (!nullToAbsent || dropoffAddress != null) {
      map['dropoff_address'] = Variable<String>(dropoffAddress);
    }
    map['distance_km'] = Variable<double>(distanceKm);
    map['estimated_duration_min'] = Variable<int>(estimatedDurationMin);
    map['fare_amount'] = Variable<double>(fareAmount);
    map['currency'] = Variable<String>(currency);
    map['platform_fee'] = Variable<double>(platformFee);
    map['driver_payout'] = Variable<double>(driverPayout);
    map['status'] = Variable<String>(status);
    map['payment_status'] = Variable<String>(paymentStatus);
    if (!nullToAbsent || paymentReference != null) {
      map['payment_reference'] = Variable<String>(paymentReference);
    }
    if (!nullToAbsent || blockchainLogHash != null) {
      map['blockchain_log_hash'] = Variable<String>(blockchainLogHash);
    }
    if (!nullToAbsent || acceptedAt != null) {
      map['accepted_at'] = Variable<int>(acceptedAt);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<int>(startedAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    if (!nullToAbsent || cancelledAt != null) {
      map['cancelled_at'] = Variable<int>(cancelledAt);
    }
    if (!nullToAbsent || cancelReason != null) {
      map['cancel_reason'] = Variable<String>(cancelReason);
    }
    {
      map['sync_status'] = Variable<String>(
          $CachedRidesTableTable.$convertersyncStatus.toSql(syncStatus));
    }
    map['local_updated_at'] = Variable<int>(localUpdatedAt);
    map['remote_updated_at'] = Variable<int>(remoteUpdatedAt);
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt);
    }
    return map;
  }

  CachedRidesTableCompanion toCompanion(bool nullToAbsent) {
    return CachedRidesTableCompanion(
      id: Value(id),
      passengerId: Value(passengerId),
      driverId: driverId == null && nullToAbsent
          ? const Value.absent()
          : Value(driverId),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      pickupLat: Value(pickupLat),
      pickupLng: Value(pickupLng),
      pickupAddress: pickupAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(pickupAddress),
      dropoffLat: Value(dropoffLat),
      dropoffLng: Value(dropoffLng),
      dropoffAddress: dropoffAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(dropoffAddress),
      distanceKm: Value(distanceKm),
      estimatedDurationMin: Value(estimatedDurationMin),
      fareAmount: Value(fareAmount),
      currency: Value(currency),
      platformFee: Value(platformFee),
      driverPayout: Value(driverPayout),
      status: Value(status),
      paymentStatus: Value(paymentStatus),
      paymentReference: paymentReference == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentReference),
      blockchainLogHash: blockchainLogHash == null && nullToAbsent
          ? const Value.absent()
          : Value(blockchainLogHash),
      acceptedAt: acceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      cancelledAt: cancelledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledAt),
      cancelReason: cancelReason == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelReason),
      syncStatus: Value(syncStatus),
      localUpdatedAt: Value(localUpdatedAt),
      remoteUpdatedAt: Value(remoteUpdatedAt),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
    );
  }

  factory CachedRide.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedRide(
      id: serializer.fromJson<String>(json['id']),
      passengerId: serializer.fromJson<String>(json['passengerId']),
      driverId: serializer.fromJson<String?>(json['driverId']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      pickupLat: serializer.fromJson<double>(json['pickupLat']),
      pickupLng: serializer.fromJson<double>(json['pickupLng']),
      pickupAddress: serializer.fromJson<String?>(json['pickupAddress']),
      dropoffLat: serializer.fromJson<double>(json['dropoffLat']),
      dropoffLng: serializer.fromJson<double>(json['dropoffLng']),
      dropoffAddress: serializer.fromJson<String?>(json['dropoffAddress']),
      distanceKm: serializer.fromJson<double>(json['distanceKm']),
      estimatedDurationMin:
          serializer.fromJson<int>(json['estimatedDurationMin']),
      fareAmount: serializer.fromJson<double>(json['fareAmount']),
      currency: serializer.fromJson<String>(json['currency']),
      platformFee: serializer.fromJson<double>(json['platformFee']),
      driverPayout: serializer.fromJson<double>(json['driverPayout']),
      status: serializer.fromJson<String>(json['status']),
      paymentStatus: serializer.fromJson<String>(json['paymentStatus']),
      paymentReference: serializer.fromJson<String?>(json['paymentReference']),
      blockchainLogHash:
          serializer.fromJson<String?>(json['blockchainLogHash']),
      acceptedAt: serializer.fromJson<int?>(json['acceptedAt']),
      startedAt: serializer.fromJson<int?>(json['startedAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      cancelledAt: serializer.fromJson<int?>(json['cancelledAt']),
      cancelReason: serializer.fromJson<String?>(json['cancelReason']),
      syncStatus: $CachedRidesTableTable.$convertersyncStatus
          .fromJson(serializer.fromJson<String>(json['syncStatus'])),
      localUpdatedAt: serializer.fromJson<int>(json['localUpdatedAt']),
      remoteUpdatedAt: serializer.fromJson<int>(json['remoteUpdatedAt']),
      lastSyncedAt: serializer.fromJson<int?>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'passengerId': serializer.toJson<String>(passengerId),
      'driverId': serializer.toJson<String?>(driverId),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'pickupLat': serializer.toJson<double>(pickupLat),
      'pickupLng': serializer.toJson<double>(pickupLng),
      'pickupAddress': serializer.toJson<String?>(pickupAddress),
      'dropoffLat': serializer.toJson<double>(dropoffLat),
      'dropoffLng': serializer.toJson<double>(dropoffLng),
      'dropoffAddress': serializer.toJson<String?>(dropoffAddress),
      'distanceKm': serializer.toJson<double>(distanceKm),
      'estimatedDurationMin': serializer.toJson<int>(estimatedDurationMin),
      'fareAmount': serializer.toJson<double>(fareAmount),
      'currency': serializer.toJson<String>(currency),
      'platformFee': serializer.toJson<double>(platformFee),
      'driverPayout': serializer.toJson<double>(driverPayout),
      'status': serializer.toJson<String>(status),
      'paymentStatus': serializer.toJson<String>(paymentStatus),
      'paymentReference': serializer.toJson<String?>(paymentReference),
      'blockchainLogHash': serializer.toJson<String?>(blockchainLogHash),
      'acceptedAt': serializer.toJson<int?>(acceptedAt),
      'startedAt': serializer.toJson<int?>(startedAt),
      'completedAt': serializer.toJson<int?>(completedAt),
      'cancelledAt': serializer.toJson<int?>(cancelledAt),
      'cancelReason': serializer.toJson<String?>(cancelReason),
      'syncStatus': serializer.toJson<String>(
          $CachedRidesTableTable.$convertersyncStatus.toJson(syncStatus)),
      'localUpdatedAt': serializer.toJson<int>(localUpdatedAt),
      'remoteUpdatedAt': serializer.toJson<int>(remoteUpdatedAt),
      'lastSyncedAt': serializer.toJson<int?>(lastSyncedAt),
    };
  }

  CachedRide copyWith(
          {String? id,
          String? passengerId,
          Value<String?> driverId = const Value.absent(),
          Value<String?> vehicleId = const Value.absent(),
          double? pickupLat,
          double? pickupLng,
          Value<String?> pickupAddress = const Value.absent(),
          double? dropoffLat,
          double? dropoffLng,
          Value<String?> dropoffAddress = const Value.absent(),
          double? distanceKm,
          int? estimatedDurationMin,
          double? fareAmount,
          String? currency,
          double? platformFee,
          double? driverPayout,
          String? status,
          String? paymentStatus,
          Value<String?> paymentReference = const Value.absent(),
          Value<String?> blockchainLogHash = const Value.absent(),
          Value<int?> acceptedAt = const Value.absent(),
          Value<int?> startedAt = const Value.absent(),
          Value<int?> completedAt = const Value.absent(),
          Value<int?> cancelledAt = const Value.absent(),
          Value<String?> cancelReason = const Value.absent(),
          EntitySyncStatus? syncStatus,
          int? localUpdatedAt,
          int? remoteUpdatedAt,
          Value<int?> lastSyncedAt = const Value.absent()}) =>
      CachedRide(
        id: id ?? this.id,
        passengerId: passengerId ?? this.passengerId,
        driverId: driverId.present ? driverId.value : this.driverId,
        vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
        pickupLat: pickupLat ?? this.pickupLat,
        pickupLng: pickupLng ?? this.pickupLng,
        pickupAddress:
            pickupAddress.present ? pickupAddress.value : this.pickupAddress,
        dropoffLat: dropoffLat ?? this.dropoffLat,
        dropoffLng: dropoffLng ?? this.dropoffLng,
        dropoffAddress:
            dropoffAddress.present ? dropoffAddress.value : this.dropoffAddress,
        distanceKm: distanceKm ?? this.distanceKm,
        estimatedDurationMin: estimatedDurationMin ?? this.estimatedDurationMin,
        fareAmount: fareAmount ?? this.fareAmount,
        currency: currency ?? this.currency,
        platformFee: platformFee ?? this.platformFee,
        driverPayout: driverPayout ?? this.driverPayout,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paymentReference: paymentReference.present
            ? paymentReference.value
            : this.paymentReference,
        blockchainLogHash: blockchainLogHash.present
            ? blockchainLogHash.value
            : this.blockchainLogHash,
        acceptedAt: acceptedAt.present ? acceptedAt.value : this.acceptedAt,
        startedAt: startedAt.present ? startedAt.value : this.startedAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        cancelledAt: cancelledAt.present ? cancelledAt.value : this.cancelledAt,
        cancelReason:
            cancelReason.present ? cancelReason.value : this.cancelReason,
        syncStatus: syncStatus ?? this.syncStatus,
        localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
        lastSyncedAt:
            lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
      );
  CachedRide copyWithCompanion(CachedRidesTableCompanion data) {
    return CachedRide(
      id: data.id.present ? data.id.value : this.id,
      passengerId:
          data.passengerId.present ? data.passengerId.value : this.passengerId,
      driverId: data.driverId.present ? data.driverId.value : this.driverId,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      pickupLat: data.pickupLat.present ? data.pickupLat.value : this.pickupLat,
      pickupLng: data.pickupLng.present ? data.pickupLng.value : this.pickupLng,
      pickupAddress: data.pickupAddress.present
          ? data.pickupAddress.value
          : this.pickupAddress,
      dropoffLat:
          data.dropoffLat.present ? data.dropoffLat.value : this.dropoffLat,
      dropoffLng:
          data.dropoffLng.present ? data.dropoffLng.value : this.dropoffLng,
      dropoffAddress: data.dropoffAddress.present
          ? data.dropoffAddress.value
          : this.dropoffAddress,
      distanceKm:
          data.distanceKm.present ? data.distanceKm.value : this.distanceKm,
      estimatedDurationMin: data.estimatedDurationMin.present
          ? data.estimatedDurationMin.value
          : this.estimatedDurationMin,
      fareAmount:
          data.fareAmount.present ? data.fareAmount.value : this.fareAmount,
      currency: data.currency.present ? data.currency.value : this.currency,
      platformFee:
          data.platformFee.present ? data.platformFee.value : this.platformFee,
      driverPayout: data.driverPayout.present
          ? data.driverPayout.value
          : this.driverPayout,
      status: data.status.present ? data.status.value : this.status,
      paymentStatus: data.paymentStatus.present
          ? data.paymentStatus.value
          : this.paymentStatus,
      paymentReference: data.paymentReference.present
          ? data.paymentReference.value
          : this.paymentReference,
      blockchainLogHash: data.blockchainLogHash.present
          ? data.blockchainLogHash.value
          : this.blockchainLogHash,
      acceptedAt:
          data.acceptedAt.present ? data.acceptedAt.value : this.acceptedAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      cancelledAt:
          data.cancelledAt.present ? data.cancelledAt.value : this.cancelledAt,
      cancelReason: data.cancelReason.present
          ? data.cancelReason.value
          : this.cancelReason,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
      localUpdatedAt: data.localUpdatedAt.present
          ? data.localUpdatedAt.value
          : this.localUpdatedAt,
      remoteUpdatedAt: data.remoteUpdatedAt.present
          ? data.remoteUpdatedAt.value
          : this.remoteUpdatedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedRide(')
          ..write('id: $id, ')
          ..write('passengerId: $passengerId, ')
          ..write('driverId: $driverId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('pickupLat: $pickupLat, ')
          ..write('pickupLng: $pickupLng, ')
          ..write('pickupAddress: $pickupAddress, ')
          ..write('dropoffLat: $dropoffLat, ')
          ..write('dropoffLng: $dropoffLng, ')
          ..write('dropoffAddress: $dropoffAddress, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('estimatedDurationMin: $estimatedDurationMin, ')
          ..write('fareAmount: $fareAmount, ')
          ..write('currency: $currency, ')
          ..write('platformFee: $platformFee, ')
          ..write('driverPayout: $driverPayout, ')
          ..write('status: $status, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('paymentReference: $paymentReference, ')
          ..write('blockchainLogHash: $blockchainLogHash, ')
          ..write('acceptedAt: $acceptedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        passengerId,
        driverId,
        vehicleId,
        pickupLat,
        pickupLng,
        pickupAddress,
        dropoffLat,
        dropoffLng,
        dropoffAddress,
        distanceKm,
        estimatedDurationMin,
        fareAmount,
        currency,
        platformFee,
        driverPayout,
        status,
        paymentStatus,
        paymentReference,
        blockchainLogHash,
        acceptedAt,
        startedAt,
        completedAt,
        cancelledAt,
        cancelReason,
        syncStatus,
        localUpdatedAt,
        remoteUpdatedAt,
        lastSyncedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRide &&
          other.id == this.id &&
          other.passengerId == this.passengerId &&
          other.driverId == this.driverId &&
          other.vehicleId == this.vehicleId &&
          other.pickupLat == this.pickupLat &&
          other.pickupLng == this.pickupLng &&
          other.pickupAddress == this.pickupAddress &&
          other.dropoffLat == this.dropoffLat &&
          other.dropoffLng == this.dropoffLng &&
          other.dropoffAddress == this.dropoffAddress &&
          other.distanceKm == this.distanceKm &&
          other.estimatedDurationMin == this.estimatedDurationMin &&
          other.fareAmount == this.fareAmount &&
          other.currency == this.currency &&
          other.platformFee == this.platformFee &&
          other.driverPayout == this.driverPayout &&
          other.status == this.status &&
          other.paymentStatus == this.paymentStatus &&
          other.paymentReference == this.paymentReference &&
          other.blockchainLogHash == this.blockchainLogHash &&
          other.acceptedAt == this.acceptedAt &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.cancelledAt == this.cancelledAt &&
          other.cancelReason == this.cancelReason &&
          other.syncStatus == this.syncStatus &&
          other.localUpdatedAt == this.localUpdatedAt &&
          other.remoteUpdatedAt == this.remoteUpdatedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class CachedRidesTableCompanion extends UpdateCompanion<CachedRide> {
  final Value<String> id;
  final Value<String> passengerId;
  final Value<String?> driverId;
  final Value<String?> vehicleId;
  final Value<double> pickupLat;
  final Value<double> pickupLng;
  final Value<String?> pickupAddress;
  final Value<double> dropoffLat;
  final Value<double> dropoffLng;
  final Value<String?> dropoffAddress;
  final Value<double> distanceKm;
  final Value<int> estimatedDurationMin;
  final Value<double> fareAmount;
  final Value<String> currency;
  final Value<double> platformFee;
  final Value<double> driverPayout;
  final Value<String> status;
  final Value<String> paymentStatus;
  final Value<String?> paymentReference;
  final Value<String?> blockchainLogHash;
  final Value<int?> acceptedAt;
  final Value<int?> startedAt;
  final Value<int?> completedAt;
  final Value<int?> cancelledAt;
  final Value<String?> cancelReason;
  final Value<EntitySyncStatus> syncStatus;
  final Value<int> localUpdatedAt;
  final Value<int> remoteUpdatedAt;
  final Value<int?> lastSyncedAt;
  final Value<int> rowid;
  const CachedRidesTableCompanion({
    this.id = const Value.absent(),
    this.passengerId = const Value.absent(),
    this.driverId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.pickupLat = const Value.absent(),
    this.pickupLng = const Value.absent(),
    this.pickupAddress = const Value.absent(),
    this.dropoffLat = const Value.absent(),
    this.dropoffLng = const Value.absent(),
    this.dropoffAddress = const Value.absent(),
    this.distanceKm = const Value.absent(),
    this.estimatedDurationMin = const Value.absent(),
    this.fareAmount = const Value.absent(),
    this.currency = const Value.absent(),
    this.platformFee = const Value.absent(),
    this.driverPayout = const Value.absent(),
    this.status = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.paymentReference = const Value.absent(),
    this.blockchainLogHash = const Value.absent(),
    this.acceptedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localUpdatedAt = const Value.absent(),
    this.remoteUpdatedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedRidesTableCompanion.insert({
    required String id,
    required String passengerId,
    this.driverId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    required double pickupLat,
    required double pickupLng,
    this.pickupAddress = const Value.absent(),
    required double dropoffLat,
    required double dropoffLng,
    this.dropoffAddress = const Value.absent(),
    required double distanceKm,
    required int estimatedDurationMin,
    required double fareAmount,
    this.currency = const Value.absent(),
    required double platformFee,
    required double driverPayout,
    required String status,
    required String paymentStatus,
    this.paymentReference = const Value.absent(),
    this.blockchainLogHash = const Value.absent(),
    this.acceptedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required int localUpdatedAt,
    required int remoteUpdatedAt,
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        passengerId = Value(passengerId),
        pickupLat = Value(pickupLat),
        pickupLng = Value(pickupLng),
        dropoffLat = Value(dropoffLat),
        dropoffLng = Value(dropoffLng),
        distanceKm = Value(distanceKm),
        estimatedDurationMin = Value(estimatedDurationMin),
        fareAmount = Value(fareAmount),
        platformFee = Value(platformFee),
        driverPayout = Value(driverPayout),
        status = Value(status),
        paymentStatus = Value(paymentStatus),
        localUpdatedAt = Value(localUpdatedAt),
        remoteUpdatedAt = Value(remoteUpdatedAt);
  static Insertable<CachedRide> custom({
    Expression<String>? id,
    Expression<String>? passengerId,
    Expression<String>? driverId,
    Expression<String>? vehicleId,
    Expression<double>? pickupLat,
    Expression<double>? pickupLng,
    Expression<String>? pickupAddress,
    Expression<double>? dropoffLat,
    Expression<double>? dropoffLng,
    Expression<String>? dropoffAddress,
    Expression<double>? distanceKm,
    Expression<int>? estimatedDurationMin,
    Expression<double>? fareAmount,
    Expression<String>? currency,
    Expression<double>? platformFee,
    Expression<double>? driverPayout,
    Expression<String>? status,
    Expression<String>? paymentStatus,
    Expression<String>? paymentReference,
    Expression<String>? blockchainLogHash,
    Expression<int>? acceptedAt,
    Expression<int>? startedAt,
    Expression<int>? completedAt,
    Expression<int>? cancelledAt,
    Expression<String>? cancelReason,
    Expression<String>? syncStatus,
    Expression<int>? localUpdatedAt,
    Expression<int>? remoteUpdatedAt,
    Expression<int>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (passengerId != null) 'passenger_id': passengerId,
      if (driverId != null) 'driver_id': driverId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (pickupLat != null) 'pickup_lat': pickupLat,
      if (pickupLng != null) 'pickup_lng': pickupLng,
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (dropoffLat != null) 'dropoff_lat': dropoffLat,
      if (dropoffLng != null) 'dropoff_lng': dropoffLng,
      if (dropoffAddress != null) 'dropoff_address': dropoffAddress,
      if (distanceKm != null) 'distance_km': distanceKm,
      if (estimatedDurationMin != null)
        'estimated_duration_min': estimatedDurationMin,
      if (fareAmount != null) 'fare_amount': fareAmount,
      if (currency != null) 'currency': currency,
      if (platformFee != null) 'platform_fee': platformFee,
      if (driverPayout != null) 'driver_payout': driverPayout,
      if (status != null) 'status': status,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (paymentReference != null) 'payment_reference': paymentReference,
      if (blockchainLogHash != null) 'blockchain_log_hash': blockchainLogHash,
      if (acceptedAt != null) 'accepted_at': acceptedAt,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
      if (cancelReason != null) 'cancel_reason': cancelReason,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (localUpdatedAt != null) 'local_updated_at': localUpdatedAt,
      if (remoteUpdatedAt != null) 'remote_updated_at': remoteUpdatedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedRidesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? passengerId,
      Value<String?>? driverId,
      Value<String?>? vehicleId,
      Value<double>? pickupLat,
      Value<double>? pickupLng,
      Value<String?>? pickupAddress,
      Value<double>? dropoffLat,
      Value<double>? dropoffLng,
      Value<String?>? dropoffAddress,
      Value<double>? distanceKm,
      Value<int>? estimatedDurationMin,
      Value<double>? fareAmount,
      Value<String>? currency,
      Value<double>? platformFee,
      Value<double>? driverPayout,
      Value<String>? status,
      Value<String>? paymentStatus,
      Value<String?>? paymentReference,
      Value<String?>? blockchainLogHash,
      Value<int?>? acceptedAt,
      Value<int?>? startedAt,
      Value<int?>? completedAt,
      Value<int?>? cancelledAt,
      Value<String?>? cancelReason,
      Value<EntitySyncStatus>? syncStatus,
      Value<int>? localUpdatedAt,
      Value<int>? remoteUpdatedAt,
      Value<int?>? lastSyncedAt,
      Value<int>? rowid}) {
    return CachedRidesTableCompanion(
      id: id ?? this.id,
      passengerId: passengerId ?? this.passengerId,
      driverId: driverId ?? this.driverId,
      vehicleId: vehicleId ?? this.vehicleId,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDurationMin: estimatedDurationMin ?? this.estimatedDurationMin,
      fareAmount: fareAmount ?? this.fareAmount,
      currency: currency ?? this.currency,
      platformFee: platformFee ?? this.platformFee,
      driverPayout: driverPayout ?? this.driverPayout,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentReference: paymentReference ?? this.paymentReference,
      blockchainLogHash: blockchainLogHash ?? this.blockchainLogHash,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      syncStatus: syncStatus ?? this.syncStatus,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (passengerId.present) {
      map['passenger_id'] = Variable<String>(passengerId.value);
    }
    if (driverId.present) {
      map['driver_id'] = Variable<String>(driverId.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (pickupLat.present) {
      map['pickup_lat'] = Variable<double>(pickupLat.value);
    }
    if (pickupLng.present) {
      map['pickup_lng'] = Variable<double>(pickupLng.value);
    }
    if (pickupAddress.present) {
      map['pickup_address'] = Variable<String>(pickupAddress.value);
    }
    if (dropoffLat.present) {
      map['dropoff_lat'] = Variable<double>(dropoffLat.value);
    }
    if (dropoffLng.present) {
      map['dropoff_lng'] = Variable<double>(dropoffLng.value);
    }
    if (dropoffAddress.present) {
      map['dropoff_address'] = Variable<String>(dropoffAddress.value);
    }
    if (distanceKm.present) {
      map['distance_km'] = Variable<double>(distanceKm.value);
    }
    if (estimatedDurationMin.present) {
      map['estimated_duration_min'] = Variable<int>(estimatedDurationMin.value);
    }
    if (fareAmount.present) {
      map['fare_amount'] = Variable<double>(fareAmount.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (platformFee.present) {
      map['platform_fee'] = Variable<double>(platformFee.value);
    }
    if (driverPayout.present) {
      map['driver_payout'] = Variable<double>(driverPayout.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (paymentStatus.present) {
      map['payment_status'] = Variable<String>(paymentStatus.value);
    }
    if (paymentReference.present) {
      map['payment_reference'] = Variable<String>(paymentReference.value);
    }
    if (blockchainLogHash.present) {
      map['blockchain_log_hash'] = Variable<String>(blockchainLogHash.value);
    }
    if (acceptedAt.present) {
      map['accepted_at'] = Variable<int>(acceptedAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (cancelledAt.present) {
      map['cancelled_at'] = Variable<int>(cancelledAt.value);
    }
    if (cancelReason.present) {
      map['cancel_reason'] = Variable<String>(cancelReason.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
          $CachedRidesTableTable.$convertersyncStatus.toSql(syncStatus.value));
    }
    if (localUpdatedAt.present) {
      map['local_updated_at'] = Variable<int>(localUpdatedAt.value);
    }
    if (remoteUpdatedAt.present) {
      map['remote_updated_at'] = Variable<int>(remoteUpdatedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedRidesTableCompanion(')
          ..write('id: $id, ')
          ..write('passengerId: $passengerId, ')
          ..write('driverId: $driverId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('pickupLat: $pickupLat, ')
          ..write('pickupLng: $pickupLng, ')
          ..write('pickupAddress: $pickupAddress, ')
          ..write('dropoffLat: $dropoffLat, ')
          ..write('dropoffLng: $dropoffLng, ')
          ..write('dropoffAddress: $dropoffAddress, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('estimatedDurationMin: $estimatedDurationMin, ')
          ..write('fareAmount: $fareAmount, ')
          ..write('currency: $currency, ')
          ..write('platformFee: $platformFee, ')
          ..write('driverPayout: $driverPayout, ')
          ..write('status: $status, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('paymentReference: $paymentReference, ')
          ..write('blockchainLogHash: $blockchainLogHash, ')
          ..write('acceptedAt: $acceptedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedWalletsTableTable extends CachedWalletsTable
    with TableInfo<$CachedWalletsTableTable, CachedWallet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedWalletsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _availableBalanceMeta =
      const VerificationMeta('availableBalance');
  @override
  late final GeneratedColumn<double> availableBalance = GeneratedColumn<double>(
      'available_balance', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pendingBalanceMeta =
      const VerificationMeta('pendingBalance');
  @override
  late final GeneratedColumn<double> pendingBalance = GeneratedColumn<double>(
      'pending_balance', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localUpdatedAtMeta =
      const VerificationMeta('localUpdatedAt');
  @override
  late final GeneratedColumn<int> localUpdatedAt = GeneratedColumn<int>(
      'local_updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _remoteUpdatedAtMeta =
      const VerificationMeta('remoteUpdatedAt');
  @override
  late final GeneratedColumn<int> remoteUpdatedAt = GeneratedColumn<int>(
      'remote_updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
      'last_synced_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        userId,
        availableBalance,
        pendingBalance,
        currency,
        localUpdatedAt,
        remoteUpdatedAt,
        lastSyncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_wallets_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedWallet> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('available_balance')) {
      context.handle(
          _availableBalanceMeta,
          availableBalance.isAcceptableOrUnknown(
              data['available_balance']!, _availableBalanceMeta));
    } else if (isInserting) {
      context.missing(_availableBalanceMeta);
    }
    if (data.containsKey('pending_balance')) {
      context.handle(
          _pendingBalanceMeta,
          pendingBalance.isAcceptableOrUnknown(
              data['pending_balance']!, _pendingBalanceMeta));
    } else if (isInserting) {
      context.missing(_pendingBalanceMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('local_updated_at')) {
      context.handle(
          _localUpdatedAtMeta,
          localUpdatedAt.isAcceptableOrUnknown(
              data['local_updated_at']!, _localUpdatedAtMeta));
    } else if (isInserting) {
      context.missing(_localUpdatedAtMeta);
    }
    if (data.containsKey('remote_updated_at')) {
      context.handle(
          _remoteUpdatedAtMeta,
          remoteUpdatedAt.isAcceptableOrUnknown(
              data['remote_updated_at']!, _remoteUpdatedAtMeta));
    } else if (isInserting) {
      context.missing(_remoteUpdatedAtMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedWallet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedWallet(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      availableBalance: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}available_balance'])!,
      pendingBalance: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}pending_balance'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      localUpdatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}local_updated_at'])!,
      remoteUpdatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_updated_at'])!,
      lastSyncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_synced_at']),
    );
  }

  @override
  $CachedWalletsTableTable createAlias(String alias) {
    return $CachedWalletsTableTable(attachedDatabase, alias);
  }
}

class CachedWallet extends DataClass implements Insertable<CachedWallet> {
  final String id;
  final String userId;
  final double availableBalance;
  final double pendingBalance;
  final String currency;
  final int localUpdatedAt;
  final int remoteUpdatedAt;
  final int? lastSyncedAt;
  const CachedWallet(
      {required this.id,
      required this.userId,
      required this.availableBalance,
      required this.pendingBalance,
      required this.currency,
      required this.localUpdatedAt,
      required this.remoteUpdatedAt,
      this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['available_balance'] = Variable<double>(availableBalance);
    map['pending_balance'] = Variable<double>(pendingBalance);
    map['currency'] = Variable<String>(currency);
    map['local_updated_at'] = Variable<int>(localUpdatedAt);
    map['remote_updated_at'] = Variable<int>(remoteUpdatedAt);
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt);
    }
    return map;
  }

  CachedWalletsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedWalletsTableCompanion(
      id: Value(id),
      userId: Value(userId),
      availableBalance: Value(availableBalance),
      pendingBalance: Value(pendingBalance),
      currency: Value(currency),
      localUpdatedAt: Value(localUpdatedAt),
      remoteUpdatedAt: Value(remoteUpdatedAt),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
    );
  }

  factory CachedWallet.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedWallet(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      availableBalance: serializer.fromJson<double>(json['availableBalance']),
      pendingBalance: serializer.fromJson<double>(json['pendingBalance']),
      currency: serializer.fromJson<String>(json['currency']),
      localUpdatedAt: serializer.fromJson<int>(json['localUpdatedAt']),
      remoteUpdatedAt: serializer.fromJson<int>(json['remoteUpdatedAt']),
      lastSyncedAt: serializer.fromJson<int?>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'availableBalance': serializer.toJson<double>(availableBalance),
      'pendingBalance': serializer.toJson<double>(pendingBalance),
      'currency': serializer.toJson<String>(currency),
      'localUpdatedAt': serializer.toJson<int>(localUpdatedAt),
      'remoteUpdatedAt': serializer.toJson<int>(remoteUpdatedAt),
      'lastSyncedAt': serializer.toJson<int?>(lastSyncedAt),
    };
  }

  CachedWallet copyWith(
          {String? id,
          String? userId,
          double? availableBalance,
          double? pendingBalance,
          String? currency,
          int? localUpdatedAt,
          int? remoteUpdatedAt,
          Value<int?> lastSyncedAt = const Value.absent()}) =>
      CachedWallet(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        availableBalance: availableBalance ?? this.availableBalance,
        pendingBalance: pendingBalance ?? this.pendingBalance,
        currency: currency ?? this.currency,
        localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
        lastSyncedAt:
            lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
      );
  CachedWallet copyWithCompanion(CachedWalletsTableCompanion data) {
    return CachedWallet(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      availableBalance: data.availableBalance.present
          ? data.availableBalance.value
          : this.availableBalance,
      pendingBalance: data.pendingBalance.present
          ? data.pendingBalance.value
          : this.pendingBalance,
      currency: data.currency.present ? data.currency.value : this.currency,
      localUpdatedAt: data.localUpdatedAt.present
          ? data.localUpdatedAt.value
          : this.localUpdatedAt,
      remoteUpdatedAt: data.remoteUpdatedAt.present
          ? data.remoteUpdatedAt.value
          : this.remoteUpdatedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedWallet(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('availableBalance: $availableBalance, ')
          ..write('pendingBalance: $pendingBalance, ')
          ..write('currency: $currency, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, availableBalance, pendingBalance,
      currency, localUpdatedAt, remoteUpdatedAt, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedWallet &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.availableBalance == this.availableBalance &&
          other.pendingBalance == this.pendingBalance &&
          other.currency == this.currency &&
          other.localUpdatedAt == this.localUpdatedAt &&
          other.remoteUpdatedAt == this.remoteUpdatedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class CachedWalletsTableCompanion extends UpdateCompanion<CachedWallet> {
  final Value<String> id;
  final Value<String> userId;
  final Value<double> availableBalance;
  final Value<double> pendingBalance;
  final Value<String> currency;
  final Value<int> localUpdatedAt;
  final Value<int> remoteUpdatedAt;
  final Value<int?> lastSyncedAt;
  final Value<int> rowid;
  const CachedWalletsTableCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.availableBalance = const Value.absent(),
    this.pendingBalance = const Value.absent(),
    this.currency = const Value.absent(),
    this.localUpdatedAt = const Value.absent(),
    this.remoteUpdatedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedWalletsTableCompanion.insert({
    required String id,
    required String userId,
    required double availableBalance,
    required double pendingBalance,
    required String currency,
    required int localUpdatedAt,
    required int remoteUpdatedAt,
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        userId = Value(userId),
        availableBalance = Value(availableBalance),
        pendingBalance = Value(pendingBalance),
        currency = Value(currency),
        localUpdatedAt = Value(localUpdatedAt),
        remoteUpdatedAt = Value(remoteUpdatedAt);
  static Insertable<CachedWallet> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<double>? availableBalance,
    Expression<double>? pendingBalance,
    Expression<String>? currency,
    Expression<int>? localUpdatedAt,
    Expression<int>? remoteUpdatedAt,
    Expression<int>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (availableBalance != null) 'available_balance': availableBalance,
      if (pendingBalance != null) 'pending_balance': pendingBalance,
      if (currency != null) 'currency': currency,
      if (localUpdatedAt != null) 'local_updated_at': localUpdatedAt,
      if (remoteUpdatedAt != null) 'remote_updated_at': remoteUpdatedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedWalletsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? userId,
      Value<double>? availableBalance,
      Value<double>? pendingBalance,
      Value<String>? currency,
      Value<int>? localUpdatedAt,
      Value<int>? remoteUpdatedAt,
      Value<int?>? lastSyncedAt,
      Value<int>? rowid}) {
    return CachedWalletsTableCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      availableBalance: availableBalance ?? this.availableBalance,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      currency: currency ?? this.currency,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (availableBalance.present) {
      map['available_balance'] = Variable<double>(availableBalance.value);
    }
    if (pendingBalance.present) {
      map['pending_balance'] = Variable<double>(pendingBalance.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (localUpdatedAt.present) {
      map['local_updated_at'] = Variable<int>(localUpdatedAt.value);
    }
    if (remoteUpdatedAt.present) {
      map['remote_updated_at'] = Variable<int>(remoteUpdatedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedWalletsTableCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('availableBalance: $availableBalance, ')
          ..write('pendingBalance: $pendingBalance, ')
          ..write('currency: $currency, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedTransactionsTableTable extends CachedTransactionsTable
    with TableInfo<$CachedTransactionsTableTable, CachedTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTransactionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _walletIdMeta =
      const VerificationMeta('walletId');
  @override
  late final GeneratedColumn<String> walletId = GeneratedColumn<String>(
      'wallet_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _referenceTypeMeta =
      const VerificationMeta('referenceType');
  @override
  late final GeneratedColumn<String> referenceType = GeneratedColumn<String>(
      'reference_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
      'reference_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _blockchainTxHashMeta =
      const VerificationMeta('blockchainTxHash');
  @override
  late final GeneratedColumn<String> blockchainTxHash = GeneratedColumn<String>(
      'blockchain_tx_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _remoteCreatedAtMeta =
      const VerificationMeta('remoteCreatedAt');
  @override
  late final GeneratedColumn<int> remoteCreatedAt = GeneratedColumn<int>(
      'remote_created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        walletId,
        userId,
        type,
        amount,
        currency,
        referenceType,
        referenceId,
        status,
        description,
        blockchainTxHash,
        remoteCreatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_transactions_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('wallet_id')) {
      context.handle(_walletIdMeta,
          walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta));
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('reference_type')) {
      context.handle(
          _referenceTypeMeta,
          referenceType.isAcceptableOrUnknown(
              data['reference_type']!, _referenceTypeMeta));
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('blockchain_tx_hash')) {
      context.handle(
          _blockchainTxHashMeta,
          blockchainTxHash.isAcceptableOrUnknown(
              data['blockchain_tx_hash']!, _blockchainTxHashMeta));
    }
    if (data.containsKey('remote_created_at')) {
      context.handle(
          _remoteCreatedAtMeta,
          remoteCreatedAt.isAcceptableOrUnknown(
              data['remote_created_at']!, _remoteCreatedAtMeta));
    } else if (isInserting) {
      context.missing(_remoteCreatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTransaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      walletId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}wallet_id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      referenceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_type']),
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_id']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      blockchainTxHash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}blockchain_tx_hash']),
      remoteCreatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_created_at'])!,
    );
  }

  @override
  $CachedTransactionsTableTable createAlias(String alias) {
    return $CachedTransactionsTableTable(attachedDatabase, alias);
  }
}

class CachedTransaction extends DataClass
    implements Insertable<CachedTransaction> {
  final String id;
  final String walletId;
  final String userId;
  final String type;
  final double amount;
  final String currency;
  final String? referenceType;
  final String? referenceId;
  final String status;
  final String? description;
  final String? blockchainTxHash;
  final int remoteCreatedAt;
  const CachedTransaction(
      {required this.id,
      required this.walletId,
      required this.userId,
      required this.type,
      required this.amount,
      required this.currency,
      this.referenceType,
      this.referenceId,
      required this.status,
      this.description,
      this.blockchainTxHash,
      required this.remoteCreatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['wallet_id'] = Variable<String>(walletId);
    map['user_id'] = Variable<String>(userId);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || referenceType != null) {
      map['reference_type'] = Variable<String>(referenceType);
    }
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || blockchainTxHash != null) {
      map['blockchain_tx_hash'] = Variable<String>(blockchainTxHash);
    }
    map['remote_created_at'] = Variable<int>(remoteCreatedAt);
    return map;
  }

  CachedTransactionsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedTransactionsTableCompanion(
      id: Value(id),
      walletId: Value(walletId),
      userId: Value(userId),
      type: Value(type),
      amount: Value(amount),
      currency: Value(currency),
      referenceType: referenceType == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceType),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      status: Value(status),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      blockchainTxHash: blockchainTxHash == null && nullToAbsent
          ? const Value.absent()
          : Value(blockchainTxHash),
      remoteCreatedAt: Value(remoteCreatedAt),
    );
  }

  factory CachedTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTransaction(
      id: serializer.fromJson<String>(json['id']),
      walletId: serializer.fromJson<String>(json['walletId']),
      userId: serializer.fromJson<String>(json['userId']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      currency: serializer.fromJson<String>(json['currency']),
      referenceType: serializer.fromJson<String?>(json['referenceType']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      status: serializer.fromJson<String>(json['status']),
      description: serializer.fromJson<String?>(json['description']),
      blockchainTxHash: serializer.fromJson<String?>(json['blockchainTxHash']),
      remoteCreatedAt: serializer.fromJson<int>(json['remoteCreatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'walletId': serializer.toJson<String>(walletId),
      'userId': serializer.toJson<String>(userId),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'currency': serializer.toJson<String>(currency),
      'referenceType': serializer.toJson<String?>(referenceType),
      'referenceId': serializer.toJson<String?>(referenceId),
      'status': serializer.toJson<String>(status),
      'description': serializer.toJson<String?>(description),
      'blockchainTxHash': serializer.toJson<String?>(blockchainTxHash),
      'remoteCreatedAt': serializer.toJson<int>(remoteCreatedAt),
    };
  }

  CachedTransaction copyWith(
          {String? id,
          String? walletId,
          String? userId,
          String? type,
          double? amount,
          String? currency,
          Value<String?> referenceType = const Value.absent(),
          Value<String?> referenceId = const Value.absent(),
          String? status,
          Value<String?> description = const Value.absent(),
          Value<String?> blockchainTxHash = const Value.absent(),
          int? remoteCreatedAt}) =>
      CachedTransaction(
        id: id ?? this.id,
        walletId: walletId ?? this.walletId,
        userId: userId ?? this.userId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        referenceType:
            referenceType.present ? referenceType.value : this.referenceType,
        referenceId: referenceId.present ? referenceId.value : this.referenceId,
        status: status ?? this.status,
        description: description.present ? description.value : this.description,
        blockchainTxHash: blockchainTxHash.present
            ? blockchainTxHash.value
            : this.blockchainTxHash,
        remoteCreatedAt: remoteCreatedAt ?? this.remoteCreatedAt,
      );
  CachedTransaction copyWithCompanion(CachedTransactionsTableCompanion data) {
    return CachedTransaction(
      id: data.id.present ? data.id.value : this.id,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      userId: data.userId.present ? data.userId.value : this.userId,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      currency: data.currency.present ? data.currency.value : this.currency,
      referenceType: data.referenceType.present
          ? data.referenceType.value
          : this.referenceType,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      status: data.status.present ? data.status.value : this.status,
      description:
          data.description.present ? data.description.value : this.description,
      blockchainTxHash: data.blockchainTxHash.present
          ? data.blockchainTxHash.value
          : this.blockchainTxHash,
      remoteCreatedAt: data.remoteCreatedAt.present
          ? data.remoteCreatedAt.value
          : this.remoteCreatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTransaction(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('userId: $userId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('currency: $currency, ')
          ..write('referenceType: $referenceType, ')
          ..write('referenceId: $referenceId, ')
          ..write('status: $status, ')
          ..write('description: $description, ')
          ..write('blockchainTxHash: $blockchainTxHash, ')
          ..write('remoteCreatedAt: $remoteCreatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      walletId,
      userId,
      type,
      amount,
      currency,
      referenceType,
      referenceId,
      status,
      description,
      blockchainTxHash,
      remoteCreatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTransaction &&
          other.id == this.id &&
          other.walletId == this.walletId &&
          other.userId == this.userId &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.currency == this.currency &&
          other.referenceType == this.referenceType &&
          other.referenceId == this.referenceId &&
          other.status == this.status &&
          other.description == this.description &&
          other.blockchainTxHash == this.blockchainTxHash &&
          other.remoteCreatedAt == this.remoteCreatedAt);
}

class CachedTransactionsTableCompanion
    extends UpdateCompanion<CachedTransaction> {
  final Value<String> id;
  final Value<String> walletId;
  final Value<String> userId;
  final Value<String> type;
  final Value<double> amount;
  final Value<String> currency;
  final Value<String?> referenceType;
  final Value<String?> referenceId;
  final Value<String> status;
  final Value<String?> description;
  final Value<String?> blockchainTxHash;
  final Value<int> remoteCreatedAt;
  final Value<int> rowid;
  const CachedTransactionsTableCompanion({
    this.id = const Value.absent(),
    this.walletId = const Value.absent(),
    this.userId = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.currency = const Value.absent(),
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.status = const Value.absent(),
    this.description = const Value.absent(),
    this.blockchainTxHash = const Value.absent(),
    this.remoteCreatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTransactionsTableCompanion.insert({
    required String id,
    required String walletId,
    required String userId,
    required String type,
    required double amount,
    required String currency,
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    required String status,
    this.description = const Value.absent(),
    this.blockchainTxHash = const Value.absent(),
    required int remoteCreatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        walletId = Value(walletId),
        userId = Value(userId),
        type = Value(type),
        amount = Value(amount),
        currency = Value(currency),
        status = Value(status),
        remoteCreatedAt = Value(remoteCreatedAt);
  static Insertable<CachedTransaction> custom({
    Expression<String>? id,
    Expression<String>? walletId,
    Expression<String>? userId,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<String>? currency,
    Expression<String>? referenceType,
    Expression<String>? referenceId,
    Expression<String>? status,
    Expression<String>? description,
    Expression<String>? blockchainTxHash,
    Expression<int>? remoteCreatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (walletId != null) 'wallet_id': walletId,
      if (userId != null) 'user_id': userId,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (currency != null) 'currency': currency,
      if (referenceType != null) 'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      if (status != null) 'status': status,
      if (description != null) 'description': description,
      if (blockchainTxHash != null) 'blockchain_tx_hash': blockchainTxHash,
      if (remoteCreatedAt != null) 'remote_created_at': remoteCreatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTransactionsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? walletId,
      Value<String>? userId,
      Value<String>? type,
      Value<double>? amount,
      Value<String>? currency,
      Value<String?>? referenceType,
      Value<String?>? referenceId,
      Value<String>? status,
      Value<String?>? description,
      Value<String?>? blockchainTxHash,
      Value<int>? remoteCreatedAt,
      Value<int>? rowid}) {
    return CachedTransactionsTableCompanion(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      status: status ?? this.status,
      description: description ?? this.description,
      blockchainTxHash: blockchainTxHash ?? this.blockchainTxHash,
      remoteCreatedAt: remoteCreatedAt ?? this.remoteCreatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (referenceType.present) {
      map['reference_type'] = Variable<String>(referenceType.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (blockchainTxHash.present) {
      map['blockchain_tx_hash'] = Variable<String>(blockchainTxHash.value);
    }
    if (remoteCreatedAt.present) {
      map['remote_created_at'] = Variable<int>(remoteCreatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTransactionsTableCompanion(')
          ..write('id: $id, ')
          ..write('walletId: $walletId, ')
          ..write('userId: $userId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('currency: $currency, ')
          ..write('referenceType: $referenceType, ')
          ..write('referenceId: $referenceId, ')
          ..write('status: $status, ')
          ..write('description: $description, ')
          ..write('blockchainTxHash: $blockchainTxHash, ')
          ..write('remoteCreatedAt: $remoteCreatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedUsersTableTable extends CachedUsersTable
    with TableInfo<$CachedUsersTableTable, CachedUser> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedUsersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isVerifiedMeta =
      const VerificationMeta('isVerified');
  @override
  late final GeneratedColumn<bool> isVerified = GeneratedColumn<bool>(
      'is_verified', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_verified" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _avatarUrlMeta =
      const VerificationMeta('avatarUrl');
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
      'avatar_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _walletAddressMeta =
      const VerificationMeta('walletAddress');
  @override
  late final GeneratedColumn<String> walletAddress = GeneratedColumn<String>(
      'wallet_address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sessionTokenMeta =
      const VerificationMeta('sessionToken');
  @override
  late final GeneratedColumn<String> sessionToken = GeneratedColumn<String>(
      'session_token', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveSessionMeta =
      const VerificationMeta('isActiveSession');
  @override
  late final GeneratedColumn<bool> isActiveSession = GeneratedColumn<bool>(
      'is_active_session', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_active_session" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        email,
        phone,
        role,
        isVerified,
        avatarUrl,
        walletAddress,
        sessionToken,
        isActiveSession,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_users_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedUser> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('is_verified')) {
      context.handle(
          _isVerifiedMeta,
          isVerified.isAcceptableOrUnknown(
              data['is_verified']!, _isVerifiedMeta));
    }
    if (data.containsKey('avatar_url')) {
      context.handle(_avatarUrlMeta,
          avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta));
    }
    if (data.containsKey('wallet_address')) {
      context.handle(
          _walletAddressMeta,
          walletAddress.isAcceptableOrUnknown(
              data['wallet_address']!, _walletAddressMeta));
    }
    if (data.containsKey('session_token')) {
      context.handle(
          _sessionTokenMeta,
          sessionToken.isAcceptableOrUnknown(
              data['session_token']!, _sessionTokenMeta));
    }
    if (data.containsKey('is_active_session')) {
      context.handle(
          _isActiveSessionMeta,
          isActiveSession.isAcceptableOrUnknown(
              data['is_active_session']!, _isActiveSessionMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedUser map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedUser(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      isVerified: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_verified'])!,
      avatarUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_url']),
      walletAddress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}wallet_address']),
      sessionToken: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_token']),
      isActiveSession: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_active_session'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedUsersTableTable createAlias(String alias) {
    return $CachedUsersTableTable(attachedDatabase, alias);
  }
}

class CachedUser extends DataClass implements Insertable<CachedUser> {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final bool isVerified;
  final String? avatarUrl;
  final String? walletAddress;
  final String? sessionToken;
  final bool isActiveSession;
  final int cachedAt;
  const CachedUser(
      {required this.id,
      required this.name,
      required this.email,
      required this.phone,
      required this.role,
      required this.isVerified,
      this.avatarUrl,
      this.walletAddress,
      this.sessionToken,
      required this.isActiveSession,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['email'] = Variable<String>(email);
    map['phone'] = Variable<String>(phone);
    map['role'] = Variable<String>(role);
    map['is_verified'] = Variable<bool>(isVerified);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || walletAddress != null) {
      map['wallet_address'] = Variable<String>(walletAddress);
    }
    if (!nullToAbsent || sessionToken != null) {
      map['session_token'] = Variable<String>(sessionToken);
    }
    map['is_active_session'] = Variable<bool>(isActiveSession);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedUsersTableCompanion toCompanion(bool nullToAbsent) {
    return CachedUsersTableCompanion(
      id: Value(id),
      name: Value(name),
      email: Value(email),
      phone: Value(phone),
      role: Value(role),
      isVerified: Value(isVerified),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      walletAddress: walletAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(walletAddress),
      sessionToken: sessionToken == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionToken),
      isActiveSession: Value(isActiveSession),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedUser.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedUser(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      email: serializer.fromJson<String>(json['email']),
      phone: serializer.fromJson<String>(json['phone']),
      role: serializer.fromJson<String>(json['role']),
      isVerified: serializer.fromJson<bool>(json['isVerified']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      walletAddress: serializer.fromJson<String?>(json['walletAddress']),
      sessionToken: serializer.fromJson<String?>(json['sessionToken']),
      isActiveSession: serializer.fromJson<bool>(json['isActiveSession']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'email': serializer.toJson<String>(email),
      'phone': serializer.toJson<String>(phone),
      'role': serializer.toJson<String>(role),
      'isVerified': serializer.toJson<bool>(isVerified),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'walletAddress': serializer.toJson<String?>(walletAddress),
      'sessionToken': serializer.toJson<String?>(sessionToken),
      'isActiveSession': serializer.toJson<bool>(isActiveSession),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedUser copyWith(
          {String? id,
          String? name,
          String? email,
          String? phone,
          String? role,
          bool? isVerified,
          Value<String?> avatarUrl = const Value.absent(),
          Value<String?> walletAddress = const Value.absent(),
          Value<String?> sessionToken = const Value.absent(),
          bool? isActiveSession,
          int? cachedAt}) =>
      CachedUser(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        isVerified: isVerified ?? this.isVerified,
        avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
        walletAddress:
            walletAddress.present ? walletAddress.value : this.walletAddress,
        sessionToken:
            sessionToken.present ? sessionToken.value : this.sessionToken,
        isActiveSession: isActiveSession ?? this.isActiveSession,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedUser copyWithCompanion(CachedUsersTableCompanion data) {
    return CachedUser(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      email: data.email.present ? data.email.value : this.email,
      phone: data.phone.present ? data.phone.value : this.phone,
      role: data.role.present ? data.role.value : this.role,
      isVerified:
          data.isVerified.present ? data.isVerified.value : this.isVerified,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      walletAddress: data.walletAddress.present
          ? data.walletAddress.value
          : this.walletAddress,
      sessionToken: data.sessionToken.present
          ? data.sessionToken.value
          : this.sessionToken,
      isActiveSession: data.isActiveSession.present
          ? data.isActiveSession.value
          : this.isActiveSession,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedUser(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('role: $role, ')
          ..write('isVerified: $isVerified, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('walletAddress: $walletAddress, ')
          ..write('sessionToken: $sessionToken, ')
          ..write('isActiveSession: $isActiveSession, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, email, phone, role, isVerified,
      avatarUrl, walletAddress, sessionToken, isActiveSession, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedUser &&
          other.id == this.id &&
          other.name == this.name &&
          other.email == this.email &&
          other.phone == this.phone &&
          other.role == this.role &&
          other.isVerified == this.isVerified &&
          other.avatarUrl == this.avatarUrl &&
          other.walletAddress == this.walletAddress &&
          other.sessionToken == this.sessionToken &&
          other.isActiveSession == this.isActiveSession &&
          other.cachedAt == this.cachedAt);
}

class CachedUsersTableCompanion extends UpdateCompanion<CachedUser> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> email;
  final Value<String> phone;
  final Value<String> role;
  final Value<bool> isVerified;
  final Value<String?> avatarUrl;
  final Value<String?> walletAddress;
  final Value<String?> sessionToken;
  final Value<bool> isActiveSession;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedUsersTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.role = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.walletAddress = const Value.absent(),
    this.sessionToken = const Value.absent(),
    this.isActiveSession = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedUsersTableCompanion.insert({
    required String id,
    required String name,
    required String email,
    required String phone,
    required String role,
    this.isVerified = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.walletAddress = const Value.absent(),
    this.sessionToken = const Value.absent(),
    this.isActiveSession = const Value.absent(),
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        email = Value(email),
        phone = Value(phone),
        role = Value(role),
        cachedAt = Value(cachedAt);
  static Insertable<CachedUser> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? email,
    Expression<String>? phone,
    Expression<String>? role,
    Expression<bool>? isVerified,
    Expression<String>? avatarUrl,
    Expression<String>? walletAddress,
    Expression<String>? sessionToken,
    Expression<bool>? isActiveSession,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (role != null) 'role': role,
      if (isVerified != null) 'is_verified': isVerified,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (walletAddress != null) 'wallet_address': walletAddress,
      if (sessionToken != null) 'session_token': sessionToken,
      if (isActiveSession != null) 'is_active_session': isActiveSession,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedUsersTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? email,
      Value<String>? phone,
      Value<String>? role,
      Value<bool>? isVerified,
      Value<String?>? avatarUrl,
      Value<String?>? walletAddress,
      Value<String?>? sessionToken,
      Value<bool>? isActiveSession,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedUsersTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      walletAddress: walletAddress ?? this.walletAddress,
      sessionToken: sessionToken ?? this.sessionToken,
      isActiveSession: isActiveSession ?? this.isActiveSession,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (isVerified.present) {
      map['is_verified'] = Variable<bool>(isVerified.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (walletAddress.present) {
      map['wallet_address'] = Variable<String>(walletAddress.value);
    }
    if (sessionToken.present) {
      map['session_token'] = Variable<String>(sessionToken.value);
    }
    if (isActiveSession.present) {
      map['is_active_session'] = Variable<bool>(isActiveSession.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedUsersTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('role: $role, ')
          ..write('isVerified: $isVerified, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('walletAddress: $walletAddress, ')
          ..write('sessionToken: $sessionToken, ')
          ..write('isActiveSession: $isActiveSession, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPropertyListingsTableTable extends CachedPropertyListingsTable
    with TableInfo<$CachedPropertyListingsTableTable, CachedPropertyListing> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPropertyListingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _hourlyRateMeta =
      const VerificationMeta('hourlyRate');
  @override
  late final GeneratedColumn<double> hourlyRate = GeneratedColumn<double>(
      'hourly_rate', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _primaryImageUrlMeta =
      const VerificationMeta('primaryImageUrl');
  @override
  late final GeneratedColumn<String> primaryImageUrl = GeneratedColumn<String>(
      'primary_image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ownerId,
        title,
        description,
        category,
        price,
        hourlyRate,
        address,
        latitude,
        longitude,
        primaryImageUrl,
        isSynced,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_property_listings_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<CachedPropertyListing> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('hourly_rate')) {
      context.handle(
          _hourlyRateMeta,
          hourlyRate.isAcceptableOrUnknown(
              data['hourly_rate']!, _hourlyRateMeta));
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('primary_image_url')) {
      context.handle(
          _primaryImageUrlMeta,
          primaryImageUrl.isAcceptableOrUnknown(
              data['primary_image_url']!, _primaryImageUrlMeta));
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedPropertyListing map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPropertyListing(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      hourlyRate: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}hourly_rate']),
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      primaryImageUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}primary_image_url']),
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedPropertyListingsTableTable createAlias(String alias) {
    return $CachedPropertyListingsTableTable(attachedDatabase, alias);
  }
}

class CachedPropertyListing extends DataClass
    implements Insertable<CachedPropertyListing> {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final String category;
  final double price;
  final double? hourlyRate;
  final String address;
  final double latitude;
  final double longitude;
  final String? primaryImageUrl;
  final bool isSynced;
  final int cachedAt;
  const CachedPropertyListing(
      {required this.id,
      required this.ownerId,
      required this.title,
      required this.description,
      required this.category,
      required this.price,
      this.hourlyRate,
      required this.address,
      required this.latitude,
      required this.longitude,
      this.primaryImageUrl,
      required this.isSynced,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['category'] = Variable<String>(category);
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || hourlyRate != null) {
      map['hourly_rate'] = Variable<double>(hourlyRate);
    }
    map['address'] = Variable<String>(address);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || primaryImageUrl != null) {
      map['primary_image_url'] = Variable<String>(primaryImageUrl);
    }
    map['is_synced'] = Variable<bool>(isSynced);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedPropertyListingsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedPropertyListingsTableCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      title: Value(title),
      description: Value(description),
      category: Value(category),
      price: Value(price),
      hourlyRate: hourlyRate == null && nullToAbsent
          ? const Value.absent()
          : Value(hourlyRate),
      address: Value(address),
      latitude: Value(latitude),
      longitude: Value(longitude),
      primaryImageUrl: primaryImageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(primaryImageUrl),
      isSynced: Value(isSynced),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedPropertyListing.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPropertyListing(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      category: serializer.fromJson<String>(json['category']),
      price: serializer.fromJson<double>(json['price']),
      hourlyRate: serializer.fromJson<double?>(json['hourlyRate']),
      address: serializer.fromJson<String>(json['address']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      primaryImageUrl: serializer.fromJson<String?>(json['primaryImageUrl']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'category': serializer.toJson<String>(category),
      'price': serializer.toJson<double>(price),
      'hourlyRate': serializer.toJson<double?>(hourlyRate),
      'address': serializer.toJson<String>(address),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'primaryImageUrl': serializer.toJson<String?>(primaryImageUrl),
      'isSynced': serializer.toJson<bool>(isSynced),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedPropertyListing copyWith(
          {String? id,
          String? ownerId,
          String? title,
          String? description,
          String? category,
          double? price,
          Value<double?> hourlyRate = const Value.absent(),
          String? address,
          double? latitude,
          double? longitude,
          Value<String?> primaryImageUrl = const Value.absent(),
          bool? isSynced,
          int? cachedAt}) =>
      CachedPropertyListing(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        price: price ?? this.price,
        hourlyRate: hourlyRate.present ? hourlyRate.value : this.hourlyRate,
        address: address ?? this.address,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        primaryImageUrl: primaryImageUrl.present
            ? primaryImageUrl.value
            : this.primaryImageUrl,
        isSynced: isSynced ?? this.isSynced,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedPropertyListing copyWithCompanion(
      CachedPropertyListingsTableCompanion data) {
    return CachedPropertyListing(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      category: data.category.present ? data.category.value : this.category,
      price: data.price.present ? data.price.value : this.price,
      hourlyRate:
          data.hourlyRate.present ? data.hourlyRate.value : this.hourlyRate,
      address: data.address.present ? data.address.value : this.address,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      primaryImageUrl: data.primaryImageUrl.present
          ? data.primaryImageUrl.value
          : this.primaryImageUrl,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPropertyListing(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('price: $price, ')
          ..write('hourlyRate: $hourlyRate, ')
          ..write('address: $address, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('primaryImageUrl: $primaryImageUrl, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      ownerId,
      title,
      description,
      category,
      price,
      hourlyRate,
      address,
      latitude,
      longitude,
      primaryImageUrl,
      isSynced,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPropertyListing &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.title == this.title &&
          other.description == this.description &&
          other.category == this.category &&
          other.price == this.price &&
          other.hourlyRate == this.hourlyRate &&
          other.address == this.address &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.primaryImageUrl == this.primaryImageUrl &&
          other.isSynced == this.isSynced &&
          other.cachedAt == this.cachedAt);
}

class CachedPropertyListingsTableCompanion
    extends UpdateCompanion<CachedPropertyListing> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> title;
  final Value<String> description;
  final Value<String> category;
  final Value<double> price;
  final Value<double?> hourlyRate;
  final Value<String> address;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<String?> primaryImageUrl;
  final Value<bool> isSynced;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedPropertyListingsTableCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.price = const Value.absent(),
    this.hourlyRate = const Value.absent(),
    this.address = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.primaryImageUrl = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPropertyListingsTableCompanion.insert({
    required String id,
    required String ownerId,
    required String title,
    required String description,
    required String category,
    required double price,
    this.hourlyRate = const Value.absent(),
    required String address,
    required double latitude,
    required double longitude,
    this.primaryImageUrl = const Value.absent(),
    this.isSynced = const Value.absent(),
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ownerId = Value(ownerId),
        title = Value(title),
        description = Value(description),
        category = Value(category),
        price = Value(price),
        address = Value(address),
        latitude = Value(latitude),
        longitude = Value(longitude),
        cachedAt = Value(cachedAt);
  static Insertable<CachedPropertyListing> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? category,
    Expression<double>? price,
    Expression<double>? hourlyRate,
    Expression<String>? address,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? primaryImageUrl,
    Expression<bool>? isSynced,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (price != null) 'price': price,
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
      if (address != null) 'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (primaryImageUrl != null) 'primary_image_url': primaryImageUrl,
      if (isSynced != null) 'is_synced': isSynced,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPropertyListingsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? ownerId,
      Value<String>? title,
      Value<String>? description,
      Value<String>? category,
      Value<double>? price,
      Value<double?>? hourlyRate,
      Value<String>? address,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<String?>? primaryImageUrl,
      Value<bool>? isSynced,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedPropertyListingsTableCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      primaryImageUrl: primaryImageUrl ?? this.primaryImageUrl,
      isSynced: isSynced ?? this.isSynced,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (hourlyRate.present) {
      map['hourly_rate'] = Variable<double>(hourlyRate.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (primaryImageUrl.present) {
      map['primary_image_url'] = Variable<String>(primaryImageUrl.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPropertyListingsTableCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('price: $price, ')
          ..write('hourlyRate: $hourlyRate, ')
          ..write('address: $address, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('primaryImageUrl: $primaryImageUrl, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedVehicleListingsTableTable extends CachedVehicleListingsTable
    with TableInfo<$CachedVehicleListingsTableTable, CachedVehicleListing> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedVehicleListingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _vehicleTypeMeta =
      const VerificationMeta('vehicleType');
  @override
  late final GeneratedColumn<String> vehicleType = GeneratedColumn<String>(
      'vehicle_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _listingIntentMeta =
      const VerificationMeta('listingIntent');
  @override
  late final GeneratedColumn<String> listingIntent = GeneratedColumn<String>(
      'listing_intent', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _makeMeta = const VerificationMeta('make');
  @override
  late final GeneratedColumn<String> make = GeneratedColumn<String>(
      'make', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _pricePerKmMeta =
      const VerificationMeta('pricePerKm');
  @override
  late final GeneratedColumn<double> pricePerKm = GeneratedColumn<double>(
      'price_per_km', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _pricePerDayMeta =
      const VerificationMeta('pricePerDay');
  @override
  late final GeneratedColumn<double> pricePerDay = GeneratedColumn<double>(
      'price_per_day', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _salePriceMeta =
      const VerificationMeta('salePrice');
  @override
  late final GeneratedColumn<double> salePrice = GeneratedColumn<double>(
      'sale_price', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _primaryImageUrlMeta =
      const VerificationMeta('primaryImageUrl');
  @override
  late final GeneratedColumn<String> primaryImageUrl = GeneratedColumn<String>(
      'primary_image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        ownerId,
        vehicleType,
        listingIntent,
        make,
        model,
        year,
        pricePerKm,
        pricePerDay,
        salePrice,
        primaryImageUrl,
        isSynced,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_vehicle_listings_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<CachedVehicleListing> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('vehicle_type')) {
      context.handle(
          _vehicleTypeMeta,
          vehicleType.isAcceptableOrUnknown(
              data['vehicle_type']!, _vehicleTypeMeta));
    } else if (isInserting) {
      context.missing(_vehicleTypeMeta);
    }
    if (data.containsKey('listing_intent')) {
      context.handle(
          _listingIntentMeta,
          listingIntent.isAcceptableOrUnknown(
              data['listing_intent']!, _listingIntentMeta));
    } else if (isInserting) {
      context.missing(_listingIntentMeta);
    }
    if (data.containsKey('make')) {
      context.handle(
          _makeMeta, make.isAcceptableOrUnknown(data['make']!, _makeMeta));
    } else if (isInserting) {
      context.missing(_makeMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('price_per_km')) {
      context.handle(
          _pricePerKmMeta,
          pricePerKm.isAcceptableOrUnknown(
              data['price_per_km']!, _pricePerKmMeta));
    }
    if (data.containsKey('price_per_day')) {
      context.handle(
          _pricePerDayMeta,
          pricePerDay.isAcceptableOrUnknown(
              data['price_per_day']!, _pricePerDayMeta));
    }
    if (data.containsKey('sale_price')) {
      context.handle(_salePriceMeta,
          salePrice.isAcceptableOrUnknown(data['sale_price']!, _salePriceMeta));
    }
    if (data.containsKey('primary_image_url')) {
      context.handle(
          _primaryImageUrlMeta,
          primaryImageUrl.isAcceptableOrUnknown(
              data['primary_image_url']!, _primaryImageUrlMeta));
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedVehicleListing map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedVehicleListing(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      vehicleType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}vehicle_type'])!,
      listingIntent: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}listing_intent'])!,
      make: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}make'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year'])!,
      pricePerKm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price_per_km']),
      pricePerDay: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price_per_day']),
      salePrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}sale_price']),
      primaryImageUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}primary_image_url']),
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedVehicleListingsTableTable createAlias(String alias) {
    return $CachedVehicleListingsTableTable(attachedDatabase, alias);
  }
}

class CachedVehicleListing extends DataClass
    implements Insertable<CachedVehicleListing> {
  final String id;
  final String ownerId;
  final String vehicleType;
  final String listingIntent;
  final String make;
  final String model;
  final int year;
  final double? pricePerKm;
  final double? pricePerDay;
  final double? salePrice;
  final String? primaryImageUrl;
  final bool isSynced;
  final int cachedAt;
  const CachedVehicleListing(
      {required this.id,
      required this.ownerId,
      required this.vehicleType,
      required this.listingIntent,
      required this.make,
      required this.model,
      required this.year,
      this.pricePerKm,
      this.pricePerDay,
      this.salePrice,
      this.primaryImageUrl,
      required this.isSynced,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['vehicle_type'] = Variable<String>(vehicleType);
    map['listing_intent'] = Variable<String>(listingIntent);
    map['make'] = Variable<String>(make);
    map['model'] = Variable<String>(model);
    map['year'] = Variable<int>(year);
    if (!nullToAbsent || pricePerKm != null) {
      map['price_per_km'] = Variable<double>(pricePerKm);
    }
    if (!nullToAbsent || pricePerDay != null) {
      map['price_per_day'] = Variable<double>(pricePerDay);
    }
    if (!nullToAbsent || salePrice != null) {
      map['sale_price'] = Variable<double>(salePrice);
    }
    if (!nullToAbsent || primaryImageUrl != null) {
      map['primary_image_url'] = Variable<String>(primaryImageUrl);
    }
    map['is_synced'] = Variable<bool>(isSynced);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedVehicleListingsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedVehicleListingsTableCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      vehicleType: Value(vehicleType),
      listingIntent: Value(listingIntent),
      make: Value(make),
      model: Value(model),
      year: Value(year),
      pricePerKm: pricePerKm == null && nullToAbsent
          ? const Value.absent()
          : Value(pricePerKm),
      pricePerDay: pricePerDay == null && nullToAbsent
          ? const Value.absent()
          : Value(pricePerDay),
      salePrice: salePrice == null && nullToAbsent
          ? const Value.absent()
          : Value(salePrice),
      primaryImageUrl: primaryImageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(primaryImageUrl),
      isSynced: Value(isSynced),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedVehicleListing.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedVehicleListing(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      vehicleType: serializer.fromJson<String>(json['vehicleType']),
      listingIntent: serializer.fromJson<String>(json['listingIntent']),
      make: serializer.fromJson<String>(json['make']),
      model: serializer.fromJson<String>(json['model']),
      year: serializer.fromJson<int>(json['year']),
      pricePerKm: serializer.fromJson<double?>(json['pricePerKm']),
      pricePerDay: serializer.fromJson<double?>(json['pricePerDay']),
      salePrice: serializer.fromJson<double?>(json['salePrice']),
      primaryImageUrl: serializer.fromJson<String?>(json['primaryImageUrl']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'vehicleType': serializer.toJson<String>(vehicleType),
      'listingIntent': serializer.toJson<String>(listingIntent),
      'make': serializer.toJson<String>(make),
      'model': serializer.toJson<String>(model),
      'year': serializer.toJson<int>(year),
      'pricePerKm': serializer.toJson<double?>(pricePerKm),
      'pricePerDay': serializer.toJson<double?>(pricePerDay),
      'salePrice': serializer.toJson<double?>(salePrice),
      'primaryImageUrl': serializer.toJson<String?>(primaryImageUrl),
      'isSynced': serializer.toJson<bool>(isSynced),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedVehicleListing copyWith(
          {String? id,
          String? ownerId,
          String? vehicleType,
          String? listingIntent,
          String? make,
          String? model,
          int? year,
          Value<double?> pricePerKm = const Value.absent(),
          Value<double?> pricePerDay = const Value.absent(),
          Value<double?> salePrice = const Value.absent(),
          Value<String?> primaryImageUrl = const Value.absent(),
          bool? isSynced,
          int? cachedAt}) =>
      CachedVehicleListing(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        vehicleType: vehicleType ?? this.vehicleType,
        listingIntent: listingIntent ?? this.listingIntent,
        make: make ?? this.make,
        model: model ?? this.model,
        year: year ?? this.year,
        pricePerKm: pricePerKm.present ? pricePerKm.value : this.pricePerKm,
        pricePerDay: pricePerDay.present ? pricePerDay.value : this.pricePerDay,
        salePrice: salePrice.present ? salePrice.value : this.salePrice,
        primaryImageUrl: primaryImageUrl.present
            ? primaryImageUrl.value
            : this.primaryImageUrl,
        isSynced: isSynced ?? this.isSynced,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedVehicleListing copyWithCompanion(
      CachedVehicleListingsTableCompanion data) {
    return CachedVehicleListing(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      vehicleType:
          data.vehicleType.present ? data.vehicleType.value : this.vehicleType,
      listingIntent: data.listingIntent.present
          ? data.listingIntent.value
          : this.listingIntent,
      make: data.make.present ? data.make.value : this.make,
      model: data.model.present ? data.model.value : this.model,
      year: data.year.present ? data.year.value : this.year,
      pricePerKm:
          data.pricePerKm.present ? data.pricePerKm.value : this.pricePerKm,
      pricePerDay:
          data.pricePerDay.present ? data.pricePerDay.value : this.pricePerDay,
      salePrice: data.salePrice.present ? data.salePrice.value : this.salePrice,
      primaryImageUrl: data.primaryImageUrl.present
          ? data.primaryImageUrl.value
          : this.primaryImageUrl,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedVehicleListing(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('vehicleType: $vehicleType, ')
          ..write('listingIntent: $listingIntent, ')
          ..write('make: $make, ')
          ..write('model: $model, ')
          ..write('year: $year, ')
          ..write('pricePerKm: $pricePerKm, ')
          ..write('pricePerDay: $pricePerDay, ')
          ..write('salePrice: $salePrice, ')
          ..write('primaryImageUrl: $primaryImageUrl, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      ownerId,
      vehicleType,
      listingIntent,
      make,
      model,
      year,
      pricePerKm,
      pricePerDay,
      salePrice,
      primaryImageUrl,
      isSynced,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedVehicleListing &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.vehicleType == this.vehicleType &&
          other.listingIntent == this.listingIntent &&
          other.make == this.make &&
          other.model == this.model &&
          other.year == this.year &&
          other.pricePerKm == this.pricePerKm &&
          other.pricePerDay == this.pricePerDay &&
          other.salePrice == this.salePrice &&
          other.primaryImageUrl == this.primaryImageUrl &&
          other.isSynced == this.isSynced &&
          other.cachedAt == this.cachedAt);
}

class CachedVehicleListingsTableCompanion
    extends UpdateCompanion<CachedVehicleListing> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> vehicleType;
  final Value<String> listingIntent;
  final Value<String> make;
  final Value<String> model;
  final Value<int> year;
  final Value<double?> pricePerKm;
  final Value<double?> pricePerDay;
  final Value<double?> salePrice;
  final Value<String?> primaryImageUrl;
  final Value<bool> isSynced;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedVehicleListingsTableCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.vehicleType = const Value.absent(),
    this.listingIntent = const Value.absent(),
    this.make = const Value.absent(),
    this.model = const Value.absent(),
    this.year = const Value.absent(),
    this.pricePerKm = const Value.absent(),
    this.pricePerDay = const Value.absent(),
    this.salePrice = const Value.absent(),
    this.primaryImageUrl = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedVehicleListingsTableCompanion.insert({
    required String id,
    required String ownerId,
    required String vehicleType,
    required String listingIntent,
    required String make,
    required String model,
    required int year,
    this.pricePerKm = const Value.absent(),
    this.pricePerDay = const Value.absent(),
    this.salePrice = const Value.absent(),
    this.primaryImageUrl = const Value.absent(),
    this.isSynced = const Value.absent(),
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        ownerId = Value(ownerId),
        vehicleType = Value(vehicleType),
        listingIntent = Value(listingIntent),
        make = Value(make),
        model = Value(model),
        year = Value(year),
        cachedAt = Value(cachedAt);
  static Insertable<CachedVehicleListing> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? vehicleType,
    Expression<String>? listingIntent,
    Expression<String>? make,
    Expression<String>? model,
    Expression<int>? year,
    Expression<double>? pricePerKm,
    Expression<double>? pricePerDay,
    Expression<double>? salePrice,
    Expression<String>? primaryImageUrl,
    Expression<bool>? isSynced,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (listingIntent != null) 'listing_intent': listingIntent,
      if (make != null) 'make': make,
      if (model != null) 'model': model,
      if (year != null) 'year': year,
      if (pricePerKm != null) 'price_per_km': pricePerKm,
      if (pricePerDay != null) 'price_per_day': pricePerDay,
      if (salePrice != null) 'sale_price': salePrice,
      if (primaryImageUrl != null) 'primary_image_url': primaryImageUrl,
      if (isSynced != null) 'is_synced': isSynced,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedVehicleListingsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? ownerId,
      Value<String>? vehicleType,
      Value<String>? listingIntent,
      Value<String>? make,
      Value<String>? model,
      Value<int>? year,
      Value<double?>? pricePerKm,
      Value<double?>? pricePerDay,
      Value<double?>? salePrice,
      Value<String?>? primaryImageUrl,
      Value<bool>? isSynced,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedVehicleListingsTableCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      vehicleType: vehicleType ?? this.vehicleType,
      listingIntent: listingIntent ?? this.listingIntent,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      pricePerKm: pricePerKm ?? this.pricePerKm,
      pricePerDay: pricePerDay ?? this.pricePerDay,
      salePrice: salePrice ?? this.salePrice,
      primaryImageUrl: primaryImageUrl ?? this.primaryImageUrl,
      isSynced: isSynced ?? this.isSynced,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (vehicleType.present) {
      map['vehicle_type'] = Variable<String>(vehicleType.value);
    }
    if (listingIntent.present) {
      map['listing_intent'] = Variable<String>(listingIntent.value);
    }
    if (make.present) {
      map['make'] = Variable<String>(make.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (pricePerKm.present) {
      map['price_per_km'] = Variable<double>(pricePerKm.value);
    }
    if (pricePerDay.present) {
      map['price_per_day'] = Variable<double>(pricePerDay.value);
    }
    if (salePrice.present) {
      map['sale_price'] = Variable<double>(salePrice.value);
    }
    if (primaryImageUrl.present) {
      map['primary_image_url'] = Variable<String>(primaryImageUrl.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedVehicleListingsTableCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('vehicleType: $vehicleType, ')
          ..write('listingIntent: $listingIntent, ')
          ..write('make: $make, ')
          ..write('model: $model, ')
          ..write('year: $year, ')
          ..write('pricePerKm: $pricePerKm, ')
          ..write('pricePerDay: $pricePerDay, ')
          ..write('salePrice: $salePrice, ')
          ..write('primaryImageUrl: $primaryImageUrl, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedBookingsTableTable extends CachedBookingsTable
    with TableInfo<$CachedBookingsTableTable, CachedBooking> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedBookingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _listingIdMeta =
      const VerificationMeta('listingId');
  @override
  late final GeneratedColumn<String> listingId = GeneratedColumn<String>(
      'listing_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _listingTitleMeta =
      const VerificationMeta('listingTitle');
  @override
  late final GeneratedColumn<String> listingTitle = GeneratedColumn<String>(
      'listing_title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _buyerIdMeta =
      const VerificationMeta('buyerId');
  @override
  late final GeneratedColumn<String> buyerId = GeneratedColumn<String>(
      'buyer_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _vendorIdMeta =
      const VerificationMeta('vendorId');
  @override
  late final GeneratedColumn<String> vendorId = GeneratedColumn<String>(
      'vendor_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bookingTypeMeta =
      const VerificationMeta('bookingType');
  @override
  late final GeneratedColumn<String> bookingType = GeneratedColumn<String>(
      'booking_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startTimeMeta =
      const VerificationMeta('startTime');
  @override
  late final GeneratedColumn<int> startTime = GeneratedColumn<int>(
      'start_time', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endTimeMeta =
      const VerificationMeta('endTime');
  @override
  late final GeneratedColumn<int> endTime = GeneratedColumn<int>(
      'end_time', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalAmountMeta =
      const VerificationMeta('totalAmount');
  @override
  late final GeneratedColumn<double> totalAmount = GeneratedColumn<double>(
      'total_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('SLE'));
  static const VerificationMeta _paymentStatusMeta =
      const VerificationMeta('paymentStatus');
  @override
  late final GeneratedColumn<String> paymentStatus = GeneratedColumn<String>(
      'payment_status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bookingStatusMeta =
      const VerificationMeta('bookingStatus');
  @override
  late final GeneratedColumn<String> bookingStatus = GeneratedColumn<String>(
      'booking_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending_payment'));
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        listingId,
        listingTitle,
        buyerId,
        vendorId,
        bookingType,
        startTime,
        endTime,
        totalAmount,
        currency,
        paymentStatus,
        bookingStatus,
        isSynced,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_bookings_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedBooking> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('listing_id')) {
      context.handle(_listingIdMeta,
          listingId.isAcceptableOrUnknown(data['listing_id']!, _listingIdMeta));
    } else if (isInserting) {
      context.missing(_listingIdMeta);
    }
    if (data.containsKey('listing_title')) {
      context.handle(
          _listingTitleMeta,
          listingTitle.isAcceptableOrUnknown(
              data['listing_title']!, _listingTitleMeta));
    }
    if (data.containsKey('buyer_id')) {
      context.handle(_buyerIdMeta,
          buyerId.isAcceptableOrUnknown(data['buyer_id']!, _buyerIdMeta));
    } else if (isInserting) {
      context.missing(_buyerIdMeta);
    }
    if (data.containsKey('vendor_id')) {
      context.handle(_vendorIdMeta,
          vendorId.isAcceptableOrUnknown(data['vendor_id']!, _vendorIdMeta));
    } else if (isInserting) {
      context.missing(_vendorIdMeta);
    }
    if (data.containsKey('booking_type')) {
      context.handle(
          _bookingTypeMeta,
          bookingType.isAcceptableOrUnknown(
              data['booking_type']!, _bookingTypeMeta));
    } else if (isInserting) {
      context.missing(_bookingTypeMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(_startTimeMeta,
          startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta));
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(_endTimeMeta,
          endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta));
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('total_amount')) {
      context.handle(
          _totalAmountMeta,
          totalAmount.isAcceptableOrUnknown(
              data['total_amount']!, _totalAmountMeta));
    } else if (isInserting) {
      context.missing(_totalAmountMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('payment_status')) {
      context.handle(
          _paymentStatusMeta,
          paymentStatus.isAcceptableOrUnknown(
              data['payment_status']!, _paymentStatusMeta));
    } else if (isInserting) {
      context.missing(_paymentStatusMeta);
    }
    if (data.containsKey('booking_status')) {
      context.handle(
          _bookingStatusMeta,
          bookingStatus.isAcceptableOrUnknown(
              data['booking_status']!, _bookingStatusMeta));
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedBooking map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedBooking(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      listingId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}listing_id'])!,
      listingTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}listing_title'])!,
      buyerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}buyer_id'])!,
      vendorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}vendor_id'])!,
      bookingType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}booking_type'])!,
      startTime: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_time'])!,
      endTime: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_time'])!,
      totalAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total_amount'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      paymentStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_status'])!,
      bookingStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}booking_status'])!,
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedBookingsTableTable createAlias(String alias) {
    return $CachedBookingsTableTable(attachedDatabase, alias);
  }
}

class CachedBooking extends DataClass implements Insertable<CachedBooking> {
  final String id;
  final String listingId;
  final String listingTitle;
  final String buyerId;
  final String vendorId;
  final String bookingType;
  final int startTime;
  final int endTime;
  final double totalAmount;
  final String currency;
  final String paymentStatus;
  final String bookingStatus;
  final bool isSynced;
  final int cachedAt;
  const CachedBooking(
      {required this.id,
      required this.listingId,
      required this.listingTitle,
      required this.buyerId,
      required this.vendorId,
      required this.bookingType,
      required this.startTime,
      required this.endTime,
      required this.totalAmount,
      required this.currency,
      required this.paymentStatus,
      required this.bookingStatus,
      required this.isSynced,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['listing_id'] = Variable<String>(listingId);
    map['listing_title'] = Variable<String>(listingTitle);
    map['buyer_id'] = Variable<String>(buyerId);
    map['vendor_id'] = Variable<String>(vendorId);
    map['booking_type'] = Variable<String>(bookingType);
    map['start_time'] = Variable<int>(startTime);
    map['end_time'] = Variable<int>(endTime);
    map['total_amount'] = Variable<double>(totalAmount);
    map['currency'] = Variable<String>(currency);
    map['payment_status'] = Variable<String>(paymentStatus);
    map['booking_status'] = Variable<String>(bookingStatus);
    map['is_synced'] = Variable<bool>(isSynced);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedBookingsTableCompanion toCompanion(bool nullToAbsent) {
    return CachedBookingsTableCompanion(
      id: Value(id),
      listingId: Value(listingId),
      listingTitle: Value(listingTitle),
      buyerId: Value(buyerId),
      vendorId: Value(vendorId),
      bookingType: Value(bookingType),
      startTime: Value(startTime),
      endTime: Value(endTime),
      totalAmount: Value(totalAmount),
      currency: Value(currency),
      paymentStatus: Value(paymentStatus),
      bookingStatus: Value(bookingStatus),
      isSynced: Value(isSynced),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedBooking.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedBooking(
      id: serializer.fromJson<String>(json['id']),
      listingId: serializer.fromJson<String>(json['listingId']),
      listingTitle: serializer.fromJson<String>(json['listingTitle']),
      buyerId: serializer.fromJson<String>(json['buyerId']),
      vendorId: serializer.fromJson<String>(json['vendorId']),
      bookingType: serializer.fromJson<String>(json['bookingType']),
      startTime: serializer.fromJson<int>(json['startTime']),
      endTime: serializer.fromJson<int>(json['endTime']),
      totalAmount: serializer.fromJson<double>(json['totalAmount']),
      currency: serializer.fromJson<String>(json['currency']),
      paymentStatus: serializer.fromJson<String>(json['paymentStatus']),
      bookingStatus: serializer.fromJson<String>(json['bookingStatus']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'listingId': serializer.toJson<String>(listingId),
      'listingTitle': serializer.toJson<String>(listingTitle),
      'buyerId': serializer.toJson<String>(buyerId),
      'vendorId': serializer.toJson<String>(vendorId),
      'bookingType': serializer.toJson<String>(bookingType),
      'startTime': serializer.toJson<int>(startTime),
      'endTime': serializer.toJson<int>(endTime),
      'totalAmount': serializer.toJson<double>(totalAmount),
      'currency': serializer.toJson<String>(currency),
      'paymentStatus': serializer.toJson<String>(paymentStatus),
      'bookingStatus': serializer.toJson<String>(bookingStatus),
      'isSynced': serializer.toJson<bool>(isSynced),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedBooking copyWith(
          {String? id,
          String? listingId,
          String? listingTitle,
          String? buyerId,
          String? vendorId,
          String? bookingType,
          int? startTime,
          int? endTime,
          double? totalAmount,
          String? currency,
          String? paymentStatus,
          String? bookingStatus,
          bool? isSynced,
          int? cachedAt}) =>
      CachedBooking(
        id: id ?? this.id,
        listingId: listingId ?? this.listingId,
        listingTitle: listingTitle ?? this.listingTitle,
        buyerId: buyerId ?? this.buyerId,
        vendorId: vendorId ?? this.vendorId,
        bookingType: bookingType ?? this.bookingType,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        totalAmount: totalAmount ?? this.totalAmount,
        currency: currency ?? this.currency,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        bookingStatus: bookingStatus ?? this.bookingStatus,
        isSynced: isSynced ?? this.isSynced,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedBooking copyWithCompanion(CachedBookingsTableCompanion data) {
    return CachedBooking(
      id: data.id.present ? data.id.value : this.id,
      listingId: data.listingId.present ? data.listingId.value : this.listingId,
      listingTitle: data.listingTitle.present
          ? data.listingTitle.value
          : this.listingTitle,
      buyerId: data.buyerId.present ? data.buyerId.value : this.buyerId,
      vendorId: data.vendorId.present ? data.vendorId.value : this.vendorId,
      bookingType:
          data.bookingType.present ? data.bookingType.value : this.bookingType,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      totalAmount:
          data.totalAmount.present ? data.totalAmount.value : this.totalAmount,
      currency: data.currency.present ? data.currency.value : this.currency,
      paymentStatus: data.paymentStatus.present
          ? data.paymentStatus.value
          : this.paymentStatus,
      bookingStatus: data.bookingStatus.present
          ? data.bookingStatus.value
          : this.bookingStatus,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedBooking(')
          ..write('id: $id, ')
          ..write('listingId: $listingId, ')
          ..write('listingTitle: $listingTitle, ')
          ..write('buyerId: $buyerId, ')
          ..write('vendorId: $vendorId, ')
          ..write('bookingType: $bookingType, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('currency: $currency, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('bookingStatus: $bookingStatus, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      listingId,
      listingTitle,
      buyerId,
      vendorId,
      bookingType,
      startTime,
      endTime,
      totalAmount,
      currency,
      paymentStatus,
      bookingStatus,
      isSynced,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedBooking &&
          other.id == this.id &&
          other.listingId == this.listingId &&
          other.listingTitle == this.listingTitle &&
          other.buyerId == this.buyerId &&
          other.vendorId == this.vendorId &&
          other.bookingType == this.bookingType &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.totalAmount == this.totalAmount &&
          other.currency == this.currency &&
          other.paymentStatus == this.paymentStatus &&
          other.bookingStatus == this.bookingStatus &&
          other.isSynced == this.isSynced &&
          other.cachedAt == this.cachedAt);
}

class CachedBookingsTableCompanion extends UpdateCompanion<CachedBooking> {
  final Value<String> id;
  final Value<String> listingId;
  final Value<String> listingTitle;
  final Value<String> buyerId;
  final Value<String> vendorId;
  final Value<String> bookingType;
  final Value<int> startTime;
  final Value<int> endTime;
  final Value<double> totalAmount;
  final Value<String> currency;
  final Value<String> paymentStatus;
  final Value<String> bookingStatus;
  final Value<bool> isSynced;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedBookingsTableCompanion({
    this.id = const Value.absent(),
    this.listingId = const Value.absent(),
    this.listingTitle = const Value.absent(),
    this.buyerId = const Value.absent(),
    this.vendorId = const Value.absent(),
    this.bookingType = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.totalAmount = const Value.absent(),
    this.currency = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.bookingStatus = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedBookingsTableCompanion.insert({
    required String id,
    required String listingId,
    this.listingTitle = const Value.absent(),
    required String buyerId,
    required String vendorId,
    required String bookingType,
    required int startTime,
    required int endTime,
    required double totalAmount,
    this.currency = const Value.absent(),
    required String paymentStatus,
    this.bookingStatus = const Value.absent(),
    this.isSynced = const Value.absent(),
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        listingId = Value(listingId),
        buyerId = Value(buyerId),
        vendorId = Value(vendorId),
        bookingType = Value(bookingType),
        startTime = Value(startTime),
        endTime = Value(endTime),
        totalAmount = Value(totalAmount),
        paymentStatus = Value(paymentStatus),
        cachedAt = Value(cachedAt);
  static Insertable<CachedBooking> custom({
    Expression<String>? id,
    Expression<String>? listingId,
    Expression<String>? listingTitle,
    Expression<String>? buyerId,
    Expression<String>? vendorId,
    Expression<String>? bookingType,
    Expression<int>? startTime,
    Expression<int>? endTime,
    Expression<double>? totalAmount,
    Expression<String>? currency,
    Expression<String>? paymentStatus,
    Expression<String>? bookingStatus,
    Expression<bool>? isSynced,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (listingId != null) 'listing_id': listingId,
      if (listingTitle != null) 'listing_title': listingTitle,
      if (buyerId != null) 'buyer_id': buyerId,
      if (vendorId != null) 'vendor_id': vendorId,
      if (bookingType != null) 'booking_type': bookingType,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (totalAmount != null) 'total_amount': totalAmount,
      if (currency != null) 'currency': currency,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (bookingStatus != null) 'booking_status': bookingStatus,
      if (isSynced != null) 'is_synced': isSynced,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedBookingsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? listingId,
      Value<String>? listingTitle,
      Value<String>? buyerId,
      Value<String>? vendorId,
      Value<String>? bookingType,
      Value<int>? startTime,
      Value<int>? endTime,
      Value<double>? totalAmount,
      Value<String>? currency,
      Value<String>? paymentStatus,
      Value<String>? bookingStatus,
      Value<bool>? isSynced,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedBookingsTableCompanion(
      id: id ?? this.id,
      listingId: listingId ?? this.listingId,
      listingTitle: listingTitle ?? this.listingTitle,
      buyerId: buyerId ?? this.buyerId,
      vendorId: vendorId ?? this.vendorId,
      bookingType: bookingType ?? this.bookingType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalAmount: totalAmount ?? this.totalAmount,
      currency: currency ?? this.currency,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      bookingStatus: bookingStatus ?? this.bookingStatus,
      isSynced: isSynced ?? this.isSynced,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (listingId.present) {
      map['listing_id'] = Variable<String>(listingId.value);
    }
    if (listingTitle.present) {
      map['listing_title'] = Variable<String>(listingTitle.value);
    }
    if (buyerId.present) {
      map['buyer_id'] = Variable<String>(buyerId.value);
    }
    if (vendorId.present) {
      map['vendor_id'] = Variable<String>(vendorId.value);
    }
    if (bookingType.present) {
      map['booking_type'] = Variable<String>(bookingType.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<int>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<int>(endTime.value);
    }
    if (totalAmount.present) {
      map['total_amount'] = Variable<double>(totalAmount.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (paymentStatus.present) {
      map['payment_status'] = Variable<String>(paymentStatus.value);
    }
    if (bookingStatus.present) {
      map['booking_status'] = Variable<String>(bookingStatus.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedBookingsTableCompanion(')
          ..write('id: $id, ')
          ..write('listingId: $listingId, ')
          ..write('listingTitle: $listingTitle, ')
          ..write('buyerId: $buyerId, ')
          ..write('vendorId: $vendorId, ')
          ..write('bookingType: $bookingType, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('currency: $currency, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('bookingStatus: $bookingStatus, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDriverProfilesTableTable extends CachedDriverProfilesTable
    with TableInfo<$CachedDriverProfilesTableTable, CachedDriverProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDriverProfilesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isOnlineMeta =
      const VerificationMeta('isOnline');
  @override
  late final GeneratedColumn<bool> isOnline = GeneratedColumn<bool>(
      'is_online', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_online" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isAvailableMeta =
      const VerificationMeta('isAvailable');
  @override
  late final GeneratedColumn<bool> isAvailable = GeneratedColumn<bool>(
      'is_available', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_available" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _serviceTypeMeta =
      const VerificationMeta('serviceType');
  @override
  late final GeneratedColumn<String> serviceType = GeneratedColumn<String>(
      'service_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _currentLatMeta =
      const VerificationMeta('currentLat');
  @override
  late final GeneratedColumn<double> currentLat = GeneratedColumn<double>(
      'current_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currentLngMeta =
      const VerificationMeta('currentLng');
  @override
  late final GeneratedColumn<double> currentLng = GeneratedColumn<double>(
      'current_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currentGeohashMeta =
      const VerificationMeta('currentGeohash');
  @override
  late final GeneratedColumn<String> currentGeohash = GeneratedColumn<String>(
      'current_geohash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastLocationUpdateMeta =
      const VerificationMeta('lastLocationUpdate');
  @override
  late final GeneratedColumn<int> lastLocationUpdate = GeneratedColumn<int>(
      'last_location_update', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        userId,
        isOnline,
        isAvailable,
        serviceType,
        currentLat,
        currentLng,
        currentGeohash,
        lastLocationUpdate,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_driver_profiles_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<CachedDriverProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('is_online')) {
      context.handle(_isOnlineMeta,
          isOnline.isAcceptableOrUnknown(data['is_online']!, _isOnlineMeta));
    }
    if (data.containsKey('is_available')) {
      context.handle(
          _isAvailableMeta,
          isAvailable.isAcceptableOrUnknown(
              data['is_available']!, _isAvailableMeta));
    }
    if (data.containsKey('service_type')) {
      context.handle(
          _serviceTypeMeta,
          serviceType.isAcceptableOrUnknown(
              data['service_type']!, _serviceTypeMeta));
    } else if (isInserting) {
      context.missing(_serviceTypeMeta);
    }
    if (data.containsKey('current_lat')) {
      context.handle(
          _currentLatMeta,
          currentLat.isAcceptableOrUnknown(
              data['current_lat']!, _currentLatMeta));
    } else if (isInserting) {
      context.missing(_currentLatMeta);
    }
    if (data.containsKey('current_lng')) {
      context.handle(
          _currentLngMeta,
          currentLng.isAcceptableOrUnknown(
              data['current_lng']!, _currentLngMeta));
    } else if (isInserting) {
      context.missing(_currentLngMeta);
    }
    if (data.containsKey('current_geohash')) {
      context.handle(
          _currentGeohashMeta,
          currentGeohash.isAcceptableOrUnknown(
              data['current_geohash']!, _currentGeohashMeta));
    } else if (isInserting) {
      context.missing(_currentGeohashMeta);
    }
    if (data.containsKey('last_location_update')) {
      context.handle(
          _lastLocationUpdateMeta,
          lastLocationUpdate.isAcceptableOrUnknown(
              data['last_location_update']!, _lastLocationUpdateMeta));
    } else if (isInserting) {
      context.missing(_lastLocationUpdateMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedDriverProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDriverProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      isOnline: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_online'])!,
      isAvailable: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_available'])!,
      serviceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}service_type'])!,
      currentLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}current_lat'])!,
      currentLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}current_lng'])!,
      currentGeohash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}current_geohash'])!,
      lastLocationUpdate: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_location_update'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedDriverProfilesTableTable createAlias(String alias) {
    return $CachedDriverProfilesTableTable(attachedDatabase, alias);
  }
}

class CachedDriverProfile extends DataClass
    implements Insertable<CachedDriverProfile> {
  final String id;
  final String userId;
  final bool isOnline;
  final bool isAvailable;
  final String serviceType;
  final double currentLat;
  final double currentLng;
  final String currentGeohash;
  final int lastLocationUpdate;
  final int cachedAt;
  const CachedDriverProfile(
      {required this.id,
      required this.userId,
      required this.isOnline,
      required this.isAvailable,
      required this.serviceType,
      required this.currentLat,
      required this.currentLng,
      required this.currentGeohash,
      required this.lastLocationUpdate,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['is_online'] = Variable<bool>(isOnline);
    map['is_available'] = Variable<bool>(isAvailable);
    map['service_type'] = Variable<String>(serviceType);
    map['current_lat'] = Variable<double>(currentLat);
    map['current_lng'] = Variable<double>(currentLng);
    map['current_geohash'] = Variable<String>(currentGeohash);
    map['last_location_update'] = Variable<int>(lastLocationUpdate);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedDriverProfilesTableCompanion toCompanion(bool nullToAbsent) {
    return CachedDriverProfilesTableCompanion(
      id: Value(id),
      userId: Value(userId),
      isOnline: Value(isOnline),
      isAvailable: Value(isAvailable),
      serviceType: Value(serviceType),
      currentLat: Value(currentLat),
      currentLng: Value(currentLng),
      currentGeohash: Value(currentGeohash),
      lastLocationUpdate: Value(lastLocationUpdate),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedDriverProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDriverProfile(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      isOnline: serializer.fromJson<bool>(json['isOnline']),
      isAvailable: serializer.fromJson<bool>(json['isAvailable']),
      serviceType: serializer.fromJson<String>(json['serviceType']),
      currentLat: serializer.fromJson<double>(json['currentLat']),
      currentLng: serializer.fromJson<double>(json['currentLng']),
      currentGeohash: serializer.fromJson<String>(json['currentGeohash']),
      lastLocationUpdate: serializer.fromJson<int>(json['lastLocationUpdate']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'isOnline': serializer.toJson<bool>(isOnline),
      'isAvailable': serializer.toJson<bool>(isAvailable),
      'serviceType': serializer.toJson<String>(serviceType),
      'currentLat': serializer.toJson<double>(currentLat),
      'currentLng': serializer.toJson<double>(currentLng),
      'currentGeohash': serializer.toJson<String>(currentGeohash),
      'lastLocationUpdate': serializer.toJson<int>(lastLocationUpdate),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedDriverProfile copyWith(
          {String? id,
          String? userId,
          bool? isOnline,
          bool? isAvailable,
          String? serviceType,
          double? currentLat,
          double? currentLng,
          String? currentGeohash,
          int? lastLocationUpdate,
          int? cachedAt}) =>
      CachedDriverProfile(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        isOnline: isOnline ?? this.isOnline,
        isAvailable: isAvailable ?? this.isAvailable,
        serviceType: serviceType ?? this.serviceType,
        currentLat: currentLat ?? this.currentLat,
        currentLng: currentLng ?? this.currentLng,
        currentGeohash: currentGeohash ?? this.currentGeohash,
        lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedDriverProfile copyWithCompanion(
      CachedDriverProfilesTableCompanion data) {
    return CachedDriverProfile(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      isOnline: data.isOnline.present ? data.isOnline.value : this.isOnline,
      isAvailable:
          data.isAvailable.present ? data.isAvailable.value : this.isAvailable,
      serviceType:
          data.serviceType.present ? data.serviceType.value : this.serviceType,
      currentLat:
          data.currentLat.present ? data.currentLat.value : this.currentLat,
      currentLng:
          data.currentLng.present ? data.currentLng.value : this.currentLng,
      currentGeohash: data.currentGeohash.present
          ? data.currentGeohash.value
          : this.currentGeohash,
      lastLocationUpdate: data.lastLocationUpdate.present
          ? data.lastLocationUpdate.value
          : this.lastLocationUpdate,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDriverProfile(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('isOnline: $isOnline, ')
          ..write('isAvailable: $isAvailable, ')
          ..write('serviceType: $serviceType, ')
          ..write('currentLat: $currentLat, ')
          ..write('currentLng: $currentLng, ')
          ..write('currentGeohash: $currentGeohash, ')
          ..write('lastLocationUpdate: $lastLocationUpdate, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      userId,
      isOnline,
      isAvailable,
      serviceType,
      currentLat,
      currentLng,
      currentGeohash,
      lastLocationUpdate,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDriverProfile &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.isOnline == this.isOnline &&
          other.isAvailable == this.isAvailable &&
          other.serviceType == this.serviceType &&
          other.currentLat == this.currentLat &&
          other.currentLng == this.currentLng &&
          other.currentGeohash == this.currentGeohash &&
          other.lastLocationUpdate == this.lastLocationUpdate &&
          other.cachedAt == this.cachedAt);
}

class CachedDriverProfilesTableCompanion
    extends UpdateCompanion<CachedDriverProfile> {
  final Value<String> id;
  final Value<String> userId;
  final Value<bool> isOnline;
  final Value<bool> isAvailable;
  final Value<String> serviceType;
  final Value<double> currentLat;
  final Value<double> currentLng;
  final Value<String> currentGeohash;
  final Value<int> lastLocationUpdate;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedDriverProfilesTableCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.isAvailable = const Value.absent(),
    this.serviceType = const Value.absent(),
    this.currentLat = const Value.absent(),
    this.currentLng = const Value.absent(),
    this.currentGeohash = const Value.absent(),
    this.lastLocationUpdate = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDriverProfilesTableCompanion.insert({
    required String id,
    required String userId,
    this.isOnline = const Value.absent(),
    this.isAvailable = const Value.absent(),
    required String serviceType,
    required double currentLat,
    required double currentLng,
    required String currentGeohash,
    required int lastLocationUpdate,
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        userId = Value(userId),
        serviceType = Value(serviceType),
        currentLat = Value(currentLat),
        currentLng = Value(currentLng),
        currentGeohash = Value(currentGeohash),
        lastLocationUpdate = Value(lastLocationUpdate),
        cachedAt = Value(cachedAt);
  static Insertable<CachedDriverProfile> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<bool>? isOnline,
    Expression<bool>? isAvailable,
    Expression<String>? serviceType,
    Expression<double>? currentLat,
    Expression<double>? currentLng,
    Expression<String>? currentGeohash,
    Expression<int>? lastLocationUpdate,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (isOnline != null) 'is_online': isOnline,
      if (isAvailable != null) 'is_available': isAvailable,
      if (serviceType != null) 'service_type': serviceType,
      if (currentLat != null) 'current_lat': currentLat,
      if (currentLng != null) 'current_lng': currentLng,
      if (currentGeohash != null) 'current_geohash': currentGeohash,
      if (lastLocationUpdate != null)
        'last_location_update': lastLocationUpdate,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDriverProfilesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? userId,
      Value<bool>? isOnline,
      Value<bool>? isAvailable,
      Value<String>? serviceType,
      Value<double>? currentLat,
      Value<double>? currentLng,
      Value<String>? currentGeohash,
      Value<int>? lastLocationUpdate,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedDriverProfilesTableCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      isOnline: isOnline ?? this.isOnline,
      isAvailable: isAvailable ?? this.isAvailable,
      serviceType: serviceType ?? this.serviceType,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      currentGeohash: currentGeohash ?? this.currentGeohash,
      lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (isOnline.present) {
      map['is_online'] = Variable<bool>(isOnline.value);
    }
    if (isAvailable.present) {
      map['is_available'] = Variable<bool>(isAvailable.value);
    }
    if (serviceType.present) {
      map['service_type'] = Variable<String>(serviceType.value);
    }
    if (currentLat.present) {
      map['current_lat'] = Variable<double>(currentLat.value);
    }
    if (currentLng.present) {
      map['current_lng'] = Variable<double>(currentLng.value);
    }
    if (currentGeohash.present) {
      map['current_geohash'] = Variable<String>(currentGeohash.value);
    }
    if (lastLocationUpdate.present) {
      map['last_location_update'] = Variable<int>(lastLocationUpdate.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDriverProfilesTableCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('isOnline: $isOnline, ')
          ..write('isAvailable: $isAvailable, ')
          ..write('serviceType: $serviceType, ')
          ..write('currentLat: $currentLat, ')
          ..write('currentLng: $currentLng, ')
          ..write('currentGeohash: $currentGeohash, ')
          ..write('lastLocationUpdate: $lastLocationUpdate, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDriverVehiclesTableTable extends CachedDriverVehiclesTable
    with TableInfo<$CachedDriverVehiclesTableTable, CachedDriverVehicle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDriverVehiclesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _driverIdMeta =
      const VerificationMeta('driverId');
  @override
  late final GeneratedColumn<String> driverId = GeneratedColumn<String>(
      'driver_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _makeMeta = const VerificationMeta('make');
  @override
  late final GeneratedColumn<String> make = GeneratedColumn<String>(
      'make', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
      'year', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
      'color', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _licensePlateMeta =
      const VerificationMeta('licensePlate');
  @override
  late final GeneratedColumn<String> licensePlate = GeneratedColumn<String>(
      'license_plate', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isVerifiedMeta =
      const VerificationMeta('isVerified');
  @override
  late final GeneratedColumn<bool> isVerified = GeneratedColumn<bool>(
      'is_verified', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_verified" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        driverId,
        make,
        model,
        year,
        color,
        licensePlate,
        category,
        isVerified,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_driver_vehicles_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<CachedDriverVehicle> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('driver_id')) {
      context.handle(_driverIdMeta,
          driverId.isAcceptableOrUnknown(data['driver_id']!, _driverIdMeta));
    } else if (isInserting) {
      context.missing(_driverIdMeta);
    }
    if (data.containsKey('make')) {
      context.handle(
          _makeMeta, make.isAcceptableOrUnknown(data['make']!, _makeMeta));
    } else if (isInserting) {
      context.missing(_makeMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
          _yearMeta, year.isAcceptableOrUnknown(data['year']!, _yearMeta));
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
          _colorMeta, color.isAcceptableOrUnknown(data['color']!, _colorMeta));
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('license_plate')) {
      context.handle(
          _licensePlateMeta,
          licensePlate.isAcceptableOrUnknown(
              data['license_plate']!, _licensePlateMeta));
    } else if (isInserting) {
      context.missing(_licensePlateMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('is_verified')) {
      context.handle(
          _isVerifiedMeta,
          isVerified.isAcceptableOrUnknown(
              data['is_verified']!, _isVerifiedMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedDriverVehicle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDriverVehicle(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      driverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}driver_id'])!,
      make: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}make'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      year: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}year'])!,
      color: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color'])!,
      licensePlate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}license_plate'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      isVerified: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_verified'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedDriverVehiclesTableTable createAlias(String alias) {
    return $CachedDriverVehiclesTableTable(attachedDatabase, alias);
  }
}

class CachedDriverVehicle extends DataClass
    implements Insertable<CachedDriverVehicle> {
  final String id;
  final String driverId;
  final String make;
  final String model;
  final int year;
  final String color;
  final String licensePlate;
  final String category;
  final bool isVerified;
  final int cachedAt;
  const CachedDriverVehicle(
      {required this.id,
      required this.driverId,
      required this.make,
      required this.model,
      required this.year,
      required this.color,
      required this.licensePlate,
      required this.category,
      required this.isVerified,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['driver_id'] = Variable<String>(driverId);
    map['make'] = Variable<String>(make);
    map['model'] = Variable<String>(model);
    map['year'] = Variable<int>(year);
    map['color'] = Variable<String>(color);
    map['license_plate'] = Variable<String>(licensePlate);
    map['category'] = Variable<String>(category);
    map['is_verified'] = Variable<bool>(isVerified);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedDriverVehiclesTableCompanion toCompanion(bool nullToAbsent) {
    return CachedDriverVehiclesTableCompanion(
      id: Value(id),
      driverId: Value(driverId),
      make: Value(make),
      model: Value(model),
      year: Value(year),
      color: Value(color),
      licensePlate: Value(licensePlate),
      category: Value(category),
      isVerified: Value(isVerified),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedDriverVehicle.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDriverVehicle(
      id: serializer.fromJson<String>(json['id']),
      driverId: serializer.fromJson<String>(json['driverId']),
      make: serializer.fromJson<String>(json['make']),
      model: serializer.fromJson<String>(json['model']),
      year: serializer.fromJson<int>(json['year']),
      color: serializer.fromJson<String>(json['color']),
      licensePlate: serializer.fromJson<String>(json['licensePlate']),
      category: serializer.fromJson<String>(json['category']),
      isVerified: serializer.fromJson<bool>(json['isVerified']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'driverId': serializer.toJson<String>(driverId),
      'make': serializer.toJson<String>(make),
      'model': serializer.toJson<String>(model),
      'year': serializer.toJson<int>(year),
      'color': serializer.toJson<String>(color),
      'licensePlate': serializer.toJson<String>(licensePlate),
      'category': serializer.toJson<String>(category),
      'isVerified': serializer.toJson<bool>(isVerified),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedDriverVehicle copyWith(
          {String? id,
          String? driverId,
          String? make,
          String? model,
          int? year,
          String? color,
          String? licensePlate,
          String? category,
          bool? isVerified,
          int? cachedAt}) =>
      CachedDriverVehicle(
        id: id ?? this.id,
        driverId: driverId ?? this.driverId,
        make: make ?? this.make,
        model: model ?? this.model,
        year: year ?? this.year,
        color: color ?? this.color,
        licensePlate: licensePlate ?? this.licensePlate,
        category: category ?? this.category,
        isVerified: isVerified ?? this.isVerified,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedDriverVehicle copyWithCompanion(
      CachedDriverVehiclesTableCompanion data) {
    return CachedDriverVehicle(
      id: data.id.present ? data.id.value : this.id,
      driverId: data.driverId.present ? data.driverId.value : this.driverId,
      make: data.make.present ? data.make.value : this.make,
      model: data.model.present ? data.model.value : this.model,
      year: data.year.present ? data.year.value : this.year,
      color: data.color.present ? data.color.value : this.color,
      licensePlate: data.licensePlate.present
          ? data.licensePlate.value
          : this.licensePlate,
      category: data.category.present ? data.category.value : this.category,
      isVerified:
          data.isVerified.present ? data.isVerified.value : this.isVerified,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDriverVehicle(')
          ..write('id: $id, ')
          ..write('driverId: $driverId, ')
          ..write('make: $make, ')
          ..write('model: $model, ')
          ..write('year: $year, ')
          ..write('color: $color, ')
          ..write('licensePlate: $licensePlate, ')
          ..write('category: $category, ')
          ..write('isVerified: $isVerified, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, driverId, make, model, year, color,
      licensePlate, category, isVerified, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDriverVehicle &&
          other.id == this.id &&
          other.driverId == this.driverId &&
          other.make == this.make &&
          other.model == this.model &&
          other.year == this.year &&
          other.color == this.color &&
          other.licensePlate == this.licensePlate &&
          other.category == this.category &&
          other.isVerified == this.isVerified &&
          other.cachedAt == this.cachedAt);
}

class CachedDriverVehiclesTableCompanion
    extends UpdateCompanion<CachedDriverVehicle> {
  final Value<String> id;
  final Value<String> driverId;
  final Value<String> make;
  final Value<String> model;
  final Value<int> year;
  final Value<String> color;
  final Value<String> licensePlate;
  final Value<String> category;
  final Value<bool> isVerified;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedDriverVehiclesTableCompanion({
    this.id = const Value.absent(),
    this.driverId = const Value.absent(),
    this.make = const Value.absent(),
    this.model = const Value.absent(),
    this.year = const Value.absent(),
    this.color = const Value.absent(),
    this.licensePlate = const Value.absent(),
    this.category = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDriverVehiclesTableCompanion.insert({
    required String id,
    required String driverId,
    required String make,
    required String model,
    required int year,
    required String color,
    required String licensePlate,
    required String category,
    this.isVerified = const Value.absent(),
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        driverId = Value(driverId),
        make = Value(make),
        model = Value(model),
        year = Value(year),
        color = Value(color),
        licensePlate = Value(licensePlate),
        category = Value(category),
        cachedAt = Value(cachedAt);
  static Insertable<CachedDriverVehicle> custom({
    Expression<String>? id,
    Expression<String>? driverId,
    Expression<String>? make,
    Expression<String>? model,
    Expression<int>? year,
    Expression<String>? color,
    Expression<String>? licensePlate,
    Expression<String>? category,
    Expression<bool>? isVerified,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (driverId != null) 'driver_id': driverId,
      if (make != null) 'make': make,
      if (model != null) 'model': model,
      if (year != null) 'year': year,
      if (color != null) 'color': color,
      if (licensePlate != null) 'license_plate': licensePlate,
      if (category != null) 'category': category,
      if (isVerified != null) 'is_verified': isVerified,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDriverVehiclesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? driverId,
      Value<String>? make,
      Value<String>? model,
      Value<int>? year,
      Value<String>? color,
      Value<String>? licensePlate,
      Value<String>? category,
      Value<bool>? isVerified,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedDriverVehiclesTableCompanion(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
      licensePlate: licensePlate ?? this.licensePlate,
      category: category ?? this.category,
      isVerified: isVerified ?? this.isVerified,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (driverId.present) {
      map['driver_id'] = Variable<String>(driverId.value);
    }
    if (make.present) {
      map['make'] = Variable<String>(make.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (licensePlate.present) {
      map['license_plate'] = Variable<String>(licensePlate.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (isVerified.present) {
      map['is_verified'] = Variable<bool>(isVerified.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDriverVehiclesTableCompanion(')
          ..write('id: $id, ')
          ..write('driverId: $driverId, ')
          ..write('make: $make, ')
          ..write('model: $model, ')
          ..write('year: $year, ')
          ..write('color: $color, ')
          ..write('licensePlate: $licensePlate, ')
          ..write('category: $category, ')
          ..write('isVerified: $isVerified, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedTripsDeliveriesTableTable extends CachedTripsDeliveriesTable
    with TableInfo<$CachedTripsDeliveriesTableTable, CachedTripDelivery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTripsDeliveriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _passengerIdMeta =
      const VerificationMeta('passengerId');
  @override
  late final GeneratedColumn<String> passengerId = GeneratedColumn<String>(
      'passenger_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _driverIdMeta =
      const VerificationMeta('driverId');
  @override
  late final GeneratedColumn<String> driverId = GeneratedColumn<String>(
      'driver_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _vehicleIdMeta =
      const VerificationMeta('vehicleId');
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
      'vehicle_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serviceTypeMeta =
      const VerificationMeta('serviceType');
  @override
  late final GeneratedColumn<String> serviceType = GeneratedColumn<String>(
      'service_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pickupLatMeta =
      const VerificationMeta('pickupLat');
  @override
  late final GeneratedColumn<double> pickupLat = GeneratedColumn<double>(
      'pickup_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pickupLngMeta =
      const VerificationMeta('pickupLng');
  @override
  late final GeneratedColumn<double> pickupLng = GeneratedColumn<double>(
      'pickup_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pickupAddressTextMeta =
      const VerificationMeta('pickupAddressText');
  @override
  late final GeneratedColumn<String> pickupAddressText =
      GeneratedColumn<String>('pickup_address_text', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pickupGeohashMeta =
      const VerificationMeta('pickupGeohash');
  @override
  late final GeneratedColumn<String> pickupGeohash = GeneratedColumn<String>(
      'pickup_geohash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dropoffLatMeta =
      const VerificationMeta('dropoffLat');
  @override
  late final GeneratedColumn<double> dropoffLat = GeneratedColumn<double>(
      'dropoff_lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _dropoffLngMeta =
      const VerificationMeta('dropoffLng');
  @override
  late final GeneratedColumn<double> dropoffLng = GeneratedColumn<double>(
      'dropoff_lng', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _dropoffAddressTextMeta =
      const VerificationMeta('dropoffAddressText');
  @override
  late final GeneratedColumn<String> dropoffAddressText =
      GeneratedColumn<String>('dropoff_address_text', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fareAmountMeta =
      const VerificationMeta('fareAmount');
  @override
  late final GeneratedColumn<double> fareAmount = GeneratedColumn<double>(
      'fare_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('SLE'));
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _distanceKmMeta =
      const VerificationMeta('distanceKm');
  @override
  late final GeneratedColumn<double> distanceKm = GeneratedColumn<double>(
      'distance_km', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _durationMinsMeta =
      const VerificationMeta('durationMins');
  @override
  late final GeneratedColumn<int> durationMins = GeneratedColumn<int>(
      'duration_mins', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deliveryPackageJsonMeta =
      const VerificationMeta('deliveryPackageJson');
  @override
  late final GeneratedColumn<String> deliveryPackageJson =
      GeneratedColumn<String>('delivery_package_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        passengerId,
        driverId,
        vehicleId,
        serviceType,
        pickupLat,
        pickupLng,
        pickupAddressText,
        pickupGeohash,
        dropoffLat,
        dropoffLng,
        dropoffAddressText,
        status,
        fareAmount,
        currency,
        paymentMethod,
        distanceKm,
        durationMins,
        deliveryPackageJson,
        isSynced,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_trips_deliveries_table';
  @override
  VerificationContext validateIntegrity(Insertable<CachedTripDelivery> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('passenger_id')) {
      context.handle(
          _passengerIdMeta,
          passengerId.isAcceptableOrUnknown(
              data['passenger_id']!, _passengerIdMeta));
    } else if (isInserting) {
      context.missing(_passengerIdMeta);
    }
    if (data.containsKey('driver_id')) {
      context.handle(_driverIdMeta,
          driverId.isAcceptableOrUnknown(data['driver_id']!, _driverIdMeta));
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(_vehicleIdMeta,
          vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta));
    }
    if (data.containsKey('service_type')) {
      context.handle(
          _serviceTypeMeta,
          serviceType.isAcceptableOrUnknown(
              data['service_type']!, _serviceTypeMeta));
    } else if (isInserting) {
      context.missing(_serviceTypeMeta);
    }
    if (data.containsKey('pickup_lat')) {
      context.handle(_pickupLatMeta,
          pickupLat.isAcceptableOrUnknown(data['pickup_lat']!, _pickupLatMeta));
    } else if (isInserting) {
      context.missing(_pickupLatMeta);
    }
    if (data.containsKey('pickup_lng')) {
      context.handle(_pickupLngMeta,
          pickupLng.isAcceptableOrUnknown(data['pickup_lng']!, _pickupLngMeta));
    } else if (isInserting) {
      context.missing(_pickupLngMeta);
    }
    if (data.containsKey('pickup_address_text')) {
      context.handle(
          _pickupAddressTextMeta,
          pickupAddressText.isAcceptableOrUnknown(
              data['pickup_address_text']!, _pickupAddressTextMeta));
    } else if (isInserting) {
      context.missing(_pickupAddressTextMeta);
    }
    if (data.containsKey('pickup_geohash')) {
      context.handle(
          _pickupGeohashMeta,
          pickupGeohash.isAcceptableOrUnknown(
              data['pickup_geohash']!, _pickupGeohashMeta));
    } else if (isInserting) {
      context.missing(_pickupGeohashMeta);
    }
    if (data.containsKey('dropoff_lat')) {
      context.handle(
          _dropoffLatMeta,
          dropoffLat.isAcceptableOrUnknown(
              data['dropoff_lat']!, _dropoffLatMeta));
    } else if (isInserting) {
      context.missing(_dropoffLatMeta);
    }
    if (data.containsKey('dropoff_lng')) {
      context.handle(
          _dropoffLngMeta,
          dropoffLng.isAcceptableOrUnknown(
              data['dropoff_lng']!, _dropoffLngMeta));
    } else if (isInserting) {
      context.missing(_dropoffLngMeta);
    }
    if (data.containsKey('dropoff_address_text')) {
      context.handle(
          _dropoffAddressTextMeta,
          dropoffAddressText.isAcceptableOrUnknown(
              data['dropoff_address_text']!, _dropoffAddressTextMeta));
    } else if (isInserting) {
      context.missing(_dropoffAddressTextMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('fare_amount')) {
      context.handle(
          _fareAmountMeta,
          fareAmount.isAcceptableOrUnknown(
              data['fare_amount']!, _fareAmountMeta));
    } else if (isInserting) {
      context.missing(_fareAmountMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('payment_method')) {
      context.handle(
          _paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(
              data['payment_method']!, _paymentMethodMeta));
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('distance_km')) {
      context.handle(
          _distanceKmMeta,
          distanceKm.isAcceptableOrUnknown(
              data['distance_km']!, _distanceKmMeta));
    } else if (isInserting) {
      context.missing(_distanceKmMeta);
    }
    if (data.containsKey('duration_mins')) {
      context.handle(
          _durationMinsMeta,
          durationMins.isAcceptableOrUnknown(
              data['duration_mins']!, _durationMinsMeta));
    } else if (isInserting) {
      context.missing(_durationMinsMeta);
    }
    if (data.containsKey('delivery_package_json')) {
      context.handle(
          _deliveryPackageJsonMeta,
          deliveryPackageJson.isAcceptableOrUnknown(
              data['delivery_package_json']!, _deliveryPackageJsonMeta));
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedTripDelivery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTripDelivery(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      passengerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}passenger_id'])!,
      driverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}driver_id']),
      vehicleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}vehicle_id']),
      serviceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}service_type'])!,
      pickupLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}pickup_lat'])!,
      pickupLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}pickup_lng'])!,
      pickupAddressText: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}pickup_address_text'])!,
      pickupGeohash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pickup_geohash'])!,
      dropoffLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}dropoff_lat'])!,
      dropoffLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}dropoff_lng'])!,
      dropoffAddressText: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}dropoff_address_text'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      fareAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}fare_amount'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      paymentMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_method'])!,
      distanceKm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}distance_km'])!,
      durationMins: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_mins'])!,
      deliveryPackageJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}delivery_package_json']),
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedTripsDeliveriesTableTable createAlias(String alias) {
    return $CachedTripsDeliveriesTableTable(attachedDatabase, alias);
  }
}

class CachedTripDelivery extends DataClass
    implements Insertable<CachedTripDelivery> {
  final String id;
  final String passengerId;
  final String? driverId;
  final String? vehicleId;
  final String serviceType;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddressText;
  final String pickupGeohash;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddressText;
  final String status;
  final double fareAmount;
  final String currency;
  final String paymentMethod;
  final double distanceKm;
  final int durationMins;
  final String? deliveryPackageJson;
  final bool isSynced;
  final int cachedAt;
  const CachedTripDelivery(
      {required this.id,
      required this.passengerId,
      this.driverId,
      this.vehicleId,
      required this.serviceType,
      required this.pickupLat,
      required this.pickupLng,
      required this.pickupAddressText,
      required this.pickupGeohash,
      required this.dropoffLat,
      required this.dropoffLng,
      required this.dropoffAddressText,
      required this.status,
      required this.fareAmount,
      required this.currency,
      required this.paymentMethod,
      required this.distanceKm,
      required this.durationMins,
      this.deliveryPackageJson,
      required this.isSynced,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['passenger_id'] = Variable<String>(passengerId);
    if (!nullToAbsent || driverId != null) {
      map['driver_id'] = Variable<String>(driverId);
    }
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    map['service_type'] = Variable<String>(serviceType);
    map['pickup_lat'] = Variable<double>(pickupLat);
    map['pickup_lng'] = Variable<double>(pickupLng);
    map['pickup_address_text'] = Variable<String>(pickupAddressText);
    map['pickup_geohash'] = Variable<String>(pickupGeohash);
    map['dropoff_lat'] = Variable<double>(dropoffLat);
    map['dropoff_lng'] = Variable<double>(dropoffLng);
    map['dropoff_address_text'] = Variable<String>(dropoffAddressText);
    map['status'] = Variable<String>(status);
    map['fare_amount'] = Variable<double>(fareAmount);
    map['currency'] = Variable<String>(currency);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['distance_km'] = Variable<double>(distanceKm);
    map['duration_mins'] = Variable<int>(durationMins);
    if (!nullToAbsent || deliveryPackageJson != null) {
      map['delivery_package_json'] = Variable<String>(deliveryPackageJson);
    }
    map['is_synced'] = Variable<bool>(isSynced);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedTripsDeliveriesTableCompanion toCompanion(bool nullToAbsent) {
    return CachedTripsDeliveriesTableCompanion(
      id: Value(id),
      passengerId: Value(passengerId),
      driverId: driverId == null && nullToAbsent
          ? const Value.absent()
          : Value(driverId),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      serviceType: Value(serviceType),
      pickupLat: Value(pickupLat),
      pickupLng: Value(pickupLng),
      pickupAddressText: Value(pickupAddressText),
      pickupGeohash: Value(pickupGeohash),
      dropoffLat: Value(dropoffLat),
      dropoffLng: Value(dropoffLng),
      dropoffAddressText: Value(dropoffAddressText),
      status: Value(status),
      fareAmount: Value(fareAmount),
      currency: Value(currency),
      paymentMethod: Value(paymentMethod),
      distanceKm: Value(distanceKm),
      durationMins: Value(durationMins),
      deliveryPackageJson: deliveryPackageJson == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryPackageJson),
      isSynced: Value(isSynced),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedTripDelivery.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTripDelivery(
      id: serializer.fromJson<String>(json['id']),
      passengerId: serializer.fromJson<String>(json['passengerId']),
      driverId: serializer.fromJson<String?>(json['driverId']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      serviceType: serializer.fromJson<String>(json['serviceType']),
      pickupLat: serializer.fromJson<double>(json['pickupLat']),
      pickupLng: serializer.fromJson<double>(json['pickupLng']),
      pickupAddressText: serializer.fromJson<String>(json['pickupAddressText']),
      pickupGeohash: serializer.fromJson<String>(json['pickupGeohash']),
      dropoffLat: serializer.fromJson<double>(json['dropoffLat']),
      dropoffLng: serializer.fromJson<double>(json['dropoffLng']),
      dropoffAddressText:
          serializer.fromJson<String>(json['dropoffAddressText']),
      status: serializer.fromJson<String>(json['status']),
      fareAmount: serializer.fromJson<double>(json['fareAmount']),
      currency: serializer.fromJson<String>(json['currency']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      distanceKm: serializer.fromJson<double>(json['distanceKm']),
      durationMins: serializer.fromJson<int>(json['durationMins']),
      deliveryPackageJson:
          serializer.fromJson<String?>(json['deliveryPackageJson']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'passengerId': serializer.toJson<String>(passengerId),
      'driverId': serializer.toJson<String?>(driverId),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'serviceType': serializer.toJson<String>(serviceType),
      'pickupLat': serializer.toJson<double>(pickupLat),
      'pickupLng': serializer.toJson<double>(pickupLng),
      'pickupAddressText': serializer.toJson<String>(pickupAddressText),
      'pickupGeohash': serializer.toJson<String>(pickupGeohash),
      'dropoffLat': serializer.toJson<double>(dropoffLat),
      'dropoffLng': serializer.toJson<double>(dropoffLng),
      'dropoffAddressText': serializer.toJson<String>(dropoffAddressText),
      'status': serializer.toJson<String>(status),
      'fareAmount': serializer.toJson<double>(fareAmount),
      'currency': serializer.toJson<String>(currency),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'distanceKm': serializer.toJson<double>(distanceKm),
      'durationMins': serializer.toJson<int>(durationMins),
      'deliveryPackageJson': serializer.toJson<String?>(deliveryPackageJson),
      'isSynced': serializer.toJson<bool>(isSynced),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedTripDelivery copyWith(
          {String? id,
          String? passengerId,
          Value<String?> driverId = const Value.absent(),
          Value<String?> vehicleId = const Value.absent(),
          String? serviceType,
          double? pickupLat,
          double? pickupLng,
          String? pickupAddressText,
          String? pickupGeohash,
          double? dropoffLat,
          double? dropoffLng,
          String? dropoffAddressText,
          String? status,
          double? fareAmount,
          String? currency,
          String? paymentMethod,
          double? distanceKm,
          int? durationMins,
          Value<String?> deliveryPackageJson = const Value.absent(),
          bool? isSynced,
          int? cachedAt}) =>
      CachedTripDelivery(
        id: id ?? this.id,
        passengerId: passengerId ?? this.passengerId,
        driverId: driverId.present ? driverId.value : this.driverId,
        vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
        serviceType: serviceType ?? this.serviceType,
        pickupLat: pickupLat ?? this.pickupLat,
        pickupLng: pickupLng ?? this.pickupLng,
        pickupAddressText: pickupAddressText ?? this.pickupAddressText,
        pickupGeohash: pickupGeohash ?? this.pickupGeohash,
        dropoffLat: dropoffLat ?? this.dropoffLat,
        dropoffLng: dropoffLng ?? this.dropoffLng,
        dropoffAddressText: dropoffAddressText ?? this.dropoffAddressText,
        status: status ?? this.status,
        fareAmount: fareAmount ?? this.fareAmount,
        currency: currency ?? this.currency,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        distanceKm: distanceKm ?? this.distanceKm,
        durationMins: durationMins ?? this.durationMins,
        deliveryPackageJson: deliveryPackageJson.present
            ? deliveryPackageJson.value
            : this.deliveryPackageJson,
        isSynced: isSynced ?? this.isSynced,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedTripDelivery copyWithCompanion(
      CachedTripsDeliveriesTableCompanion data) {
    return CachedTripDelivery(
      id: data.id.present ? data.id.value : this.id,
      passengerId:
          data.passengerId.present ? data.passengerId.value : this.passengerId,
      driverId: data.driverId.present ? data.driverId.value : this.driverId,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      serviceType:
          data.serviceType.present ? data.serviceType.value : this.serviceType,
      pickupLat: data.pickupLat.present ? data.pickupLat.value : this.pickupLat,
      pickupLng: data.pickupLng.present ? data.pickupLng.value : this.pickupLng,
      pickupAddressText: data.pickupAddressText.present
          ? data.pickupAddressText.value
          : this.pickupAddressText,
      pickupGeohash: data.pickupGeohash.present
          ? data.pickupGeohash.value
          : this.pickupGeohash,
      dropoffLat:
          data.dropoffLat.present ? data.dropoffLat.value : this.dropoffLat,
      dropoffLng:
          data.dropoffLng.present ? data.dropoffLng.value : this.dropoffLng,
      dropoffAddressText: data.dropoffAddressText.present
          ? data.dropoffAddressText.value
          : this.dropoffAddressText,
      status: data.status.present ? data.status.value : this.status,
      fareAmount:
          data.fareAmount.present ? data.fareAmount.value : this.fareAmount,
      currency: data.currency.present ? data.currency.value : this.currency,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      distanceKm:
          data.distanceKm.present ? data.distanceKm.value : this.distanceKm,
      durationMins: data.durationMins.present
          ? data.durationMins.value
          : this.durationMins,
      deliveryPackageJson: data.deliveryPackageJson.present
          ? data.deliveryPackageJson.value
          : this.deliveryPackageJson,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTripDelivery(')
          ..write('id: $id, ')
          ..write('passengerId: $passengerId, ')
          ..write('driverId: $driverId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('serviceType: $serviceType, ')
          ..write('pickupLat: $pickupLat, ')
          ..write('pickupLng: $pickupLng, ')
          ..write('pickupAddressText: $pickupAddressText, ')
          ..write('pickupGeohash: $pickupGeohash, ')
          ..write('dropoffLat: $dropoffLat, ')
          ..write('dropoffLng: $dropoffLng, ')
          ..write('dropoffAddressText: $dropoffAddressText, ')
          ..write('status: $status, ')
          ..write('fareAmount: $fareAmount, ')
          ..write('currency: $currency, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('durationMins: $durationMins, ')
          ..write('deliveryPackageJson: $deliveryPackageJson, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        passengerId,
        driverId,
        vehicleId,
        serviceType,
        pickupLat,
        pickupLng,
        pickupAddressText,
        pickupGeohash,
        dropoffLat,
        dropoffLng,
        dropoffAddressText,
        status,
        fareAmount,
        currency,
        paymentMethod,
        distanceKm,
        durationMins,
        deliveryPackageJson,
        isSynced,
        cachedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTripDelivery &&
          other.id == this.id &&
          other.passengerId == this.passengerId &&
          other.driverId == this.driverId &&
          other.vehicleId == this.vehicleId &&
          other.serviceType == this.serviceType &&
          other.pickupLat == this.pickupLat &&
          other.pickupLng == this.pickupLng &&
          other.pickupAddressText == this.pickupAddressText &&
          other.pickupGeohash == this.pickupGeohash &&
          other.dropoffLat == this.dropoffLat &&
          other.dropoffLng == this.dropoffLng &&
          other.dropoffAddressText == this.dropoffAddressText &&
          other.status == this.status &&
          other.fareAmount == this.fareAmount &&
          other.currency == this.currency &&
          other.paymentMethod == this.paymentMethod &&
          other.distanceKm == this.distanceKm &&
          other.durationMins == this.durationMins &&
          other.deliveryPackageJson == this.deliveryPackageJson &&
          other.isSynced == this.isSynced &&
          other.cachedAt == this.cachedAt);
}

class CachedTripsDeliveriesTableCompanion
    extends UpdateCompanion<CachedTripDelivery> {
  final Value<String> id;
  final Value<String> passengerId;
  final Value<String?> driverId;
  final Value<String?> vehicleId;
  final Value<String> serviceType;
  final Value<double> pickupLat;
  final Value<double> pickupLng;
  final Value<String> pickupAddressText;
  final Value<String> pickupGeohash;
  final Value<double> dropoffLat;
  final Value<double> dropoffLng;
  final Value<String> dropoffAddressText;
  final Value<String> status;
  final Value<double> fareAmount;
  final Value<String> currency;
  final Value<String> paymentMethod;
  final Value<double> distanceKm;
  final Value<int> durationMins;
  final Value<String?> deliveryPackageJson;
  final Value<bool> isSynced;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedTripsDeliveriesTableCompanion({
    this.id = const Value.absent(),
    this.passengerId = const Value.absent(),
    this.driverId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.serviceType = const Value.absent(),
    this.pickupLat = const Value.absent(),
    this.pickupLng = const Value.absent(),
    this.pickupAddressText = const Value.absent(),
    this.pickupGeohash = const Value.absent(),
    this.dropoffLat = const Value.absent(),
    this.dropoffLng = const Value.absent(),
    this.dropoffAddressText = const Value.absent(),
    this.status = const Value.absent(),
    this.fareAmount = const Value.absent(),
    this.currency = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.distanceKm = const Value.absent(),
    this.durationMins = const Value.absent(),
    this.deliveryPackageJson = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTripsDeliveriesTableCompanion.insert({
    required String id,
    required String passengerId,
    this.driverId = const Value.absent(),
    this.vehicleId = const Value.absent(),
    required String serviceType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddressText,
    required String pickupGeohash,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddressText,
    required String status,
    required double fareAmount,
    this.currency = const Value.absent(),
    required String paymentMethod,
    required double distanceKm,
    required int durationMins,
    this.deliveryPackageJson = const Value.absent(),
    this.isSynced = const Value.absent(),
    required int cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        passengerId = Value(passengerId),
        serviceType = Value(serviceType),
        pickupLat = Value(pickupLat),
        pickupLng = Value(pickupLng),
        pickupAddressText = Value(pickupAddressText),
        pickupGeohash = Value(pickupGeohash),
        dropoffLat = Value(dropoffLat),
        dropoffLng = Value(dropoffLng),
        dropoffAddressText = Value(dropoffAddressText),
        status = Value(status),
        fareAmount = Value(fareAmount),
        paymentMethod = Value(paymentMethod),
        distanceKm = Value(distanceKm),
        durationMins = Value(durationMins),
        cachedAt = Value(cachedAt);
  static Insertable<CachedTripDelivery> custom({
    Expression<String>? id,
    Expression<String>? passengerId,
    Expression<String>? driverId,
    Expression<String>? vehicleId,
    Expression<String>? serviceType,
    Expression<double>? pickupLat,
    Expression<double>? pickupLng,
    Expression<String>? pickupAddressText,
    Expression<String>? pickupGeohash,
    Expression<double>? dropoffLat,
    Expression<double>? dropoffLng,
    Expression<String>? dropoffAddressText,
    Expression<String>? status,
    Expression<double>? fareAmount,
    Expression<String>? currency,
    Expression<String>? paymentMethod,
    Expression<double>? distanceKm,
    Expression<int>? durationMins,
    Expression<String>? deliveryPackageJson,
    Expression<bool>? isSynced,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (passengerId != null) 'passenger_id': passengerId,
      if (driverId != null) 'driver_id': driverId,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (serviceType != null) 'service_type': serviceType,
      if (pickupLat != null) 'pickup_lat': pickupLat,
      if (pickupLng != null) 'pickup_lng': pickupLng,
      if (pickupAddressText != null) 'pickup_address_text': pickupAddressText,
      if (pickupGeohash != null) 'pickup_geohash': pickupGeohash,
      if (dropoffLat != null) 'dropoff_lat': dropoffLat,
      if (dropoffLng != null) 'dropoff_lng': dropoffLng,
      if (dropoffAddressText != null)
        'dropoff_address_text': dropoffAddressText,
      if (status != null) 'status': status,
      if (fareAmount != null) 'fare_amount': fareAmount,
      if (currency != null) 'currency': currency,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (distanceKm != null) 'distance_km': distanceKm,
      if (durationMins != null) 'duration_mins': durationMins,
      if (deliveryPackageJson != null)
        'delivery_package_json': deliveryPackageJson,
      if (isSynced != null) 'is_synced': isSynced,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTripsDeliveriesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? passengerId,
      Value<String?>? driverId,
      Value<String?>? vehicleId,
      Value<String>? serviceType,
      Value<double>? pickupLat,
      Value<double>? pickupLng,
      Value<String>? pickupAddressText,
      Value<String>? pickupGeohash,
      Value<double>? dropoffLat,
      Value<double>? dropoffLng,
      Value<String>? dropoffAddressText,
      Value<String>? status,
      Value<double>? fareAmount,
      Value<String>? currency,
      Value<String>? paymentMethod,
      Value<double>? distanceKm,
      Value<int>? durationMins,
      Value<String?>? deliveryPackageJson,
      Value<bool>? isSynced,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return CachedTripsDeliveriesTableCompanion(
      id: id ?? this.id,
      passengerId: passengerId ?? this.passengerId,
      driverId: driverId ?? this.driverId,
      vehicleId: vehicleId ?? this.vehicleId,
      serviceType: serviceType ?? this.serviceType,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      pickupAddressText: pickupAddressText ?? this.pickupAddressText,
      pickupGeohash: pickupGeohash ?? this.pickupGeohash,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      dropoffAddressText: dropoffAddressText ?? this.dropoffAddressText,
      status: status ?? this.status,
      fareAmount: fareAmount ?? this.fareAmount,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMins: durationMins ?? this.durationMins,
      deliveryPackageJson: deliveryPackageJson ?? this.deliveryPackageJson,
      isSynced: isSynced ?? this.isSynced,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (passengerId.present) {
      map['passenger_id'] = Variable<String>(passengerId.value);
    }
    if (driverId.present) {
      map['driver_id'] = Variable<String>(driverId.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (serviceType.present) {
      map['service_type'] = Variable<String>(serviceType.value);
    }
    if (pickupLat.present) {
      map['pickup_lat'] = Variable<double>(pickupLat.value);
    }
    if (pickupLng.present) {
      map['pickup_lng'] = Variable<double>(pickupLng.value);
    }
    if (pickupAddressText.present) {
      map['pickup_address_text'] = Variable<String>(pickupAddressText.value);
    }
    if (pickupGeohash.present) {
      map['pickup_geohash'] = Variable<String>(pickupGeohash.value);
    }
    if (dropoffLat.present) {
      map['dropoff_lat'] = Variable<double>(dropoffLat.value);
    }
    if (dropoffLng.present) {
      map['dropoff_lng'] = Variable<double>(dropoffLng.value);
    }
    if (dropoffAddressText.present) {
      map['dropoff_address_text'] = Variable<String>(dropoffAddressText.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (fareAmount.present) {
      map['fare_amount'] = Variable<double>(fareAmount.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (distanceKm.present) {
      map['distance_km'] = Variable<double>(distanceKm.value);
    }
    if (durationMins.present) {
      map['duration_mins'] = Variable<int>(durationMins.value);
    }
    if (deliveryPackageJson.present) {
      map['delivery_package_json'] =
          Variable<String>(deliveryPackageJson.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTripsDeliveriesTableCompanion(')
          ..write('id: $id, ')
          ..write('passengerId: $passengerId, ')
          ..write('driverId: $driverId, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('serviceType: $serviceType, ')
          ..write('pickupLat: $pickupLat, ')
          ..write('pickupLng: $pickupLng, ')
          ..write('pickupAddressText: $pickupAddressText, ')
          ..write('pickupGeohash: $pickupGeohash, ')
          ..write('dropoffLat: $dropoffLat, ')
          ..write('dropoffLng: $dropoffLng, ')
          ..write('dropoffAddressText: $dropoffAddressText, ')
          ..write('status: $status, ')
          ..write('fareAmount: $fareAmount, ')
          ..write('currency: $currency, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('durationMins: $durationMins, ')
          ..write('deliveryPackageJson: $deliveryPackageJson, ')
          ..write('isSynced: $isSynced, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SyncQueueTableTable syncQueueTable = $SyncQueueTableTable(this);
  late final $CachedPropertiesTableTable cachedPropertiesTable =
      $CachedPropertiesTableTable(this);
  late final $CachedRidesTableTable cachedRidesTable =
      $CachedRidesTableTable(this);
  late final $CachedWalletsTableTable cachedWalletsTable =
      $CachedWalletsTableTable(this);
  late final $CachedTransactionsTableTable cachedTransactionsTable =
      $CachedTransactionsTableTable(this);
  late final $CachedUsersTableTable cachedUsersTable =
      $CachedUsersTableTable(this);
  late final $CachedPropertyListingsTableTable cachedPropertyListingsTable =
      $CachedPropertyListingsTableTable(this);
  late final $CachedVehicleListingsTableTable cachedVehicleListingsTable =
      $CachedVehicleListingsTableTable(this);
  late final $CachedBookingsTableTable cachedBookingsTable =
      $CachedBookingsTableTable(this);
  late final $CachedDriverProfilesTableTable cachedDriverProfilesTable =
      $CachedDriverProfilesTableTable(this);
  late final $CachedDriverVehiclesTableTable cachedDriverVehiclesTable =
      $CachedDriverVehiclesTableTable(this);
  late final $CachedTripsDeliveriesTableTable cachedTripsDeliveriesTable =
      $CachedTripsDeliveriesTableTable(this);
  late final SyncQueueDao syncQueueDao = SyncQueueDao(this as AppDatabase);
  late final CachedPropertiesDao cachedPropertiesDao =
      CachedPropertiesDao(this as AppDatabase);
  late final CachedRidesDao cachedRidesDao =
      CachedRidesDao(this as AppDatabase);
  late final CachedWalletsDao cachedWalletsDao =
      CachedWalletsDao(this as AppDatabase);
  late final CachedUsersDao cachedUsersDao =
      CachedUsersDao(this as AppDatabase);
  late final CachedPropertyListingsDao cachedPropertyListingsDao =
      CachedPropertyListingsDao(this as AppDatabase);
  late final CachedVehicleListingsDao cachedVehicleListingsDao =
      CachedVehicleListingsDao(this as AppDatabase);
  late final CachedBookingsDao cachedBookingsDao =
      CachedBookingsDao(this as AppDatabase);
  late final CachedDriverProfilesDao cachedDriverProfilesDao =
      CachedDriverProfilesDao(this as AppDatabase);
  late final CachedTripsDeliveriesDao cachedTripsDeliveriesDao =
      CachedTripsDeliveriesDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        syncQueueTable,
        cachedPropertiesTable,
        cachedRidesTable,
        cachedWalletsTable,
        cachedTransactionsTable,
        cachedUsersTable,
        cachedPropertyListingsTable,
        cachedVehicleListingsTable,
        cachedBookingsTable,
        cachedDriverProfilesTable,
        cachedDriverVehiclesTable,
        cachedTripsDeliveriesTable
      ];
}

typedef $$SyncQueueTableTableCreateCompanionBuilder = SyncQueueTableCompanion
    Function({
  required String id,
  required String idempotencyKey,
  required String mutationPath,
  required OperationType operationType,
  required String entityType,
  required String entityId,
  required String payloadJson,
  Value<SyncStatus> status,
  Value<int> retryCount,
  Value<int> maxRetries,
  required int createdAt,
  Value<int?> lastAttemptAt,
  Value<String?> errorMessage,
  Value<int> priority,
  Value<int> rowid,
});
typedef $$SyncQueueTableTableUpdateCompanionBuilder = SyncQueueTableCompanion
    Function({
  Value<String> id,
  Value<String> idempotencyKey,
  Value<String> mutationPath,
  Value<OperationType> operationType,
  Value<String> entityType,
  Value<String> entityId,
  Value<String> payloadJson,
  Value<SyncStatus> status,
  Value<int> retryCount,
  Value<int> maxRetries,
  Value<int> createdAt,
  Value<int?> lastAttemptAt,
  Value<String?> errorMessage,
  Value<int> priority,
  Value<int> rowid,
});

class $$SyncQueueTableTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTableTable> {
  $$SyncQueueTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mutationPath => $composableBuilder(
      column: $table.mutationPath, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<OperationType, OperationType, String>
      get operationType => $composableBuilder(
          column: $table.operationType,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, String> get status =>
      $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));
}

class $$SyncQueueTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTableTable> {
  $$SyncQueueTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mutationPath => $composableBuilder(
      column: $table.mutationPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationType => $composableBuilder(
      column: $table.operationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTableTable> {
  $$SyncQueueTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey, builder: (column) => column);

  GeneratedColumn<String> get mutationPath => $composableBuilder(
      column: $table.mutationPath, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OperationType, String> get operationType =>
      $composableBuilder(
          column: $table.operationType, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SyncStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);
}

class $$SyncQueueTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncQueueTableTable,
    SyncQueueEntry,
    $$SyncQueueTableTableFilterComposer,
    $$SyncQueueTableTableOrderingComposer,
    $$SyncQueueTableTableAnnotationComposer,
    $$SyncQueueTableTableCreateCompanionBuilder,
    $$SyncQueueTableTableUpdateCompanionBuilder,
    (
      SyncQueueEntry,
      BaseReferences<_$AppDatabase, $SyncQueueTableTable, SyncQueueEntry>
    ),
    SyncQueueEntry,
    PrefetchHooks Function()> {
  $$SyncQueueTableTableTableManager(
      _$AppDatabase db, $SyncQueueTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> idempotencyKey = const Value.absent(),
            Value<String> mutationPath = const Value.absent(),
            Value<OperationType> operationType = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> entityId = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<SyncStatus> status = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int> maxRetries = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int?> lastAttemptAt = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncQueueTableCompanion(
            id: id,
            idempotencyKey: idempotencyKey,
            mutationPath: mutationPath,
            operationType: operationType,
            entityType: entityType,
            entityId: entityId,
            payloadJson: payloadJson,
            status: status,
            retryCount: retryCount,
            maxRetries: maxRetries,
            createdAt: createdAt,
            lastAttemptAt: lastAttemptAt,
            errorMessage: errorMessage,
            priority: priority,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String idempotencyKey,
            required String mutationPath,
            required OperationType operationType,
            required String entityType,
            required String entityId,
            required String payloadJson,
            Value<SyncStatus> status = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int> maxRetries = const Value.absent(),
            required int createdAt,
            Value<int?> lastAttemptAt = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncQueueTableCompanion.insert(
            id: id,
            idempotencyKey: idempotencyKey,
            mutationPath: mutationPath,
            operationType: operationType,
            entityType: entityType,
            entityId: entityId,
            payloadJson: payloadJson,
            status: status,
            retryCount: retryCount,
            maxRetries: maxRetries,
            createdAt: createdAt,
            lastAttemptAt: lastAttemptAt,
            errorMessage: errorMessage,
            priority: priority,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$SyncQueueTableTable, SyncQueueEntry>(table),
                    BaseReferences<_$AppDatabase, $SyncQueueTableTable,
                        SyncQueueEntry>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncQueueTableTable,
    SyncQueueEntry,
    $$SyncQueueTableTableFilterComposer,
    $$SyncQueueTableTableOrderingComposer,
    $$SyncQueueTableTableAnnotationComposer,
    $$SyncQueueTableTableCreateCompanionBuilder,
    $$SyncQueueTableTableUpdateCompanionBuilder,
    (
      SyncQueueEntry,
      BaseReferences<_$AppDatabase, $SyncQueueTableTable, SyncQueueEntry>
    ),
    SyncQueueEntry,
    PrefetchHooks Function()>;
typedef $$CachedPropertiesTableTableCreateCompanionBuilder
    = CachedPropertiesTableCompanion Function({
  required String id,
  required String ownerId,
  required String title,
  required String description,
  required String category,
  required double price,
  Value<double?> hourlyRate,
  Value<String> currency,
  required String address,
  required String city,
  required String country,
  required double latitude,
  required double longitude,
  required String geohash,
  required String availabilityStatus,
  Value<String> imageUrlsJson,
  Value<bool> isFeatured,
  Value<int> viewCount,
  Value<EntitySyncStatus> syncStatus,
  required int localUpdatedAt,
  required int remoteUpdatedAt,
  Value<int?> lastSyncedAt,
  Value<int> rowid,
});
typedef $$CachedPropertiesTableTableUpdateCompanionBuilder
    = CachedPropertiesTableCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String> title,
  Value<String> description,
  Value<String> category,
  Value<double> price,
  Value<double?> hourlyRate,
  Value<String> currency,
  Value<String> address,
  Value<String> city,
  Value<String> country,
  Value<double> latitude,
  Value<double> longitude,
  Value<String> geohash,
  Value<String> availabilityStatus,
  Value<String> imageUrlsJson,
  Value<bool> isFeatured,
  Value<int> viewCount,
  Value<EntitySyncStatus> syncStatus,
  Value<int> localUpdatedAt,
  Value<int> remoteUpdatedAt,
  Value<int?> lastSyncedAt,
  Value<int> rowid,
});

class $$CachedPropertiesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPropertiesTableTable> {
  $$CachedPropertiesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get hourlyRate => $composableBuilder(
      column: $table.hourlyRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get city => $composableBuilder(
      column: $table.city, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get country => $composableBuilder(
      column: $table.country, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get geohash => $composableBuilder(
      column: $table.geohash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get availabilityStatus => $composableBuilder(
      column: $table.availabilityStatus,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrlsJson => $composableBuilder(
      column: $table.imageUrlsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFeatured => $composableBuilder(
      column: $table.isFeatured, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get viewCount => $composableBuilder(
      column: $table.viewCount, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<EntitySyncStatus, EntitySyncStatus, String>
      get syncStatus => $composableBuilder(
          column: $table.syncStatus,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedPropertiesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPropertiesTableTable> {
  $$CachedPropertiesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get hourlyRate => $composableBuilder(
      column: $table.hourlyRate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get city => $composableBuilder(
      column: $table.city, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get country => $composableBuilder(
      column: $table.country, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get geohash => $composableBuilder(
      column: $table.geohash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get availabilityStatus => $composableBuilder(
      column: $table.availabilityStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrlsJson => $composableBuilder(
      column: $table.imageUrlsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFeatured => $composableBuilder(
      column: $table.isFeatured, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get viewCount => $composableBuilder(
      column: $table.viewCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$CachedPropertiesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPropertiesTableTable> {
  $$CachedPropertiesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get hourlyRate => $composableBuilder(
      column: $table.hourlyRate, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get city =>
      $composableBuilder(column: $table.city, builder: (column) => column);

  GeneratedColumn<String> get country =>
      $composableBuilder(column: $table.country, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get geohash =>
      $composableBuilder(column: $table.geohash, builder: (column) => column);

  GeneratedColumn<String> get availabilityStatus => $composableBuilder(
      column: $table.availabilityStatus, builder: (column) => column);

  GeneratedColumn<String> get imageUrlsJson => $composableBuilder(
      column: $table.imageUrlsJson, builder: (column) => column);

  GeneratedColumn<bool> get isFeatured => $composableBuilder(
      column: $table.isFeatured, builder: (column) => column);

  GeneratedColumn<int> get viewCount =>
      $composableBuilder(column: $table.viewCount, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EntitySyncStatus, String> get syncStatus =>
      $composableBuilder(
          column: $table.syncStatus, builder: (column) => column);

  GeneratedColumn<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt, builder: (column) => column);

  GeneratedColumn<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$CachedPropertiesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedPropertiesTableTable,
    CachedProperty,
    $$CachedPropertiesTableTableFilterComposer,
    $$CachedPropertiesTableTableOrderingComposer,
    $$CachedPropertiesTableTableAnnotationComposer,
    $$CachedPropertiesTableTableCreateCompanionBuilder,
    $$CachedPropertiesTableTableUpdateCompanionBuilder,
    (
      CachedProperty,
      BaseReferences<_$AppDatabase, $CachedPropertiesTableTable, CachedProperty>
    ),
    CachedProperty,
    PrefetchHooks Function()> {
  $$CachedPropertiesTableTableTableManager(
      _$AppDatabase db, $CachedPropertiesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPropertiesTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPropertiesTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPropertiesTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<double?> hourlyRate = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String> address = const Value.absent(),
            Value<String> city = const Value.absent(),
            Value<String> country = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<String> geohash = const Value.absent(),
            Value<String> availabilityStatus = const Value.absent(),
            Value<String> imageUrlsJson = const Value.absent(),
            Value<bool> isFeatured = const Value.absent(),
            Value<int> viewCount = const Value.absent(),
            Value<EntitySyncStatus> syncStatus = const Value.absent(),
            Value<int> localUpdatedAt = const Value.absent(),
            Value<int> remoteUpdatedAt = const Value.absent(),
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPropertiesTableCompanion(
            id: id,
            ownerId: ownerId,
            title: title,
            description: description,
            category: category,
            price: price,
            hourlyRate: hourlyRate,
            currency: currency,
            address: address,
            city: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            geohash: geohash,
            availabilityStatus: availabilityStatus,
            imageUrlsJson: imageUrlsJson,
            isFeatured: isFeatured,
            viewCount: viewCount,
            syncStatus: syncStatus,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String ownerId,
            required String title,
            required String description,
            required String category,
            required double price,
            Value<double?> hourlyRate = const Value.absent(),
            Value<String> currency = const Value.absent(),
            required String address,
            required String city,
            required String country,
            required double latitude,
            required double longitude,
            required String geohash,
            required String availabilityStatus,
            Value<String> imageUrlsJson = const Value.absent(),
            Value<bool> isFeatured = const Value.absent(),
            Value<int> viewCount = const Value.absent(),
            Value<EntitySyncStatus> syncStatus = const Value.absent(),
            required int localUpdatedAt,
            required int remoteUpdatedAt,
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPropertiesTableCompanion.insert(
            id: id,
            ownerId: ownerId,
            title: title,
            description: description,
            category: category,
            price: price,
            hourlyRate: hourlyRate,
            currency: currency,
            address: address,
            city: city,
            country: country,
            latitude: latitude,
            longitude: longitude,
            geohash: geohash,
            availabilityStatus: availabilityStatus,
            imageUrlsJson: imageUrlsJson,
            isFeatured: isFeatured,
            viewCount: viewCount,
            syncStatus: syncStatus,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedPropertiesTableTable, CachedProperty>(
                        table),
                    BaseReferences<_$AppDatabase, $CachedPropertiesTableTable,
                        CachedProperty>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedPropertiesTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedPropertiesTableTable,
        CachedProperty,
        $$CachedPropertiesTableTableFilterComposer,
        $$CachedPropertiesTableTableOrderingComposer,
        $$CachedPropertiesTableTableAnnotationComposer,
        $$CachedPropertiesTableTableCreateCompanionBuilder,
        $$CachedPropertiesTableTableUpdateCompanionBuilder,
        (
          CachedProperty,
          BaseReferences<_$AppDatabase, $CachedPropertiesTableTable,
              CachedProperty>
        ),
        CachedProperty,
        PrefetchHooks Function()>;
typedef $$CachedRidesTableTableCreateCompanionBuilder
    = CachedRidesTableCompanion Function({
  required String id,
  required String passengerId,
  Value<String?> driverId,
  Value<String?> vehicleId,
  required double pickupLat,
  required double pickupLng,
  Value<String?> pickupAddress,
  required double dropoffLat,
  required double dropoffLng,
  Value<String?> dropoffAddress,
  required double distanceKm,
  required int estimatedDurationMin,
  required double fareAmount,
  Value<String> currency,
  required double platformFee,
  required double driverPayout,
  required String status,
  required String paymentStatus,
  Value<String?> paymentReference,
  Value<String?> blockchainLogHash,
  Value<int?> acceptedAt,
  Value<int?> startedAt,
  Value<int?> completedAt,
  Value<int?> cancelledAt,
  Value<String?> cancelReason,
  Value<EntitySyncStatus> syncStatus,
  required int localUpdatedAt,
  required int remoteUpdatedAt,
  Value<int?> lastSyncedAt,
  Value<int> rowid,
});
typedef $$CachedRidesTableTableUpdateCompanionBuilder
    = CachedRidesTableCompanion Function({
  Value<String> id,
  Value<String> passengerId,
  Value<String?> driverId,
  Value<String?> vehicleId,
  Value<double> pickupLat,
  Value<double> pickupLng,
  Value<String?> pickupAddress,
  Value<double> dropoffLat,
  Value<double> dropoffLng,
  Value<String?> dropoffAddress,
  Value<double> distanceKm,
  Value<int> estimatedDurationMin,
  Value<double> fareAmount,
  Value<String> currency,
  Value<double> platformFee,
  Value<double> driverPayout,
  Value<String> status,
  Value<String> paymentStatus,
  Value<String?> paymentReference,
  Value<String?> blockchainLogHash,
  Value<int?> acceptedAt,
  Value<int?> startedAt,
  Value<int?> completedAt,
  Value<int?> cancelledAt,
  Value<String?> cancelReason,
  Value<EntitySyncStatus> syncStatus,
  Value<int> localUpdatedAt,
  Value<int> remoteUpdatedAt,
  Value<int?> lastSyncedAt,
  Value<int> rowid,
});

class $$CachedRidesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedRidesTableTable> {
  $$CachedRidesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get passengerId => $composableBuilder(
      column: $table.passengerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driverId => $composableBuilder(
      column: $table.driverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get vehicleId => $composableBuilder(
      column: $table.vehicleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pickupLat => $composableBuilder(
      column: $table.pickupLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pickupLng => $composableBuilder(
      column: $table.pickupLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pickupAddress => $composableBuilder(
      column: $table.pickupAddress, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get dropoffLat => $composableBuilder(
      column: $table.dropoffLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get dropoffLng => $composableBuilder(
      column: $table.dropoffLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dropoffAddress => $composableBuilder(
      column: $table.dropoffAddress,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get distanceKm => $composableBuilder(
      column: $table.distanceKm, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estimatedDurationMin => $composableBuilder(
      column: $table.estimatedDurationMin,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get fareAmount => $composableBuilder(
      column: $table.fareAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get platformFee => $composableBuilder(
      column: $table.platformFee, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get driverPayout => $composableBuilder(
      column: $table.driverPayout, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentStatus => $composableBuilder(
      column: $table.paymentStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentReference => $composableBuilder(
      column: $table.paymentReference,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get blockchainLogHash => $composableBuilder(
      column: $table.blockchainLogHash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get acceptedAt => $composableBuilder(
      column: $table.acceptedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<EntitySyncStatus, EntitySyncStatus, String>
      get syncStatus => $composableBuilder(
          column: $table.syncStatus,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedRidesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedRidesTableTable> {
  $$CachedRidesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get passengerId => $composableBuilder(
      column: $table.passengerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driverId => $composableBuilder(
      column: $table.driverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get vehicleId => $composableBuilder(
      column: $table.vehicleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pickupLat => $composableBuilder(
      column: $table.pickupLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pickupLng => $composableBuilder(
      column: $table.pickupLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pickupAddress => $composableBuilder(
      column: $table.pickupAddress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get dropoffLat => $composableBuilder(
      column: $table.dropoffLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get dropoffLng => $composableBuilder(
      column: $table.dropoffLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dropoffAddress => $composableBuilder(
      column: $table.dropoffAddress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get distanceKm => $composableBuilder(
      column: $table.distanceKm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estimatedDurationMin => $composableBuilder(
      column: $table.estimatedDurationMin,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get fareAmount => $composableBuilder(
      column: $table.fareAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get platformFee => $composableBuilder(
      column: $table.platformFee, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get driverPayout => $composableBuilder(
      column: $table.driverPayout,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentStatus => $composableBuilder(
      column: $table.paymentStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentReference => $composableBuilder(
      column: $table.paymentReference,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get blockchainLogHash => $composableBuilder(
      column: $table.blockchainLogHash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get acceptedAt => $composableBuilder(
      column: $table.acceptedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$CachedRidesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedRidesTableTable> {
  $$CachedRidesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get passengerId => $composableBuilder(
      column: $table.passengerId, builder: (column) => column);

  GeneratedColumn<String> get driverId =>
      $composableBuilder(column: $table.driverId, builder: (column) => column);

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<double> get pickupLat =>
      $composableBuilder(column: $table.pickupLat, builder: (column) => column);

  GeneratedColumn<double> get pickupLng =>
      $composableBuilder(column: $table.pickupLng, builder: (column) => column);

  GeneratedColumn<String> get pickupAddress => $composableBuilder(
      column: $table.pickupAddress, builder: (column) => column);

  GeneratedColumn<double> get dropoffLat => $composableBuilder(
      column: $table.dropoffLat, builder: (column) => column);

  GeneratedColumn<double> get dropoffLng => $composableBuilder(
      column: $table.dropoffLng, builder: (column) => column);

  GeneratedColumn<String> get dropoffAddress => $composableBuilder(
      column: $table.dropoffAddress, builder: (column) => column);

  GeneratedColumn<double> get distanceKm => $composableBuilder(
      column: $table.distanceKm, builder: (column) => column);

  GeneratedColumn<int> get estimatedDurationMin => $composableBuilder(
      column: $table.estimatedDurationMin, builder: (column) => column);

  GeneratedColumn<double> get fareAmount => $composableBuilder(
      column: $table.fareAmount, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get platformFee => $composableBuilder(
      column: $table.platformFee, builder: (column) => column);

  GeneratedColumn<double> get driverPayout => $composableBuilder(
      column: $table.driverPayout, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get paymentStatus => $composableBuilder(
      column: $table.paymentStatus, builder: (column) => column);

  GeneratedColumn<String> get paymentReference => $composableBuilder(
      column: $table.paymentReference, builder: (column) => column);

  GeneratedColumn<String> get blockchainLogHash => $composableBuilder(
      column: $table.blockchainLogHash, builder: (column) => column);

  GeneratedColumn<int> get acceptedAt => $composableBuilder(
      column: $table.acceptedAt, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<int> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => column);

  GeneratedColumn<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EntitySyncStatus, String> get syncStatus =>
      $composableBuilder(
          column: $table.syncStatus, builder: (column) => column);

  GeneratedColumn<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt, builder: (column) => column);

  GeneratedColumn<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$CachedRidesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedRidesTableTable,
    CachedRide,
    $$CachedRidesTableTableFilterComposer,
    $$CachedRidesTableTableOrderingComposer,
    $$CachedRidesTableTableAnnotationComposer,
    $$CachedRidesTableTableCreateCompanionBuilder,
    $$CachedRidesTableTableUpdateCompanionBuilder,
    (
      CachedRide,
      BaseReferences<_$AppDatabase, $CachedRidesTableTable, CachedRide>
    ),
    CachedRide,
    PrefetchHooks Function()> {
  $$CachedRidesTableTableTableManager(
      _$AppDatabase db, $CachedRidesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedRidesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedRidesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedRidesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> passengerId = const Value.absent(),
            Value<String?> driverId = const Value.absent(),
            Value<String?> vehicleId = const Value.absent(),
            Value<double> pickupLat = const Value.absent(),
            Value<double> pickupLng = const Value.absent(),
            Value<String?> pickupAddress = const Value.absent(),
            Value<double> dropoffLat = const Value.absent(),
            Value<double> dropoffLng = const Value.absent(),
            Value<String?> dropoffAddress = const Value.absent(),
            Value<double> distanceKm = const Value.absent(),
            Value<int> estimatedDurationMin = const Value.absent(),
            Value<double> fareAmount = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<double> platformFee = const Value.absent(),
            Value<double> driverPayout = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> paymentStatus = const Value.absent(),
            Value<String?> paymentReference = const Value.absent(),
            Value<String?> blockchainLogHash = const Value.absent(),
            Value<int?> acceptedAt = const Value.absent(),
            Value<int?> startedAt = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<int?> cancelledAt = const Value.absent(),
            Value<String?> cancelReason = const Value.absent(),
            Value<EntitySyncStatus> syncStatus = const Value.absent(),
            Value<int> localUpdatedAt = const Value.absent(),
            Value<int> remoteUpdatedAt = const Value.absent(),
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedRidesTableCompanion(
            id: id,
            passengerId: passengerId,
            driverId: driverId,
            vehicleId: vehicleId,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            pickupAddress: pickupAddress,
            dropoffLat: dropoffLat,
            dropoffLng: dropoffLng,
            dropoffAddress: dropoffAddress,
            distanceKm: distanceKm,
            estimatedDurationMin: estimatedDurationMin,
            fareAmount: fareAmount,
            currency: currency,
            platformFee: platformFee,
            driverPayout: driverPayout,
            status: status,
            paymentStatus: paymentStatus,
            paymentReference: paymentReference,
            blockchainLogHash: blockchainLogHash,
            acceptedAt: acceptedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            cancelledAt: cancelledAt,
            cancelReason: cancelReason,
            syncStatus: syncStatus,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String passengerId,
            Value<String?> driverId = const Value.absent(),
            Value<String?> vehicleId = const Value.absent(),
            required double pickupLat,
            required double pickupLng,
            Value<String?> pickupAddress = const Value.absent(),
            required double dropoffLat,
            required double dropoffLng,
            Value<String?> dropoffAddress = const Value.absent(),
            required double distanceKm,
            required int estimatedDurationMin,
            required double fareAmount,
            Value<String> currency = const Value.absent(),
            required double platformFee,
            required double driverPayout,
            required String status,
            required String paymentStatus,
            Value<String?> paymentReference = const Value.absent(),
            Value<String?> blockchainLogHash = const Value.absent(),
            Value<int?> acceptedAt = const Value.absent(),
            Value<int?> startedAt = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<int?> cancelledAt = const Value.absent(),
            Value<String?> cancelReason = const Value.absent(),
            Value<EntitySyncStatus> syncStatus = const Value.absent(),
            required int localUpdatedAt,
            required int remoteUpdatedAt,
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedRidesTableCompanion.insert(
            id: id,
            passengerId: passengerId,
            driverId: driverId,
            vehicleId: vehicleId,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            pickupAddress: pickupAddress,
            dropoffLat: dropoffLat,
            dropoffLng: dropoffLng,
            dropoffAddress: dropoffAddress,
            distanceKm: distanceKm,
            estimatedDurationMin: estimatedDurationMin,
            fareAmount: fareAmount,
            currency: currency,
            platformFee: platformFee,
            driverPayout: driverPayout,
            status: status,
            paymentStatus: paymentStatus,
            paymentReference: paymentReference,
            blockchainLogHash: blockchainLogHash,
            acceptedAt: acceptedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            cancelledAt: cancelledAt,
            cancelReason: cancelReason,
            syncStatus: syncStatus,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedRidesTableTable, CachedRide>(table),
                    BaseReferences<_$AppDatabase, $CachedRidesTableTable,
                        CachedRide>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedRidesTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedRidesTableTable,
    CachedRide,
    $$CachedRidesTableTableFilterComposer,
    $$CachedRidesTableTableOrderingComposer,
    $$CachedRidesTableTableAnnotationComposer,
    $$CachedRidesTableTableCreateCompanionBuilder,
    $$CachedRidesTableTableUpdateCompanionBuilder,
    (
      CachedRide,
      BaseReferences<_$AppDatabase, $CachedRidesTableTable, CachedRide>
    ),
    CachedRide,
    PrefetchHooks Function()>;
typedef $$CachedWalletsTableTableCreateCompanionBuilder
    = CachedWalletsTableCompanion Function({
  required String id,
  required String userId,
  required double availableBalance,
  required double pendingBalance,
  required String currency,
  required int localUpdatedAt,
  required int remoteUpdatedAt,
  Value<int?> lastSyncedAt,
  Value<int> rowid,
});
typedef $$CachedWalletsTableTableUpdateCompanionBuilder
    = CachedWalletsTableCompanion Function({
  Value<String> id,
  Value<String> userId,
  Value<double> availableBalance,
  Value<double> pendingBalance,
  Value<String> currency,
  Value<int> localUpdatedAt,
  Value<int> remoteUpdatedAt,
  Value<int?> lastSyncedAt,
  Value<int> rowid,
});

class $$CachedWalletsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedWalletsTableTable> {
  $$CachedWalletsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get availableBalance => $composableBuilder(
      column: $table.availableBalance,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pendingBalance => $composableBuilder(
      column: $table.pendingBalance,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedWalletsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedWalletsTableTable> {
  $$CachedWalletsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get availableBalance => $composableBuilder(
      column: $table.availableBalance,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pendingBalance => $composableBuilder(
      column: $table.pendingBalance,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$CachedWalletsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedWalletsTableTable> {
  $$CachedWalletsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<double> get availableBalance => $composableBuilder(
      column: $table.availableBalance, builder: (column) => column);

  GeneratedColumn<double> get pendingBalance => $composableBuilder(
      column: $table.pendingBalance, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get localUpdatedAt => $composableBuilder(
      column: $table.localUpdatedAt, builder: (column) => column);

  GeneratedColumn<int> get remoteUpdatedAt => $composableBuilder(
      column: $table.remoteUpdatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$CachedWalletsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedWalletsTableTable,
    CachedWallet,
    $$CachedWalletsTableTableFilterComposer,
    $$CachedWalletsTableTableOrderingComposer,
    $$CachedWalletsTableTableAnnotationComposer,
    $$CachedWalletsTableTableCreateCompanionBuilder,
    $$CachedWalletsTableTableUpdateCompanionBuilder,
    (
      CachedWallet,
      BaseReferences<_$AppDatabase, $CachedWalletsTableTable, CachedWallet>
    ),
    CachedWallet,
    PrefetchHooks Function()> {
  $$CachedWalletsTableTableTableManager(
      _$AppDatabase db, $CachedWalletsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedWalletsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedWalletsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedWalletsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<double> availableBalance = const Value.absent(),
            Value<double> pendingBalance = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<int> localUpdatedAt = const Value.absent(),
            Value<int> remoteUpdatedAt = const Value.absent(),
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedWalletsTableCompanion(
            id: id,
            userId: userId,
            availableBalance: availableBalance,
            pendingBalance: pendingBalance,
            currency: currency,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String userId,
            required double availableBalance,
            required double pendingBalance,
            required String currency,
            required int localUpdatedAt,
            required int remoteUpdatedAt,
            Value<int?> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedWalletsTableCompanion.insert(
            id: id,
            userId: userId,
            availableBalance: availableBalance,
            pendingBalance: pendingBalance,
            currency: currency,
            localUpdatedAt: localUpdatedAt,
            remoteUpdatedAt: remoteUpdatedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedWalletsTableTable, CachedWallet>(table),
                    BaseReferences<_$AppDatabase, $CachedWalletsTableTable,
                        CachedWallet>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedWalletsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedWalletsTableTable,
    CachedWallet,
    $$CachedWalletsTableTableFilterComposer,
    $$CachedWalletsTableTableOrderingComposer,
    $$CachedWalletsTableTableAnnotationComposer,
    $$CachedWalletsTableTableCreateCompanionBuilder,
    $$CachedWalletsTableTableUpdateCompanionBuilder,
    (
      CachedWallet,
      BaseReferences<_$AppDatabase, $CachedWalletsTableTable, CachedWallet>
    ),
    CachedWallet,
    PrefetchHooks Function()>;
typedef $$CachedTransactionsTableTableCreateCompanionBuilder
    = CachedTransactionsTableCompanion Function({
  required String id,
  required String walletId,
  required String userId,
  required String type,
  required double amount,
  required String currency,
  Value<String?> referenceType,
  Value<String?> referenceId,
  required String status,
  Value<String?> description,
  Value<String?> blockchainTxHash,
  required int remoteCreatedAt,
  Value<int> rowid,
});
typedef $$CachedTransactionsTableTableUpdateCompanionBuilder
    = CachedTransactionsTableCompanion Function({
  Value<String> id,
  Value<String> walletId,
  Value<String> userId,
  Value<String> type,
  Value<double> amount,
  Value<String> currency,
  Value<String?> referenceType,
  Value<String?> referenceId,
  Value<String> status,
  Value<String?> description,
  Value<String?> blockchainTxHash,
  Value<int> remoteCreatedAt,
  Value<int> rowid,
});

class $$CachedTransactionsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTransactionsTableTable> {
  $$CachedTransactionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get walletId => $composableBuilder(
      column: $table.walletId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceType => $composableBuilder(
      column: $table.referenceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get blockchainTxHash => $composableBuilder(
      column: $table.blockchainTxHash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteCreatedAt => $composableBuilder(
      column: $table.remoteCreatedAt,
      builder: (column) => ColumnFilters(column));
}

class $$CachedTransactionsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTransactionsTableTable> {
  $$CachedTransactionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get walletId => $composableBuilder(
      column: $table.walletId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceType => $composableBuilder(
      column: $table.referenceType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get blockchainTxHash => $composableBuilder(
      column: $table.blockchainTxHash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteCreatedAt => $composableBuilder(
      column: $table.remoteCreatedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$CachedTransactionsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTransactionsTableTable> {
  $$CachedTransactionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get referenceType => $composableBuilder(
      column: $table.referenceType, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get blockchainTxHash => $composableBuilder(
      column: $table.blockchainTxHash, builder: (column) => column);

  GeneratedColumn<int> get remoteCreatedAt => $composableBuilder(
      column: $table.remoteCreatedAt, builder: (column) => column);
}

class $$CachedTransactionsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedTransactionsTableTable,
    CachedTransaction,
    $$CachedTransactionsTableTableFilterComposer,
    $$CachedTransactionsTableTableOrderingComposer,
    $$CachedTransactionsTableTableAnnotationComposer,
    $$CachedTransactionsTableTableCreateCompanionBuilder,
    $$CachedTransactionsTableTableUpdateCompanionBuilder,
    (
      CachedTransaction,
      BaseReferences<_$AppDatabase, $CachedTransactionsTableTable,
          CachedTransaction>
    ),
    CachedTransaction,
    PrefetchHooks Function()> {
  $$CachedTransactionsTableTableTableManager(
      _$AppDatabase db, $CachedTransactionsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTransactionsTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTransactionsTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTransactionsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> walletId = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String?> referenceType = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> blockchainTxHash = const Value.absent(),
            Value<int> remoteCreatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTransactionsTableCompanion(
            id: id,
            walletId: walletId,
            userId: userId,
            type: type,
            amount: amount,
            currency: currency,
            referenceType: referenceType,
            referenceId: referenceId,
            status: status,
            description: description,
            blockchainTxHash: blockchainTxHash,
            remoteCreatedAt: remoteCreatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String walletId,
            required String userId,
            required String type,
            required double amount,
            required String currency,
            Value<String?> referenceType = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            required String status,
            Value<String?> description = const Value.absent(),
            Value<String?> blockchainTxHash = const Value.absent(),
            required int remoteCreatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTransactionsTableCompanion.insert(
            id: id,
            walletId: walletId,
            userId: userId,
            type: type,
            amount: amount,
            currency: currency,
            referenceType: referenceType,
            referenceId: referenceId,
            status: status,
            description: description,
            blockchainTxHash: blockchainTxHash,
            remoteCreatedAt: remoteCreatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedTransactionsTableTable,
                        CachedTransaction>(table),
                    BaseReferences<_$AppDatabase, $CachedTransactionsTableTable,
                        CachedTransaction>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedTransactionsTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedTransactionsTableTable,
        CachedTransaction,
        $$CachedTransactionsTableTableFilterComposer,
        $$CachedTransactionsTableTableOrderingComposer,
        $$CachedTransactionsTableTableAnnotationComposer,
        $$CachedTransactionsTableTableCreateCompanionBuilder,
        $$CachedTransactionsTableTableUpdateCompanionBuilder,
        (
          CachedTransaction,
          BaseReferences<_$AppDatabase, $CachedTransactionsTableTable,
              CachedTransaction>
        ),
        CachedTransaction,
        PrefetchHooks Function()>;
typedef $$CachedUsersTableTableCreateCompanionBuilder
    = CachedUsersTableCompanion Function({
  required String id,
  required String name,
  required String email,
  required String phone,
  required String role,
  Value<bool> isVerified,
  Value<String?> avatarUrl,
  Value<String?> walletAddress,
  Value<String?> sessionToken,
  Value<bool> isActiveSession,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedUsersTableTableUpdateCompanionBuilder
    = CachedUsersTableCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> email,
  Value<String> phone,
  Value<String> role,
  Value<bool> isVerified,
  Value<String?> avatarUrl,
  Value<String?> walletAddress,
  Value<String?> sessionToken,
  Value<bool> isActiveSession,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedUsersTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedUsersTableTable> {
  $$CachedUsersTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatarUrl => $composableBuilder(
      column: $table.avatarUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get walletAddress => $composableBuilder(
      column: $table.walletAddress, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActiveSession => $composableBuilder(
      column: $table.isActiveSession,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedUsersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedUsersTableTable> {
  $$CachedUsersTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
      column: $table.avatarUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get walletAddress => $composableBuilder(
      column: $table.walletAddress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActiveSession => $composableBuilder(
      column: $table.isActiveSession,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedUsersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedUsersTableTable> {
  $$CachedUsersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get walletAddress => $composableBuilder(
      column: $table.walletAddress, builder: (column) => column);

  GeneratedColumn<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken, builder: (column) => column);

  GeneratedColumn<bool> get isActiveSession => $composableBuilder(
      column: $table.isActiveSession, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedUsersTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedUsersTableTable,
    CachedUser,
    $$CachedUsersTableTableFilterComposer,
    $$CachedUsersTableTableOrderingComposer,
    $$CachedUsersTableTableAnnotationComposer,
    $$CachedUsersTableTableCreateCompanionBuilder,
    $$CachedUsersTableTableUpdateCompanionBuilder,
    (
      CachedUser,
      BaseReferences<_$AppDatabase, $CachedUsersTableTable, CachedUser>
    ),
    CachedUser,
    PrefetchHooks Function()> {
  $$CachedUsersTableTableTableManager(
      _$AppDatabase db, $CachedUsersTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedUsersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedUsersTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedUsersTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> email = const Value.absent(),
            Value<String> phone = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<bool> isVerified = const Value.absent(),
            Value<String?> avatarUrl = const Value.absent(),
            Value<String?> walletAddress = const Value.absent(),
            Value<String?> sessionToken = const Value.absent(),
            Value<bool> isActiveSession = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedUsersTableCompanion(
            id: id,
            name: name,
            email: email,
            phone: phone,
            role: role,
            isVerified: isVerified,
            avatarUrl: avatarUrl,
            walletAddress: walletAddress,
            sessionToken: sessionToken,
            isActiveSession: isActiveSession,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String email,
            required String phone,
            required String role,
            Value<bool> isVerified = const Value.absent(),
            Value<String?> avatarUrl = const Value.absent(),
            Value<String?> walletAddress = const Value.absent(),
            Value<String?> sessionToken = const Value.absent(),
            Value<bool> isActiveSession = const Value.absent(),
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedUsersTableCompanion.insert(
            id: id,
            name: name,
            email: email,
            phone: phone,
            role: role,
            isVerified: isVerified,
            avatarUrl: avatarUrl,
            walletAddress: walletAddress,
            sessionToken: sessionToken,
            isActiveSession: isActiveSession,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedUsersTableTable, CachedUser>(table),
                    BaseReferences<_$AppDatabase, $CachedUsersTableTable,
                        CachedUser>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedUsersTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedUsersTableTable,
    CachedUser,
    $$CachedUsersTableTableFilterComposer,
    $$CachedUsersTableTableOrderingComposer,
    $$CachedUsersTableTableAnnotationComposer,
    $$CachedUsersTableTableCreateCompanionBuilder,
    $$CachedUsersTableTableUpdateCompanionBuilder,
    (
      CachedUser,
      BaseReferences<_$AppDatabase, $CachedUsersTableTable, CachedUser>
    ),
    CachedUser,
    PrefetchHooks Function()>;
typedef $$CachedPropertyListingsTableTableCreateCompanionBuilder
    = CachedPropertyListingsTableCompanion Function({
  required String id,
  required String ownerId,
  required String title,
  required String description,
  required String category,
  required double price,
  Value<double?> hourlyRate,
  required String address,
  required double latitude,
  required double longitude,
  Value<String?> primaryImageUrl,
  Value<bool> isSynced,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedPropertyListingsTableTableUpdateCompanionBuilder
    = CachedPropertyListingsTableCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String> title,
  Value<String> description,
  Value<String> category,
  Value<double> price,
  Value<double?> hourlyRate,
  Value<String> address,
  Value<double> latitude,
  Value<double> longitude,
  Value<String?> primaryImageUrl,
  Value<bool> isSynced,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedPropertyListingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPropertyListingsTableTable> {
  $$CachedPropertyListingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get hourlyRate => $composableBuilder(
      column: $table.hourlyRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get primaryImageUrl => $composableBuilder(
      column: $table.primaryImageUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedPropertyListingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPropertyListingsTableTable> {
  $$CachedPropertyListingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get hourlyRate => $composableBuilder(
      column: $table.hourlyRate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get primaryImageUrl => $composableBuilder(
      column: $table.primaryImageUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedPropertyListingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPropertyListingsTableTable> {
  $$CachedPropertyListingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get hourlyRate => $composableBuilder(
      column: $table.hourlyRate, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get primaryImageUrl => $composableBuilder(
      column: $table.primaryImageUrl, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedPropertyListingsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedPropertyListingsTableTable,
    CachedPropertyListing,
    $$CachedPropertyListingsTableTableFilterComposer,
    $$CachedPropertyListingsTableTableOrderingComposer,
    $$CachedPropertyListingsTableTableAnnotationComposer,
    $$CachedPropertyListingsTableTableCreateCompanionBuilder,
    $$CachedPropertyListingsTableTableUpdateCompanionBuilder,
    (
      CachedPropertyListing,
      BaseReferences<_$AppDatabase, $CachedPropertyListingsTableTable,
          CachedPropertyListing>
    ),
    CachedPropertyListing,
    PrefetchHooks Function()> {
  $$CachedPropertyListingsTableTableTableManager(
      _$AppDatabase db, $CachedPropertyListingsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPropertyListingsTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPropertyListingsTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPropertyListingsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<double?> hourlyRate = const Value.absent(),
            Value<String> address = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<String?> primaryImageUrl = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPropertyListingsTableCompanion(
            id: id,
            ownerId: ownerId,
            title: title,
            description: description,
            category: category,
            price: price,
            hourlyRate: hourlyRate,
            address: address,
            latitude: latitude,
            longitude: longitude,
            primaryImageUrl: primaryImageUrl,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String ownerId,
            required String title,
            required String description,
            required String category,
            required double price,
            Value<double?> hourlyRate = const Value.absent(),
            required String address,
            required double latitude,
            required double longitude,
            Value<String?> primaryImageUrl = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPropertyListingsTableCompanion.insert(
            id: id,
            ownerId: ownerId,
            title: title,
            description: description,
            category: category,
            price: price,
            hourlyRate: hourlyRate,
            address: address,
            latitude: latitude,
            longitude: longitude,
            primaryImageUrl: primaryImageUrl,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedPropertyListingsTableTable,
                        CachedPropertyListing>(table),
                    BaseReferences<
                        _$AppDatabase,
                        $CachedPropertyListingsTableTable,
                        CachedPropertyListing>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedPropertyListingsTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedPropertyListingsTableTable,
        CachedPropertyListing,
        $$CachedPropertyListingsTableTableFilterComposer,
        $$CachedPropertyListingsTableTableOrderingComposer,
        $$CachedPropertyListingsTableTableAnnotationComposer,
        $$CachedPropertyListingsTableTableCreateCompanionBuilder,
        $$CachedPropertyListingsTableTableUpdateCompanionBuilder,
        (
          CachedPropertyListing,
          BaseReferences<_$AppDatabase, $CachedPropertyListingsTableTable,
              CachedPropertyListing>
        ),
        CachedPropertyListing,
        PrefetchHooks Function()>;
typedef $$CachedVehicleListingsTableTableCreateCompanionBuilder
    = CachedVehicleListingsTableCompanion Function({
  required String id,
  required String ownerId,
  required String vehicleType,
  required String listingIntent,
  required String make,
  required String model,
  required int year,
  Value<double?> pricePerKm,
  Value<double?> pricePerDay,
  Value<double?> salePrice,
  Value<String?> primaryImageUrl,
  Value<bool> isSynced,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedVehicleListingsTableTableUpdateCompanionBuilder
    = CachedVehicleListingsTableCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String> vehicleType,
  Value<String> listingIntent,
  Value<String> make,
  Value<String> model,
  Value<int> year,
  Value<double?> pricePerKm,
  Value<double?> pricePerDay,
  Value<double?> salePrice,
  Value<String?> primaryImageUrl,
  Value<bool> isSynced,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedVehicleListingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedVehicleListingsTableTable> {
  $$CachedVehicleListingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get vehicleType => $composableBuilder(
      column: $table.vehicleType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get listingIntent => $composableBuilder(
      column: $table.listingIntent, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get make => $composableBuilder(
      column: $table.make, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pricePerKm => $composableBuilder(
      column: $table.pricePerKm, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pricePerDay => $composableBuilder(
      column: $table.pricePerDay, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get salePrice => $composableBuilder(
      column: $table.salePrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get primaryImageUrl => $composableBuilder(
      column: $table.primaryImageUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedVehicleListingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedVehicleListingsTableTable> {
  $$CachedVehicleListingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get vehicleType => $composableBuilder(
      column: $table.vehicleType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get listingIntent => $composableBuilder(
      column: $table.listingIntent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get make => $composableBuilder(
      column: $table.make, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pricePerKm => $composableBuilder(
      column: $table.pricePerKm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pricePerDay => $composableBuilder(
      column: $table.pricePerDay, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get salePrice => $composableBuilder(
      column: $table.salePrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get primaryImageUrl => $composableBuilder(
      column: $table.primaryImageUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedVehicleListingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedVehicleListingsTableTable> {
  $$CachedVehicleListingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get vehicleType => $composableBuilder(
      column: $table.vehicleType, builder: (column) => column);

  GeneratedColumn<String> get listingIntent => $composableBuilder(
      column: $table.listingIntent, builder: (column) => column);

  GeneratedColumn<String> get make =>
      $composableBuilder(column: $table.make, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<double> get pricePerKm => $composableBuilder(
      column: $table.pricePerKm, builder: (column) => column);

  GeneratedColumn<double> get pricePerDay => $composableBuilder(
      column: $table.pricePerDay, builder: (column) => column);

  GeneratedColumn<double> get salePrice =>
      $composableBuilder(column: $table.salePrice, builder: (column) => column);

  GeneratedColumn<String> get primaryImageUrl => $composableBuilder(
      column: $table.primaryImageUrl, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedVehicleListingsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedVehicleListingsTableTable,
    CachedVehicleListing,
    $$CachedVehicleListingsTableTableFilterComposer,
    $$CachedVehicleListingsTableTableOrderingComposer,
    $$CachedVehicleListingsTableTableAnnotationComposer,
    $$CachedVehicleListingsTableTableCreateCompanionBuilder,
    $$CachedVehicleListingsTableTableUpdateCompanionBuilder,
    (
      CachedVehicleListing,
      BaseReferences<_$AppDatabase, $CachedVehicleListingsTableTable,
          CachedVehicleListing>
    ),
    CachedVehicleListing,
    PrefetchHooks Function()> {
  $$CachedVehicleListingsTableTableTableManager(
      _$AppDatabase db, $CachedVehicleListingsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedVehicleListingsTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedVehicleListingsTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedVehicleListingsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<String> vehicleType = const Value.absent(),
            Value<String> listingIntent = const Value.absent(),
            Value<String> make = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<int> year = const Value.absent(),
            Value<double?> pricePerKm = const Value.absent(),
            Value<double?> pricePerDay = const Value.absent(),
            Value<double?> salePrice = const Value.absent(),
            Value<String?> primaryImageUrl = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedVehicleListingsTableCompanion(
            id: id,
            ownerId: ownerId,
            vehicleType: vehicleType,
            listingIntent: listingIntent,
            make: make,
            model: model,
            year: year,
            pricePerKm: pricePerKm,
            pricePerDay: pricePerDay,
            salePrice: salePrice,
            primaryImageUrl: primaryImageUrl,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String ownerId,
            required String vehicleType,
            required String listingIntent,
            required String make,
            required String model,
            required int year,
            Value<double?> pricePerKm = const Value.absent(),
            Value<double?> pricePerDay = const Value.absent(),
            Value<double?> salePrice = const Value.absent(),
            Value<String?> primaryImageUrl = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedVehicleListingsTableCompanion.insert(
            id: id,
            ownerId: ownerId,
            vehicleType: vehicleType,
            listingIntent: listingIntent,
            make: make,
            model: model,
            year: year,
            pricePerKm: pricePerKm,
            pricePerDay: pricePerDay,
            salePrice: salePrice,
            primaryImageUrl: primaryImageUrl,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedVehicleListingsTableTable,
                        CachedVehicleListing>(table),
                    BaseReferences<
                        _$AppDatabase,
                        $CachedVehicleListingsTableTable,
                        CachedVehicleListing>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedVehicleListingsTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedVehicleListingsTableTable,
        CachedVehicleListing,
        $$CachedVehicleListingsTableTableFilterComposer,
        $$CachedVehicleListingsTableTableOrderingComposer,
        $$CachedVehicleListingsTableTableAnnotationComposer,
        $$CachedVehicleListingsTableTableCreateCompanionBuilder,
        $$CachedVehicleListingsTableTableUpdateCompanionBuilder,
        (
          CachedVehicleListing,
          BaseReferences<_$AppDatabase, $CachedVehicleListingsTableTable,
              CachedVehicleListing>
        ),
        CachedVehicleListing,
        PrefetchHooks Function()>;
typedef $$CachedBookingsTableTableCreateCompanionBuilder
    = CachedBookingsTableCompanion Function({
  required String id,
  required String listingId,
  Value<String> listingTitle,
  required String buyerId,
  required String vendorId,
  required String bookingType,
  required int startTime,
  required int endTime,
  required double totalAmount,
  Value<String> currency,
  required String paymentStatus,
  Value<String> bookingStatus,
  Value<bool> isSynced,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedBookingsTableTableUpdateCompanionBuilder
    = CachedBookingsTableCompanion Function({
  Value<String> id,
  Value<String> listingId,
  Value<String> listingTitle,
  Value<String> buyerId,
  Value<String> vendorId,
  Value<String> bookingType,
  Value<int> startTime,
  Value<int> endTime,
  Value<double> totalAmount,
  Value<String> currency,
  Value<String> paymentStatus,
  Value<String> bookingStatus,
  Value<bool> isSynced,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedBookingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedBookingsTableTable> {
  $$CachedBookingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get listingId => $composableBuilder(
      column: $table.listingId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get listingTitle => $composableBuilder(
      column: $table.listingTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get buyerId => $composableBuilder(
      column: $table.buyerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get vendorId => $composableBuilder(
      column: $table.vendorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bookingType => $composableBuilder(
      column: $table.bookingType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentStatus => $composableBuilder(
      column: $table.paymentStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bookingStatus => $composableBuilder(
      column: $table.bookingStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedBookingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedBookingsTableTable> {
  $$CachedBookingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get listingId => $composableBuilder(
      column: $table.listingId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get listingTitle => $composableBuilder(
      column: $table.listingTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get buyerId => $composableBuilder(
      column: $table.buyerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get vendorId => $composableBuilder(
      column: $table.vendorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bookingType => $composableBuilder(
      column: $table.bookingType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentStatus => $composableBuilder(
      column: $table.paymentStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bookingStatus => $composableBuilder(
      column: $table.bookingStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedBookingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedBookingsTableTable> {
  $$CachedBookingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get listingId =>
      $composableBuilder(column: $table.listingId, builder: (column) => column);

  GeneratedColumn<String> get listingTitle => $composableBuilder(
      column: $table.listingTitle, builder: (column) => column);

  GeneratedColumn<String> get buyerId =>
      $composableBuilder(column: $table.buyerId, builder: (column) => column);

  GeneratedColumn<String> get vendorId =>
      $composableBuilder(column: $table.vendorId, builder: (column) => column);

  GeneratedColumn<String> get bookingType => $composableBuilder(
      column: $table.bookingType, builder: (column) => column);

  GeneratedColumn<int> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<int> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<double> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get paymentStatus => $composableBuilder(
      column: $table.paymentStatus, builder: (column) => column);

  GeneratedColumn<String> get bookingStatus => $composableBuilder(
      column: $table.bookingStatus, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedBookingsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedBookingsTableTable,
    CachedBooking,
    $$CachedBookingsTableTableFilterComposer,
    $$CachedBookingsTableTableOrderingComposer,
    $$CachedBookingsTableTableAnnotationComposer,
    $$CachedBookingsTableTableCreateCompanionBuilder,
    $$CachedBookingsTableTableUpdateCompanionBuilder,
    (
      CachedBooking,
      BaseReferences<_$AppDatabase, $CachedBookingsTableTable, CachedBooking>
    ),
    CachedBooking,
    PrefetchHooks Function()> {
  $$CachedBookingsTableTableTableManager(
      _$AppDatabase db, $CachedBookingsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedBookingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedBookingsTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedBookingsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> listingId = const Value.absent(),
            Value<String> listingTitle = const Value.absent(),
            Value<String> buyerId = const Value.absent(),
            Value<String> vendorId = const Value.absent(),
            Value<String> bookingType = const Value.absent(),
            Value<int> startTime = const Value.absent(),
            Value<int> endTime = const Value.absent(),
            Value<double> totalAmount = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String> paymentStatus = const Value.absent(),
            Value<String> bookingStatus = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedBookingsTableCompanion(
            id: id,
            listingId: listingId,
            listingTitle: listingTitle,
            buyerId: buyerId,
            vendorId: vendorId,
            bookingType: bookingType,
            startTime: startTime,
            endTime: endTime,
            totalAmount: totalAmount,
            currency: currency,
            paymentStatus: paymentStatus,
            bookingStatus: bookingStatus,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String listingId,
            Value<String> listingTitle = const Value.absent(),
            required String buyerId,
            required String vendorId,
            required String bookingType,
            required int startTime,
            required int endTime,
            required double totalAmount,
            Value<String> currency = const Value.absent(),
            required String paymentStatus,
            Value<String> bookingStatus = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedBookingsTableCompanion.insert(
            id: id,
            listingId: listingId,
            listingTitle: listingTitle,
            buyerId: buyerId,
            vendorId: vendorId,
            bookingType: bookingType,
            startTime: startTime,
            endTime: endTime,
            totalAmount: totalAmount,
            currency: currency,
            paymentStatus: paymentStatus,
            bookingStatus: bookingStatus,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedBookingsTableTable, CachedBooking>(
                        table),
                    BaseReferences<_$AppDatabase, $CachedBookingsTableTable,
                        CachedBooking>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedBookingsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedBookingsTableTable,
    CachedBooking,
    $$CachedBookingsTableTableFilterComposer,
    $$CachedBookingsTableTableOrderingComposer,
    $$CachedBookingsTableTableAnnotationComposer,
    $$CachedBookingsTableTableCreateCompanionBuilder,
    $$CachedBookingsTableTableUpdateCompanionBuilder,
    (
      CachedBooking,
      BaseReferences<_$AppDatabase, $CachedBookingsTableTable, CachedBooking>
    ),
    CachedBooking,
    PrefetchHooks Function()>;
typedef $$CachedDriverProfilesTableTableCreateCompanionBuilder
    = CachedDriverProfilesTableCompanion Function({
  required String id,
  required String userId,
  Value<bool> isOnline,
  Value<bool> isAvailable,
  required String serviceType,
  required double currentLat,
  required double currentLng,
  required String currentGeohash,
  required int lastLocationUpdate,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedDriverProfilesTableTableUpdateCompanionBuilder
    = CachedDriverProfilesTableCompanion Function({
  Value<String> id,
  Value<String> userId,
  Value<bool> isOnline,
  Value<bool> isAvailable,
  Value<String> serviceType,
  Value<double> currentLat,
  Value<double> currentLng,
  Value<String> currentGeohash,
  Value<int> lastLocationUpdate,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedDriverProfilesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedDriverProfilesTableTable> {
  $$CachedDriverProfilesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isOnline => $composableBuilder(
      column: $table.isOnline, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAvailable => $composableBuilder(
      column: $table.isAvailable, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serviceType => $composableBuilder(
      column: $table.serviceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get currentLat => $composableBuilder(
      column: $table.currentLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get currentLng => $composableBuilder(
      column: $table.currentLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currentGeohash => $composableBuilder(
      column: $table.currentGeohash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastLocationUpdate => $composableBuilder(
      column: $table.lastLocationUpdate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedDriverProfilesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedDriverProfilesTableTable> {
  $$CachedDriverProfilesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isOnline => $composableBuilder(
      column: $table.isOnline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAvailable => $composableBuilder(
      column: $table.isAvailable, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serviceType => $composableBuilder(
      column: $table.serviceType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get currentLat => $composableBuilder(
      column: $table.currentLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get currentLng => $composableBuilder(
      column: $table.currentLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currentGeohash => $composableBuilder(
      column: $table.currentGeohash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastLocationUpdate => $composableBuilder(
      column: $table.lastLocationUpdate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedDriverProfilesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedDriverProfilesTableTable> {
  $$CachedDriverProfilesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<bool> get isOnline =>
      $composableBuilder(column: $table.isOnline, builder: (column) => column);

  GeneratedColumn<bool> get isAvailable => $composableBuilder(
      column: $table.isAvailable, builder: (column) => column);

  GeneratedColumn<String> get serviceType => $composableBuilder(
      column: $table.serviceType, builder: (column) => column);

  GeneratedColumn<double> get currentLat => $composableBuilder(
      column: $table.currentLat, builder: (column) => column);

  GeneratedColumn<double> get currentLng => $composableBuilder(
      column: $table.currentLng, builder: (column) => column);

  GeneratedColumn<String> get currentGeohash => $composableBuilder(
      column: $table.currentGeohash, builder: (column) => column);

  GeneratedColumn<int> get lastLocationUpdate => $composableBuilder(
      column: $table.lastLocationUpdate, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedDriverProfilesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedDriverProfilesTableTable,
    CachedDriverProfile,
    $$CachedDriverProfilesTableTableFilterComposer,
    $$CachedDriverProfilesTableTableOrderingComposer,
    $$CachedDriverProfilesTableTableAnnotationComposer,
    $$CachedDriverProfilesTableTableCreateCompanionBuilder,
    $$CachedDriverProfilesTableTableUpdateCompanionBuilder,
    (
      CachedDriverProfile,
      BaseReferences<_$AppDatabase, $CachedDriverProfilesTableTable,
          CachedDriverProfile>
    ),
    CachedDriverProfile,
    PrefetchHooks Function()> {
  $$CachedDriverProfilesTableTableTableManager(
      _$AppDatabase db, $CachedDriverProfilesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDriverProfilesTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDriverProfilesTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDriverProfilesTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<bool> isOnline = const Value.absent(),
            Value<bool> isAvailable = const Value.absent(),
            Value<String> serviceType = const Value.absent(),
            Value<double> currentLat = const Value.absent(),
            Value<double> currentLng = const Value.absent(),
            Value<String> currentGeohash = const Value.absent(),
            Value<int> lastLocationUpdate = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedDriverProfilesTableCompanion(
            id: id,
            userId: userId,
            isOnline: isOnline,
            isAvailable: isAvailable,
            serviceType: serviceType,
            currentLat: currentLat,
            currentLng: currentLng,
            currentGeohash: currentGeohash,
            lastLocationUpdate: lastLocationUpdate,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String userId,
            Value<bool> isOnline = const Value.absent(),
            Value<bool> isAvailable = const Value.absent(),
            required String serviceType,
            required double currentLat,
            required double currentLng,
            required String currentGeohash,
            required int lastLocationUpdate,
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedDriverProfilesTableCompanion.insert(
            id: id,
            userId: userId,
            isOnline: isOnline,
            isAvailable: isAvailable,
            serviceType: serviceType,
            currentLat: currentLat,
            currentLng: currentLng,
            currentGeohash: currentGeohash,
            lastLocationUpdate: lastLocationUpdate,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedDriverProfilesTableTable,
                        CachedDriverProfile>(table),
                    BaseReferences<
                        _$AppDatabase,
                        $CachedDriverProfilesTableTable,
                        CachedDriverProfile>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedDriverProfilesTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedDriverProfilesTableTable,
        CachedDriverProfile,
        $$CachedDriverProfilesTableTableFilterComposer,
        $$CachedDriverProfilesTableTableOrderingComposer,
        $$CachedDriverProfilesTableTableAnnotationComposer,
        $$CachedDriverProfilesTableTableCreateCompanionBuilder,
        $$CachedDriverProfilesTableTableUpdateCompanionBuilder,
        (
          CachedDriverProfile,
          BaseReferences<_$AppDatabase, $CachedDriverProfilesTableTable,
              CachedDriverProfile>
        ),
        CachedDriverProfile,
        PrefetchHooks Function()>;
typedef $$CachedDriverVehiclesTableTableCreateCompanionBuilder
    = CachedDriverVehiclesTableCompanion Function({
  required String id,
  required String driverId,
  required String make,
  required String model,
  required int year,
  required String color,
  required String licensePlate,
  required String category,
  Value<bool> isVerified,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedDriverVehiclesTableTableUpdateCompanionBuilder
    = CachedDriverVehiclesTableCompanion Function({
  Value<String> id,
  Value<String> driverId,
  Value<String> make,
  Value<String> model,
  Value<int> year,
  Value<String> color,
  Value<String> licensePlate,
  Value<String> category,
  Value<bool> isVerified,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedDriverVehiclesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedDriverVehiclesTableTable> {
  $$CachedDriverVehiclesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driverId => $composableBuilder(
      column: $table.driverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get make => $composableBuilder(
      column: $table.make, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get licensePlate => $composableBuilder(
      column: $table.licensePlate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedDriverVehiclesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedDriverVehiclesTableTable> {
  $$CachedDriverVehiclesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driverId => $composableBuilder(
      column: $table.driverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get make => $composableBuilder(
      column: $table.make, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get year => $composableBuilder(
      column: $table.year, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get color => $composableBuilder(
      column: $table.color, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get licensePlate => $composableBuilder(
      column: $table.licensePlate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedDriverVehiclesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedDriverVehiclesTableTable> {
  $$CachedDriverVehiclesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get driverId =>
      $composableBuilder(column: $table.driverId, builder: (column) => column);

  GeneratedColumn<String> get make =>
      $composableBuilder(column: $table.make, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get licensePlate => $composableBuilder(
      column: $table.licensePlate, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedDriverVehiclesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedDriverVehiclesTableTable,
    CachedDriverVehicle,
    $$CachedDriverVehiclesTableTableFilterComposer,
    $$CachedDriverVehiclesTableTableOrderingComposer,
    $$CachedDriverVehiclesTableTableAnnotationComposer,
    $$CachedDriverVehiclesTableTableCreateCompanionBuilder,
    $$CachedDriverVehiclesTableTableUpdateCompanionBuilder,
    (
      CachedDriverVehicle,
      BaseReferences<_$AppDatabase, $CachedDriverVehiclesTableTable,
          CachedDriverVehicle>
    ),
    CachedDriverVehicle,
    PrefetchHooks Function()> {
  $$CachedDriverVehiclesTableTableTableManager(
      _$AppDatabase db, $CachedDriverVehiclesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDriverVehiclesTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDriverVehiclesTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDriverVehiclesTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> driverId = const Value.absent(),
            Value<String> make = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<int> year = const Value.absent(),
            Value<String> color = const Value.absent(),
            Value<String> licensePlate = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<bool> isVerified = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedDriverVehiclesTableCompanion(
            id: id,
            driverId: driverId,
            make: make,
            model: model,
            year: year,
            color: color,
            licensePlate: licensePlate,
            category: category,
            isVerified: isVerified,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String driverId,
            required String make,
            required String model,
            required int year,
            required String color,
            required String licensePlate,
            required String category,
            Value<bool> isVerified = const Value.absent(),
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedDriverVehiclesTableCompanion.insert(
            id: id,
            driverId: driverId,
            make: make,
            model: model,
            year: year,
            color: color,
            licensePlate: licensePlate,
            category: category,
            isVerified: isVerified,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedDriverVehiclesTableTable,
                        CachedDriverVehicle>(table),
                    BaseReferences<
                        _$AppDatabase,
                        $CachedDriverVehiclesTableTable,
                        CachedDriverVehicle>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedDriverVehiclesTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedDriverVehiclesTableTable,
        CachedDriverVehicle,
        $$CachedDriverVehiclesTableTableFilterComposer,
        $$CachedDriverVehiclesTableTableOrderingComposer,
        $$CachedDriverVehiclesTableTableAnnotationComposer,
        $$CachedDriverVehiclesTableTableCreateCompanionBuilder,
        $$CachedDriverVehiclesTableTableUpdateCompanionBuilder,
        (
          CachedDriverVehicle,
          BaseReferences<_$AppDatabase, $CachedDriverVehiclesTableTable,
              CachedDriverVehicle>
        ),
        CachedDriverVehicle,
        PrefetchHooks Function()>;
typedef $$CachedTripsDeliveriesTableTableCreateCompanionBuilder
    = CachedTripsDeliveriesTableCompanion Function({
  required String id,
  required String passengerId,
  Value<String?> driverId,
  Value<String?> vehicleId,
  required String serviceType,
  required double pickupLat,
  required double pickupLng,
  required String pickupAddressText,
  required String pickupGeohash,
  required double dropoffLat,
  required double dropoffLng,
  required String dropoffAddressText,
  required String status,
  required double fareAmount,
  Value<String> currency,
  required String paymentMethod,
  required double distanceKm,
  required int durationMins,
  Value<String?> deliveryPackageJson,
  Value<bool> isSynced,
  required int cachedAt,
  Value<int> rowid,
});
typedef $$CachedTripsDeliveriesTableTableUpdateCompanionBuilder
    = CachedTripsDeliveriesTableCompanion Function({
  Value<String> id,
  Value<String> passengerId,
  Value<String?> driverId,
  Value<String?> vehicleId,
  Value<String> serviceType,
  Value<double> pickupLat,
  Value<double> pickupLng,
  Value<String> pickupAddressText,
  Value<String> pickupGeohash,
  Value<double> dropoffLat,
  Value<double> dropoffLng,
  Value<String> dropoffAddressText,
  Value<String> status,
  Value<double> fareAmount,
  Value<String> currency,
  Value<String> paymentMethod,
  Value<double> distanceKm,
  Value<int> durationMins,
  Value<String?> deliveryPackageJson,
  Value<bool> isSynced,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$CachedTripsDeliveriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTripsDeliveriesTableTable> {
  $$CachedTripsDeliveriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get passengerId => $composableBuilder(
      column: $table.passengerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driverId => $composableBuilder(
      column: $table.driverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get vehicleId => $composableBuilder(
      column: $table.vehicleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serviceType => $composableBuilder(
      column: $table.serviceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pickupLat => $composableBuilder(
      column: $table.pickupLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pickupLng => $composableBuilder(
      column: $table.pickupLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pickupAddressText => $composableBuilder(
      column: $table.pickupAddressText,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pickupGeohash => $composableBuilder(
      column: $table.pickupGeohash, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get dropoffLat => $composableBuilder(
      column: $table.dropoffLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get dropoffLng => $composableBuilder(
      column: $table.dropoffLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dropoffAddressText => $composableBuilder(
      column: $table.dropoffAddressText,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get fareAmount => $composableBuilder(
      column: $table.fareAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get distanceKm => $composableBuilder(
      column: $table.distanceKm, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMins => $composableBuilder(
      column: $table.durationMins, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deliveryPackageJson => $composableBuilder(
      column: $table.deliveryPackageJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedTripsDeliveriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTripsDeliveriesTableTable> {
  $$CachedTripsDeliveriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get passengerId => $composableBuilder(
      column: $table.passengerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driverId => $composableBuilder(
      column: $table.driverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get vehicleId => $composableBuilder(
      column: $table.vehicleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serviceType => $composableBuilder(
      column: $table.serviceType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pickupLat => $composableBuilder(
      column: $table.pickupLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pickupLng => $composableBuilder(
      column: $table.pickupLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pickupAddressText => $composableBuilder(
      column: $table.pickupAddressText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pickupGeohash => $composableBuilder(
      column: $table.pickupGeohash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get dropoffLat => $composableBuilder(
      column: $table.dropoffLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get dropoffLng => $composableBuilder(
      column: $table.dropoffLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dropoffAddressText => $composableBuilder(
      column: $table.dropoffAddressText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get fareAmount => $composableBuilder(
      column: $table.fareAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get distanceKm => $composableBuilder(
      column: $table.distanceKm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMins => $composableBuilder(
      column: $table.durationMins,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deliveryPackageJson => $composableBuilder(
      column: $table.deliveryPackageJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedTripsDeliveriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTripsDeliveriesTableTable> {
  $$CachedTripsDeliveriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get passengerId => $composableBuilder(
      column: $table.passengerId, builder: (column) => column);

  GeneratedColumn<String> get driverId =>
      $composableBuilder(column: $table.driverId, builder: (column) => column);

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<String> get serviceType => $composableBuilder(
      column: $table.serviceType, builder: (column) => column);

  GeneratedColumn<double> get pickupLat =>
      $composableBuilder(column: $table.pickupLat, builder: (column) => column);

  GeneratedColumn<double> get pickupLng =>
      $composableBuilder(column: $table.pickupLng, builder: (column) => column);

  GeneratedColumn<String> get pickupAddressText => $composableBuilder(
      column: $table.pickupAddressText, builder: (column) => column);

  GeneratedColumn<String> get pickupGeohash => $composableBuilder(
      column: $table.pickupGeohash, builder: (column) => column);

  GeneratedColumn<double> get dropoffLat => $composableBuilder(
      column: $table.dropoffLat, builder: (column) => column);

  GeneratedColumn<double> get dropoffLng => $composableBuilder(
      column: $table.dropoffLng, builder: (column) => column);

  GeneratedColumn<String> get dropoffAddressText => $composableBuilder(
      column: $table.dropoffAddressText, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get fareAmount => $composableBuilder(
      column: $table.fareAmount, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => column);

  GeneratedColumn<double> get distanceKm => $composableBuilder(
      column: $table.distanceKm, builder: (column) => column);

  GeneratedColumn<int> get durationMins => $composableBuilder(
      column: $table.durationMins, builder: (column) => column);

  GeneratedColumn<String> get deliveryPackageJson => $composableBuilder(
      column: $table.deliveryPackageJson, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedTripsDeliveriesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedTripsDeliveriesTableTable,
    CachedTripDelivery,
    $$CachedTripsDeliveriesTableTableFilterComposer,
    $$CachedTripsDeliveriesTableTableOrderingComposer,
    $$CachedTripsDeliveriesTableTableAnnotationComposer,
    $$CachedTripsDeliveriesTableTableCreateCompanionBuilder,
    $$CachedTripsDeliveriesTableTableUpdateCompanionBuilder,
    (
      CachedTripDelivery,
      BaseReferences<_$AppDatabase, $CachedTripsDeliveriesTableTable,
          CachedTripDelivery>
    ),
    CachedTripDelivery,
    PrefetchHooks Function()> {
  $$CachedTripsDeliveriesTableTableTableManager(
      _$AppDatabase db, $CachedTripsDeliveriesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTripsDeliveriesTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTripsDeliveriesTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTripsDeliveriesTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> passengerId = const Value.absent(),
            Value<String?> driverId = const Value.absent(),
            Value<String?> vehicleId = const Value.absent(),
            Value<String> serviceType = const Value.absent(),
            Value<double> pickupLat = const Value.absent(),
            Value<double> pickupLng = const Value.absent(),
            Value<String> pickupAddressText = const Value.absent(),
            Value<String> pickupGeohash = const Value.absent(),
            Value<double> dropoffLat = const Value.absent(),
            Value<double> dropoffLng = const Value.absent(),
            Value<String> dropoffAddressText = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<double> fareAmount = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<double> distanceKm = const Value.absent(),
            Value<int> durationMins = const Value.absent(),
            Value<String?> deliveryPackageJson = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTripsDeliveriesTableCompanion(
            id: id,
            passengerId: passengerId,
            driverId: driverId,
            vehicleId: vehicleId,
            serviceType: serviceType,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            pickupAddressText: pickupAddressText,
            pickupGeohash: pickupGeohash,
            dropoffLat: dropoffLat,
            dropoffLng: dropoffLng,
            dropoffAddressText: dropoffAddressText,
            status: status,
            fareAmount: fareAmount,
            currency: currency,
            paymentMethod: paymentMethod,
            distanceKm: distanceKm,
            durationMins: durationMins,
            deliveryPackageJson: deliveryPackageJson,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String passengerId,
            Value<String?> driverId = const Value.absent(),
            Value<String?> vehicleId = const Value.absent(),
            required String serviceType,
            required double pickupLat,
            required double pickupLng,
            required String pickupAddressText,
            required String pickupGeohash,
            required double dropoffLat,
            required double dropoffLng,
            required String dropoffAddressText,
            required String status,
            required double fareAmount,
            Value<String> currency = const Value.absent(),
            required String paymentMethod,
            required double distanceKm,
            required int durationMins,
            Value<String?> deliveryPackageJson = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            required int cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedTripsDeliveriesTableCompanion.insert(
            id: id,
            passengerId: passengerId,
            driverId: driverId,
            vehicleId: vehicleId,
            serviceType: serviceType,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            pickupAddressText: pickupAddressText,
            pickupGeohash: pickupGeohash,
            dropoffLat: dropoffLat,
            dropoffLng: dropoffLng,
            dropoffAddressText: dropoffAddressText,
            status: status,
            fareAmount: fareAmount,
            currency: currency,
            paymentMethod: paymentMethod,
            distanceKm: distanceKm,
            durationMins: durationMins,
            deliveryPackageJson: deliveryPackageJson,
            isSynced: isSynced,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CachedTripsDeliveriesTableTable,
                        CachedTripDelivery>(table),
                    BaseReferences<
                        _$AppDatabase,
                        $CachedTripsDeliveriesTableTable,
                        CachedTripDelivery>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedTripsDeliveriesTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $CachedTripsDeliveriesTableTable,
        CachedTripDelivery,
        $$CachedTripsDeliveriesTableTableFilterComposer,
        $$CachedTripsDeliveriesTableTableOrderingComposer,
        $$CachedTripsDeliveriesTableTableAnnotationComposer,
        $$CachedTripsDeliveriesTableTableCreateCompanionBuilder,
        $$CachedTripsDeliveriesTableTableUpdateCompanionBuilder,
        (
          CachedTripDelivery,
          BaseReferences<_$AppDatabase, $CachedTripsDeliveriesTableTable,
              CachedTripDelivery>
        ),
        CachedTripDelivery,
        PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SyncQueueTableTableTableManager get syncQueueTable =>
      $$SyncQueueTableTableTableManager(_db, _db.syncQueueTable);
  $$CachedPropertiesTableTableTableManager get cachedPropertiesTable =>
      $$CachedPropertiesTableTableTableManager(_db, _db.cachedPropertiesTable);
  $$CachedRidesTableTableTableManager get cachedRidesTable =>
      $$CachedRidesTableTableTableManager(_db, _db.cachedRidesTable);
  $$CachedWalletsTableTableTableManager get cachedWalletsTable =>
      $$CachedWalletsTableTableTableManager(_db, _db.cachedWalletsTable);
  $$CachedTransactionsTableTableTableManager get cachedTransactionsTable =>
      $$CachedTransactionsTableTableTableManager(
          _db, _db.cachedTransactionsTable);
  $$CachedUsersTableTableTableManager get cachedUsersTable =>
      $$CachedUsersTableTableTableManager(_db, _db.cachedUsersTable);
  $$CachedPropertyListingsTableTableTableManager
      get cachedPropertyListingsTable =>
          $$CachedPropertyListingsTableTableTableManager(
              _db, _db.cachedPropertyListingsTable);
  $$CachedVehicleListingsTableTableTableManager
      get cachedVehicleListingsTable =>
          $$CachedVehicleListingsTableTableTableManager(
              _db, _db.cachedVehicleListingsTable);
  $$CachedBookingsTableTableTableManager get cachedBookingsTable =>
      $$CachedBookingsTableTableTableManager(_db, _db.cachedBookingsTable);
  $$CachedDriverProfilesTableTableTableManager get cachedDriverProfilesTable =>
      $$CachedDriverProfilesTableTableTableManager(
          _db, _db.cachedDriverProfilesTable);
  $$CachedDriverVehiclesTableTableTableManager get cachedDriverVehiclesTable =>
      $$CachedDriverVehiclesTableTableTableManager(
          _db, _db.cachedDriverVehiclesTable);
  $$CachedTripsDeliveriesTableTableTableManager
      get cachedTripsDeliveriesTable =>
          $$CachedTripsDeliveriesTableTableTableManager(
              _db, _db.cachedTripsDeliveriesTable);
}
