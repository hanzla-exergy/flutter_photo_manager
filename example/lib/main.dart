import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:oktoast/oktoast.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import 'model/photo_provider.dart';
import 'page/index_page.dart';
import 'widget/image_item_widget.dart';

final PhotoProvider provider = PhotoProvider();

void main() {
  runZonedGuarded(
    () => runApp(const _SimpleExampleApp()),
    (Object e, StackTrace s) {
      if (kDebugMode) {
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s));
      }
      showToast('$e\n$s', textAlign: TextAlign.start);
    },
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
}

class _SimpleExampleApp extends StatelessWidget {
  const _SimpleExampleApp();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PhotoProvider>.value(
      value: provider, // This is for the advanced usages.
      child: MaterialApp(
        title: 'Photo Manager Example',
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
        ),
        themeMode: ThemeMode.system,
        builder: (context, child) {
          if (child == null) {
            return const SizedBox.shrink();
          }
          return Banner(
            message: 'Debug',
            location: BannerLocation.bottomStart,
            child: OKToast(child: child),
          );
        },
        home: const _SimpleExamplePage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class _SimpleExamplePage extends StatefulWidget {
  const _SimpleExamplePage();

  @override
  _SimpleExamplePageState createState() => _SimpleExamplePageState();
}

class _SimpleExamplePageState extends State<_SimpleExamplePage> {
  final int _sizePerPage = 50;

  AssetPathEntity? _path;
  List<AssetEntity>? _entities;
  int _totalEntitiesCount = 0;

  int _page = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreToLoad = true;

  // Grouped entities by date
  Map<String, List<AssetEntity>> _groupedEntities = {};
  List<String> _dateKeys = [];

  void _groupEntitiesByDate(List<AssetEntity> entities) {
    final Map<String, List<AssetEntity>> grouped = {};

    for (final entity in entities) {
      final DateTime createDate = entity.createDateTime;
      final String dateKey = DateFormat('yyyy-MM-dd').format(createDate);

      if (grouped.containsKey(dateKey)) {
        grouped[dateKey]!.add(entity);
      } else {
        grouped[dateKey] = [entity];
      }
    }

    // Sort date keys in descending order (most recent first)
    final List<String> sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    _groupedEntities = grouped;
    _dateKeys = sortedKeys;
  }

  String _formatDateHeader(String dateKey) {
    final DateTime date = DateTime.parse(dateKey);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));
    final DateTime dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMMM dd, yyyy').format(date);
    }
  }

  Future<void> _requestAssets() async {
    setState(() {
      _isLoading = true;
    });
    // Request permissions.
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!mounted) {
      return;
    }
    // Further requests can be only proceed with authorized or limited.
    if (!ps.hasAccess) {
      setState(() {
        _isLoading = false;
      });
      showToast('Permission is not accessible.');
      return;
    }
    // Customize your own filter options.
    final PMFilter filter = FilterOptionGroup(
      imageOption: const FilterOption(
        sizeConstraint: SizeConstraint(ignoreSize: true),
      ),
    );
    // Obtain assets using the path entity.
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      filterOption: filter,
    );
    if (!mounted) {
      return;
    }
    // Return if not paths found.
    if (paths.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      showToast('No paths found.');
      return;
    }
    setState(() {
      _path = paths.first;
    });
    _totalEntitiesCount = await _path!.assetCountAsync;
    final List<AssetEntity> entities = await _path!.getAssetListPaged(
      page: 0,
      size: _sizePerPage,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _entities = entities;
      _groupEntitiesByDate(entities);
      _isLoading = false;
      _hasMoreToLoad = _entities!.length < _totalEntitiesCount;
    });
  }

  Future<void> _loadMoreAsset() async {
    setState(() {
      _isLoadingMore = true;
    });
    final List<AssetEntity> entities = await _path!.getAssetListPaged(
      page: _page + 1,
      size: _sizePerPage,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _entities!.addAll(entities);
      _groupEntitiesByDate(_entities!);
      _page++;
      _hasMoreToLoad = _entities!.length < _totalEntitiesCount;
      _isLoadingMore = false;
    });
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final entities = _entities;
    if (entities == null) {
      return const Center(child: Text('Click buttons to request assets.'));
    }
    if (entities.isEmpty) {
      return const Center(child: Text('No assets found on this device.'));
    }

    return CustomScrollView(
      slivers: [
        ..._buildDateSections(),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          ),
        if (_hasMoreToLoad && !_isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: TextButton(
                  onPressed: _loadMoreAsset,
                  child: const Text('Load More'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildDateSections() {
    final List<Widget> sections = [];

    for (final dateKey in _dateKeys) {
      final List<AssetEntity> dateEntities = _groupedEntities[dateKey]!;

      // Add date header
      sections.add(
        SliverToBoxAdapter(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              _formatDateHeader(dateKey),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
      );

      // Add grid of images for this date
      sections.add(
        SliverPadding(
          padding: const EdgeInsets.all(2.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 2.0,
              mainAxisSpacing: 2.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                final AssetEntity entity = dateEntities[index];
                return ImageItemWidget(
                  key: ValueKey<String>('${dateKey}_$index'),
                  entity: entity,
                  option:
                      const ThumbnailOption(size: ThumbnailSize.square(200)),
                );
              },
              childCount: dateEntities.length,
            ),
          ),
        ),
      );
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('photo_manager')),
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'This page will only obtain the first page of assets '
              'under the primary album (a.k.a. Recent). '
              'If you want more filtering assets, '
              'head over to "Advanced usages".',
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
      persistentFooterButtons: <TextButton>[
        TextButton(
          onPressed: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const IndexPage()),
            );
          },
          child: const Text('Advanced usages'),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: _requestAssets,
        child: const Icon(Icons.developer_board),
      ),
    );
  }
}
