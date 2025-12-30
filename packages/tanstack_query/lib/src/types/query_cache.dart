import 'types.dart';

/// Configuration callbacks for query cache events like `onError` and `onSuccess`.
class QueryCacheConfig {
  /// Called when a query fetch results in an error.
  final void Function(dynamic error)? onError;

  /// Called when a query fetch completes successfully.
  final void Function(dynamic data)? onSuccess;

  QueryCacheConfig({this.onError, this.onSuccess});
}

/// Simple holder for query cache configuration.
class QueryCache {
  /// Configuration containing callbacks for query lifecycle events.
  final QueryCacheConfig config;

  QueryCache({required this.config});
}

/// A cache entry storing the last query [result], a [timestamp] and optionally
/// a running [queryFnRunning] future.
///
/// - `result`: The last stored `QueryResult` or `InfiniteQueryResult` produced
///   by the UI layer.
/// - `timestamp`: When the value was cached (used to compute staleness).
/// - `queryFnRunning`: If non-null, a `TrackedFuture` representing an in-flight
///   fetch for this key.
class CacheQuery<T> {
  final dynamic
      result; // can be QueryResult/InfiniteQueryResult from flutter layer
  final DateTime timestamp;
  late TrackedFuture<T>? queryFnRunning;

  CacheQuery(this.result, this.timestamp, {this.queryFnRunning});
}

/// Listener registered for cache updates and refetch callbacks.
///
/// Fields:
/// - [id]: Unique identifier used to avoid notifying the originating caller
///   when a cache update is performed.
/// - [isInfinite]: Whether the listener handles `InfiniteQueryResult` payloads.
/// - [refetchCallBack]: Callback to request a full refetch (used by invalidation
///   and refetch-on-reconnect/restart behavior).
/// - [listenUpdateCallBack]: Callback invoked when new query results are
///   available for the registered key.
class QueryCacheListener {
  /// Unique listener id used to avoid sending updates to the caller that
  /// triggered the change.
  final String id;

  /// Whether this listener expects infinite query payloads.
  bool isInfinite;

  /// Callback invoked to request a refetch.
  final Function() refetchCallBack;

  /// Callback invoked to deliver updated query results to the listener.
  final Function(dynamic) listenUpdateCallBack;

  /// Optional flag to override the default refetch-on-restart behavior.
  bool? refetchOnRestart;

  /// Optional flag to override the default refetch-on-reconnect behavior.
  bool? refetchOnReconnect;

  QueryCacheListener(
      this.id,
      this.isInfinite,
      this.refetchCallBack,
      this.listenUpdateCallBack,
      this.refetchOnRestart,
      this.refetchOnReconnect);
}
