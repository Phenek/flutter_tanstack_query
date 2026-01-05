---
id: overview
title: Overview
---

Flutter TanStack Query is often described as the missing data-fetching library for applications, but in more technical terms, it makes **fetching, caching, synchronizing and updating server state** in your applications a breeze.

> [flutter-tanstack-query](https://flutter-tanstack.com) is maintained by independent Flutter developers and is **not affiliated** with the official [TanStack](https://tanstack.com) team. This library and its documentation are a **COPY CAT** 
they intentionally follow TanStack Query's API architecture and design, mirroring many aspects of the original JavaScript library.

## Motivation

Flutter does not yet have a widely-adopted, opinionated solution for server-state management like TanStack Query provides for JavaScript. As a result, Flutter developers often end up inventing ad-hoc approaches that mix component state, side-effects, and general-purpose state libraries approaches that are not optimized for the unique challenges of asynchronous, shared server state.

Flutter TanStack Query was started to fill that gap. It brings the patterns and primitives needed for fetching, caching, synchronizing, and updating server state to Flutter apps, following TanStack Query's API and behavior where practical so Flutter developers can use a proven, consistent approach.

While most traditional state management libraries are great for working with client state, they are **not so great at working with async or server state**. This is because **server state is totally different**. For starters, server state:


- Is persisted remotely in a location you may not control or own
- Requires asynchronous APIs for fetching and updating
- Implies shared ownership and can be changed by other people without your knowledge
- Can potentially become "out of date" in your applications if you're not careful

Once you grasp the nature of server state in your application, **even more challenges will arise** as you go, for example:

- Caching... (possibly the hardest thing to do in programming)
- Deduping multiple requests for the same data into a single request
- Updating "out of date" data in the background
- Knowing when data is "out of date"
- Reflecting updates to data as quickly as possible
- Performance optimizations like pagination and lazy loading data
- Managing memory and garbage collection of server state
- Memoizing query results with structural sharing

If you're not overwhelmed by that list, then that must mean that you've probably solved all of your server state problems already and deserve an award. However, if you are like a vast majority of people, you either have yet to tackle all or most of these challenges and we're only scratching the surface!

TanStack Query is hands down one of the _best_ libraries for managing server state. It works amazingly well **out-of-the-box, with zero-config, and can be customized** to your liking as your application grows.

TanStack Query allows you to defeat and overcome the tricky challenges and hurdles of _server state_ and control your app data before it starts to control you.

On a more technical note, TanStack Query will likely:

- Help you remove **many** lines of complicated and misunderstood code from your application and replace with just a handful of lines of TanStack Query logic
- Make your application more maintainable and easier to build new features without worrying about wiring up new server state data sources
- Have a direct impact on your end-users by making your application feel faster and more responsive than ever before
- Potentially help you save on bandwidth and increase memory performance

[//]: # 'Example'

## Enough talk, show me some code already!

In the example below, you can see TanStack Query in its most basic and simple form being used to fetch the GitHub stats for the TanStack Query GitHub project itself:

```dart
import 'package:flutter/material.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

final queryClient = QueryClient();

void main() {
  runApp(
    QueryClientProvider(client: queryClient, child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Example()),
      ),
    );
  }
}

class Example extends HookWidget {
  const Example({super.key});

  @override
  Widget build(BuildContext context) {

    final result = useQuery<Map<String, dynamic>>(
      queryKey: ['repoData'],
      queryFn: () async {
        final res = await http.get(Uri.parse('https://api.github.com/repos/TanStack/query'));
        if (res.statusCode != 200) throw Exception('Failed to load repo data');
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
    );

    if (result.isPending) return const Text('Loading...');

    if (result.error != null) {
      return Text('An error has occurred: ${result.error}');
    }

    final data = result.data!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data['name'],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(data['description'] ?? ''),
        const SizedBox(height: 8),
        Text('👀 ${data['subscribers_count']}  ✨ ${data['stargazers_count']}  🍴 ${data['forks_count']}'),
      ],
    );
  }
}
```

[//]: # 'Example'