import 'types.dart';

class QueryOptions<T> {
  final Future<T> Function() queryFn;
  final List<Object> queryKey;
  final double? staleTime;
  final bool? enabled;
  final bool? refetchOnRestart;
  final bool? refetchOnReconnect;

  const QueryOptions({
    required this.queryFn,
    required this.queryKey,
    this.staleTime,
    this.enabled,
    this.refetchOnRestart,
    this.refetchOnReconnect,
  });

  QueryOptions<T> copyWith({
    Future<T> Function()? queryFn,
    List<Object>? queryKey,
    double? staleTime,
    bool? enabled,
    bool? refetchOnRestart,
    bool? refetchOnReconnect,
  }) {
    return QueryOptions<T>(
      queryFn: queryFn ?? this.queryFn,
      queryKey: queryKey ?? this.queryKey,
      staleTime: staleTime ?? this.staleTime,
      enabled: enabled ?? this.enabled,
      refetchOnRestart: refetchOnRestart ?? this.refetchOnRestart,
      refetchOnReconnect: refetchOnReconnect ?? this.refetchOnReconnect,
    );
  }
}

class QueryResult<T> {
  String key;
  QueryStatus status;
  T? data;
  /// Whether the query is currently fetching (background refetches etc).
  bool isFetching;
  Object? error;

  QueryResult(this.key, this.status, this.data, this.error, {this.isFetching = false});

  bool get isError => status == QueryStatus.error;
  bool get isSuccess => status == QueryStatus.success;
  bool get isPending => status == QueryStatus.pending;
}

class InfiniteQueryResult<T> extends QueryResult<List<T>> {
  bool isFetchingNextPage;
  Function? fetchNextPage;

  InfiniteQueryResult({
    required String key,
    required QueryStatus status,
    required List<T> data,
    required bool isFetching,
    required Object? error,
    required this.isFetchingNextPage,
    this.fetchNextPage,
  }) : super(key, status, data, error, isFetching: isFetching);

  InfiniteQueryResult<T> copyWith({
    String? key,
    List<T>? data,
    QueryStatus? status,
    bool? isFetching,
    Object? error,
    bool? isFetchingNextPage,
    Function? fetchNextPage,
  }) {
    return InfiniteQueryResult<T>(
      key: key ?? this.key,
      data: data ?? this.data!,
      status: status ?? this.status,
      isFetching: isFetching ?? this.isFetching,
      error: error ?? this.error,
      isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
      fetchNextPage: fetchNextPage ?? this.fetchNextPage,
    );
  }
}
